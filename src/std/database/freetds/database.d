module std.database.freetds.database;
pragma(lib, "sybdb");

import std.database.common;
import std.database.exception;
import std.database.resolver;

import std.database.freetds.bindings;

import std.string;
import core.stdc.stdlib;
import std.conv;
import std.typecons;
import std.container.array;
import std.experimental.logger;
public import std.database.allocator;
import std.database.impl;
import std.datetime;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

alias Database(T) = BasicDatabase!(Impl.Database!T);
alias Connection(T) = BasicConnection!(Impl.Connection!T);
alias Statement(T) = BasicStatement!(Impl.Statement!T);
alias Result(T) = BasicResult!(Impl.Result!T);
alias ResultRange(T) = BasicResultRange!(Impl.Result!T);
alias Row(T) = BasicRow!(Impl.Result!T);
alias Value(T) = BasicValue!(Impl.Result!T);

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

struct Impl {

    private static bool isError(RETCODE ret) {
        return 
            ret != SUCCEED &&
            ret != REG_ROW &&
            ret != NO_MORE_ROWS &&
            ret != NO_MORE_RESULTS;
    }

    static T* check(T)(string msg, T* object) {
        info(msg);
        if (object == null) throw new DatabaseException("error: " ~ msg);
        return object;
    }

    static RETCODE check(string msg, RETCODE ret) {
        info(msg, " : ", ret);
        if (isError(ret)) throw new DatabaseException("error: " ~ msg);
        return ret;
    }

    struct Database(T) {
        alias Allocator = T.Allocator;
        alias Connection = Impl.Connection!T;
        alias queryVariableType = QueryVariableType.QuestionMark;

        bool bindable() {return false;}
        bool dateBinding() {return false;}
        bool poolEnable() {return false;}

        Allocator allocator;

        this(string defaultURI_) {
            info("Database");
            allocator = Allocator();
            check("dbinit", dbinit());
            dberrhandle(&errorHandler);
            dbmsghandle(&msgHandler);
        }

        ~this() {
            info("~Database");
            //dbexit(); // should this be called (only on process exit?)
        }


        static extern(C) int errorHandler(
                DBPROCESS* dbproc,
                int severity,
                int dberr,
                int oserr,
                char *dberrstr,
                char *oserrstr) {

            auto con = cast(Connection *) dbgetuserdata(dbproc);
            if (con) {
                con.error.message = to!string(dberrstr);
            }
            info("error: ",
                    "severity: ", severity,
                    ", db error: ", to!string(dberrstr),
                    ", os error: ", to!string(oserrstr));

            return INT_CANCEL;
        }

        static extern(C) int msgHandler(
                DBPROCESS *dbproc,
                DBINT msgno,
                int msgstate,
                int severity,
                char *msgtext,
                char *srvname,
                char *procname,
                int line) {

            auto con = cast(Connection *) dbgetuserdata(dbproc);
            if (con) {}
            info("msg: ", to!string(msgtext), ", severity:", severity);
            return 0;
        }

    }

    struct Connection(T) {
        alias Allocator = T.Allocator;
        alias Database = Impl.Database!T;
        alias Statement = Impl.Statement!T;

        Database* db;
        string source;
        LOGINREC *login;
        DBPROCESS *con;

        DatabaseError error;

        this(Database* db_, string source_) {
            db = db_;
            source = source_;

            info("Connection: ", source);

            Source src = resolve(source);

            login = check("dblogin", dblogin());

            check("dbsetlname", dbsetlname(login, toStringz(src.username), DBSETUSER));
            check("dbsetlname", dbsetlname(login, toStringz(src.password), DBSETPWD));

            //con = dbopen(login, toStringz(src.server));
            con = check("tdsdbopen", tdsdbopen(login, toStringz(src.server), 1));

            dbsetuserdata(con, cast(BYTE*) &this);

            check("dbuse", dbuse(con, toStringz(src.database)));
        }

        ~this() {
            info("~Connection: ", source);
            if (con) dbclose(con);
            if (login) dbloginfree(login);
        }

    }

    struct Statement(T) {
        alias Connection = Impl.Connection!T;
        //alias Bind = Impl.Bind!T;
        alias Result = Impl.Result!T;
        alias Allocator = T.Allocator;

        Connection* con;
        string sql;
        Allocator *allocator;
        int binds;
        //Array!Bind inputbind_;

        this(Connection* con_, string sql_) {
            info("Statement");
            con = con_;
            sql = sql_;
            allocator = &con.db.allocator;
        }

        ~this() {
            info("~Statement");
        }

        void prepare() {
            check("dbcmd: " ~ sql, dbcmd(con.con, toStringz(sql)));
        }

        void query() {
            RETCODE status = check("dbsqlexec: ", dbsqlexec(con.con));
        }

        void query(X...) (X args) {
            bindAll(args);
            query();
        }

        private void bindAll(T...) (T args) {
            //int col;
            //foreach (arg; args) bind(++col, arg);
        }

        void bind(int n, int value) {}
        void bind(int n, const char[] value) {}

        void reset() {
        }

        private RETCODE check(string msg, RETCODE ret) {
            info(msg, " : ", ret);
            if (isError(ret)) throw new DatabaseException(con.error, msg);
            return ret;
        }
    }

    struct Describe(T) {
        char *name;
        char *buffer;
        int type;
        int size;
        int status;
    }

    struct Bind(T) {
        ValueType type;
        int bindType;
        int size;
        void[] data;
        DBINT status;
    }

    struct Result(T) {
        alias Allocator = T.Allocator;
        alias Statement = Impl.Statement!T;
        alias Describe = Impl.Describe!T;
        alias Bind = Impl.Bind!T;

        //int columns() {return columns;}

        Statement* stmt;
        Allocator *allocator;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        RETCODE status;

        private auto con() {return stmt.con;}
        private auto dbproc() {return con.con;}

        this(Statement* stmt_) {
            stmt = stmt_;
            allocator = stmt.allocator;

            status = check("dbresults", dbresults(dbproc));
            if (status == NO_MORE_RESULTS) return;

            columns = dbnumcols(dbproc);
            info("COLUMNS:", columns);

            //if (!columns) return;

            build_describe();
            build_bind();
            next();
        }

        ~this() {
            foreach(b; bind) allocator.deallocate(b.data);
        }

        void build_describe() {

            describe.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                int c = i+1;
                describe ~= Describe();
                auto d = &describe.back();

                d.name = dbcolname(dbproc, c);
                d.type = dbcoltype(dbproc, c);
                d.size = dbcollen(dbproc, c);

                info("NAME: ", to!string(d.name), ", type: ", d.type);
            }
        }

        void build_bind() {
            import core.memory : GC;

            bind.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                int c = i+1;
                bind ~= Bind();
                auto b = &bind.back();
                auto d = &describe[i];

                int allocSize;
                switch (d.type) {
                    case SYBCHAR:
                        b.type = ValueType.String;
                        b.size = 255;
                        allocSize = b.size+1;
                        b.bindType = NTBSTRINGBIND;
                        break;
                    default: 
                        b.type = ValueType.String;
                        b.size = 255;
                        allocSize = b.size+1;
                        b.bindType = NTBSTRINGBIND;
                        break;
                }

                b.data = allocator.allocate(allocSize); // make consistent acros dbs
                GC.addRange(b.data.ptr, b.data.length);

                check("dbbind", dbbind(
                            dbproc,
                            c,
                            b.bindType,
                            cast(DBINT) b.data.length,
                            cast(BYTE*) b.data.ptr));

                check("dbnullbind", dbnullbind(dbproc, c, &b.status));

                info(
                        "output bind: index: ", i,
                        ", type: ", b.bindType,
                        ", size: ", b.size,
                        ", allocSize: ", b.data.length);
            }
        }

        bool start() {return status == REG_ROW;}

        bool next() {
            status = check("dbnextrow", dbnextrow(dbproc));
            if (status == REG_ROW) {
                return true; 
            } else if (status == NO_MORE_ROWS) {
                stmt.reset();
                return false;
            }
            return false;
        }

        auto get(X:string)(Bind *b) {
            import core.stdc.string: strlen;
            checkType(b.bindType, NTBSTRINGBIND);
            auto ptr = cast(immutable char*) b.data.ptr;
            return cast(string) ptr[0..strlen(ptr)];
        }

        auto get(X:int)(Bind *b) {
            //if (b.bindType == SQL_C_CHAR) return to!int(as!string()); // tmp hack
            //checkType(b.bindType, SQL_C_LONG);
            //return *(cast(int*) b.data);
            return 0;
        }

        auto get(X:Date)(Bind *b) {
            return Date(2016,1,1); // fix
        }

        void checkType(int a, int b) {
            if (a != b) throw new DatabaseException("type mismatch");
        }

    }

}

