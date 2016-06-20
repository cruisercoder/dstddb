module std.database.freetds.database;
pragma(lib, "sybdb");

import std.database.common;
import std.database.exception;
import std.database.source;

import std.database.freetds.bindings;

import std.string;
import core.stdc.stdlib;
import std.conv;
import std.typecons;
import std.container.array;
import std.experimental.logger;
public import std.database.allocator;
import std.database.front;
import std.datetime;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

alias Database(T) = BasicDatabase!(Driver!T,T);

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}


struct Driver(Policy) {
    alias Allocator = Policy.Allocator;
    alias Cell = BasicCell!(Driver!Policy,Policy);

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

    struct Database {
        alias queryVariableType = QueryVariableType.QuestionMark;

        static const FeatureArray features = [
            //Feature.InputBinding,
            //Feature.DateBinding,
            //Feature.ConnectionPool,
            ];

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

    struct Connection {
        Database* db;
        Source source;
        LOGINREC *login;
        DBPROCESS *con;

        DatabaseError error;

        this(Database* db_, Source source_) {
            db = db_;
            source = source_;

            //info("Connection: ");

            login = check("dblogin", dblogin());

            check("dbsetlname", dbsetlname(login, toStringz(source.username), DBSETUSER));
            check("dbsetlname", dbsetlname(login, toStringz(source.password), DBSETPWD));

            // if host is present, then specify server as direct host:port
            // otherwise just past a name for freetds name lookup

            string server;
            if (source.host.length != 0) {
                server = source.host ~ ":" ~ to!string(source.port);
            } else {
                server = source.server;
            }

            //con = dbopen(login, toStringz(source.server));
            con = check("tdsdbopen: " ~ server, tdsdbopen(login, toStringz(server), 1));

            dbsetuserdata(con, cast(BYTE*) &this);

            check("dbuse", dbuse(con, toStringz(source.database)));
        }

        ~this() {
            //info("~Connection: ", source);
            if (con) dbclose(con);
            if (login) dbloginfree(login);
        }

    }

    struct Statement {
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

        //bool hasRows() {return status != NO_MORE_RESULTS;}
        bool hasRows() {return true;}

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

    struct Describe {
        char *name;
        char *buffer;
        int type;
        int size;
        int status;
    }

    struct Bind {
        ValueType type;
        int bindType;
        int size;
        void[] data;
        DBINT status;
    }

    struct Result {
        //int columns() {return columns;}

        Statement* stmt;
        Allocator *allocator;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        RETCODE status;

        private auto con() {return stmt.con;}
        private auto dbproc() {return con.con;}

        this(Statement* stmt_, int rowArraySize_) {
            stmt = stmt_;
            allocator = stmt.allocator;
            status = check("dbresults", dbresults(dbproc));
            columns = dbnumcols(dbproc);
            build_describe();
            build_bind();
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
                    case SYBMSDATE:
                        b.type = ValueType.Date;
                        b.size = DBDATETIME.sizeof;
                        allocSize = b.size;
                        b.bindType = DATETIMEBIND;
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

        int fetch() {
            status = check("dbnextrow", dbnextrow(dbproc));
            if (status == REG_ROW) {
                return 1; 
            } else if (status == NO_MORE_ROWS) {
                stmt.reset();
                return 0;
            }
            return 0;
        }

        auto name(size_t idx) {
            return to!string(describe[idx].name);
        }

        auto get(X:string)(Cell* cell) {
            import core.stdc.string: strlen;
            checkType(cell.bind.bindType, NTBSTRINGBIND);
            auto ptr = cast(immutable char*) cell.bind.data.ptr;
            return cast(string) ptr[0..strlen(ptr)];
        }

        auto get(X:int)(Cell* cell) {
            //if (b.bindType == SQL_C_CHAR) return to!int(as!string()); // tmp hack
            //checkType(b.bindType, SQL_C_LONG);
            //return *(cast(int*) b.data);
            return 0;
        }

        auto get(X:Date)(Cell* cell) {
            auto ptr = cast(DBDATETIME*) cell.bind.data.ptr;
            DBDATEREC d;
            check("dbdatecrack", dbdatecrack(dbproc, &d, ptr));
            return Date(d.year, d.month, d.day);
        }

        void checkType(int a, int b) {
            if (a != b) throw new DatabaseException("type mismatch");
        }

    }

}

