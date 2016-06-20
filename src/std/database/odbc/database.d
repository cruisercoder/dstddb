module std.database.odbc.database;
pragma(lib, "odbc");

import std.database.common;
import std.database.exception;
import std.database.source;
import etc.c.odbc.sql;
import etc.c.odbc.sqlext;
import etc.c.odbc.sqltypes;
import etc.c.odbc.sqlucode;

import std.string;
import core.stdc.stdlib;
import std.conv;
import std.typecons;
import std.container.array;
import std.experimental.logger;
public import std.database.allocator;
import std.database.front;
import std.datetime;

//alias long SQLLEN;
//alias ubyte SQLULEN;

alias SQLINTEGER SQLLEN;
alias SQLUINTEGER SQLULEN;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

alias Database(T) = BasicDatabase!(Driver!T,T);

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

struct Driver(Policy) {
    alias Allocator = Policy.Allocator;
    alias Cell = BasicCell!(Driver,Policy);

    struct Database {
        alias queryVariableType = QueryVariableType.QuestionMark;

        static const FeatureArray features = [
            //Feature.InputBinding,
            //Feature.DateBinding,
            Feature.ConnectionPool,
            ];

        Allocator allocator;
        SQLHENV env;

        this(string defaultURI_) {
            info("Database");
            allocator = Allocator();
            check(
                    "SQLAllocHandle", 
                    SQLAllocHandle(
                        SQL_HANDLE_ENV, 
                        SQL_NULL_HANDLE,
                        &env));
            SQLSetEnvAttr(env, SQL_ATTR_ODBC_VERSION, cast(void *) SQL_OV_ODBC3, 0);
        }

        ~this() {
            info("~Database");
            if (!env) return;
            check("SQLFreeHandle", SQL_HANDLE_ENV, env, SQLFreeHandle(SQL_HANDLE_ENV, env));
            env = null;
        }

        void showDrivers() {
            import core.stdc.string: strlen;

            SQLUSMALLINT direction;

            SQLCHAR[256] driver;
            SQLCHAR[256] attr;
            SQLSMALLINT driver_ret;
            SQLSMALLINT attr_ret;
            SQLRETURN ret;

            direction = SQL_FETCH_FIRST;
            info("DRIVERS:");
            while(SQL_SUCCEEDED(ret = SQLDrivers(
                            env, 
                            direction,
                            driver.ptr, 
                            driver.sizeof, 
                            &driver_ret,
                            attr.ptr, 
                            attr.sizeof, 
                            &attr_ret))) {
                direction = SQL_FETCH_NEXT;
                info(driver.ptr[0..strlen(driver.ptr)], ": ", attr.ptr[0..strlen(attr.ptr)]);
                //if (ret == SQL_SUCCESS_WITH_INFO) printf("\tdata truncation\n");
            }
        }
    }

    struct Connection {
        Database* db;
        Source source;
        SQLHDBC con;
        bool connected;

        this(Database* db_, Source source_) {
            db = db_;
            source = source_;

            info("Connection: ", source);

            char[1024] outstr;
            SQLSMALLINT outstrlen;
            //string DSN = "DSN=testdb";

            SQLRETURN ret = SQLAllocHandle(SQL_HANDLE_DBC,db.env,&con);
            if ((ret != SQL_SUCCESS) && (ret != SQL_SUCCESS_WITH_INFO)) {
                throw new DatabaseException("SQLAllocHandle error: " ~ to!string(ret));
            }

            check("SQLConnect", SQL_HANDLE_DBC, con, SQLConnect(
                        con,
                        cast(SQLCHAR*) toStringz(source.server),
                        SQL_NTS,
                        cast(SQLCHAR*) toStringz(source.username),
                        SQL_NTS,
                        cast(SQLCHAR*) toStringz(source.password),
                        SQL_NTS));
            connected = true;
        }

        ~this() {
            info("~Connection: ", source);
            if (connected) check("SQLDisconnect()", SQL_HANDLE_DBC, con, SQLDisconnect(con));
            check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_DBC, con));
        }
    }

    struct Statement {
        Connection* con;
        string sql;
        Allocator *allocator;
        SQLHSTMT stmt;
        bool hasRows_; // not working
        int binds;
        Array!Bind inputbind_;

        this(Connection* con_, string sql_) {
            info("Statement");
            con = con_;
            sql = sql_;
            allocator = &con.db.allocator;
            check("SQLAllocHandle", SQLAllocHandle(SQL_HANDLE_STMT, con.con, &stmt));
        }

        ~this() {
            info("~Statement");
            for(int i = 0; i < inputbind_.length; ++i) {
                allocator.deallocate(inputbind_[i].data[0..inputbind_[i].allocSize]);
            }
            if (stmt) check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_STMT, stmt));
            // stmt = null? needed
        }

        void bind(int n, int value) {
            info("input bind: n: ", n, ", value: ", value);

            Bind b;
            b.bindType = SQL_C_LONG;
            b.dbtype = SQL_INTEGER;
            b.size = SQLINTEGER.sizeof;
            b.allocSize = b.size;
            b.data = cast(void*)(allocator.allocate(b.allocSize));
            inputBind(n, b);

            *(cast(SQLINTEGER*) inputbind_[n-1].data) = value;
        }

        void bind(int n, const char[] value){
            import core.stdc.string: strncpy;
            info("input bind: n: ", n, ", value: ", value);
            // no null termination needed

            Bind b;
            b.bindType = SQL_C_CHAR;
            b.dbtype = SQL_CHAR;
            b.size = cast(SQLSMALLINT) value.length;
            b.allocSize = b.size;
            b.data = cast(void*)(allocator.allocate(b.allocSize));
            inputBind(n, b);

            strncpy(cast(char*) b.data, value.ptr, b.size);
        }

        void bind(int n, Date d) {
        }

        void inputBind(int n, ref Bind bind) {
            inputbind_ ~= bind;
            auto b = &inputbind_.back();

            check("SQLBindParameter", SQLBindParameter(
                        stmt,
                        cast(SQLSMALLINT) n,
                        SQL_PARAM_INPUT,
                        b.bindType,
                        b.dbtype,
                        0,
                        0,
                        b.data,
                        b.allocSize,
                        null));
        }


        void prepare() {
            //if (!data_.st)
            check("SQLPrepare", SQLPrepare(
                        stmt,
                        cast(SQLCHAR*) toStringz(sql),
                        SQL_NTS));

            SQLSMALLINT v;
            check("SQLNumParams", SQLNumParams(stmt, &v));
            binds = v;
            check("SQLNumResultCols", SQLNumResultCols (stmt, &v));
            info("binds: ", binds);
        }

        void query() {
            if (!binds) {
                info("sql execute direct: ", sql);
                SQLRETURN ret = SQLExecDirect(
                        stmt,
                        cast(SQLCHAR*) toStringz(sql),
                        SQL_NTS);
                check("SQLExecuteDirect()", SQL_HANDLE_STMT, stmt, ret);
                hasRows_ = ret != SQL_NO_DATA;
            } else {
                info("sql execute prepared: ", sql);
                SQLRETURN ret = SQLExecute(stmt);
                check("SQLExecute()", SQL_HANDLE_STMT, stmt, ret);
                hasRows_ = ret != SQL_NO_DATA;
            }
        }

        void query(X...) (X args) {
            bindAll(args);
            query();
        }

        bool hasRows() {return hasRows_;}

        void exec() {
            check("SQLExecDirect", SQLExecDirect(stmt,cast(SQLCHAR*) toStringz(sql), SQL_NTS));
        }

        void reset() {
            //SQLCloseCursor
        }

        private void bindAll(T...) (T args) {
            int col;
            foreach (arg; args) {
                bind(++col, arg);
            }
        }
    }


    struct Describe {
        static const nameSize = 256;
        char[nameSize] name;
        SQLSMALLINT nameLen;
        SQLSMALLINT type;
        SQLULEN size; 
        SQLSMALLINT digits;
        SQLSMALLINT nullable;
        SQLCHAR* data;
        //SQLCHAR[256] data;
        SQLLEN datLen;
    }

    struct Bind {
        ValueType type;

        SQLSMALLINT bindType;
        SQLSMALLINT dbtype;
        //SQLCHAR* data[maxData];
        void* data;

        // apparently the crash problem
        //SQLULEN size; 
        //SQLULEN allocSize; 
        //SQLLEN len;

        SQLINTEGER size; 
        SQLINTEGER allocSize; 
        SQLINTEGER len;
    }

    struct Result {
        //int columns() {return columns;}

        static const maxData = 256;

        Statement* stmt;
        Allocator *allocator;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        SQLRETURN status;

        this(Statement* stmt_, int rowArraySize_) {
            stmt = stmt_;
            allocator = stmt.allocator;

            // check for result set (probably a better way)
            //if (!stmt.hasRows) return;
            SQLSMALLINT v;
            check("SQLNumResultCols", SQLNumResultCols (stmt.stmt, &v));
            columns = v;
            build_describe();
            build_bind();
        }

        ~this() {
            for(int i = 0; i < bind.length; ++i) {
                free(bind[i].data);
            }
        }

        void build_describe() {

            describe.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                describe ~= Describe();
                auto d = &describe.back();

                check("SQLDescribeCol", SQLDescribeCol(
                            stmt.stmt,
                            cast(SQLUSMALLINT) (i+1),
                            cast(SQLCHAR *) d.name,
                            cast(SQLSMALLINT) Describe.nameSize,
                            &d.nameLen,
                            &d.type,
                            &d.size,
                            &d.digits,
                            &d.nullable));

                //info("NAME: ", d.name, ", type: ", d.type);
            }
        }

        void build_bind() {
            import core.memory : GC;

            bind.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                bind ~= Bind();
                auto b = &bind.back();
                auto d = &describe[i];

                b.size = d.size;
                b.allocSize = cast(SQLULEN) (b.size + 1);
                b.data = cast(void*)(allocator.allocate(b.allocSize));
                GC.addRange(b.data, b.allocSize);

                // just INT and VARCHAR for now
                switch (d.type) {
                    case SQL_INTEGER:
                        //b.type = SQL_C_LONG;
                        b.type = ValueType.String;
                        b.bindType = SQL_C_CHAR;
                        break;
                    case SQL_VARCHAR:
                        b.type = ValueType.String;
                        b.bindType = SQL_C_CHAR;
                        break;
                    default: 
                        throw new DatabaseException("bind error: type: " ~ to!string(d.type));
                }

                check("SQLBINDCol", SQLBindCol (
                            stmt.stmt,
                            cast(SQLUSMALLINT) (i+1),
                            b.bindType,
                            b.data,
                            b.size,
                            &b.len));

                info(
                        "output bind: index: ", i,
                        ", type: ", b.bindType,
                        ", size: ", b.size,
                        ", allocSize: ", b.allocSize);
            }
        }

        int fetch() {
            //info("SQLFetch");
            status = SQLFetch(stmt.stmt);
            if (status == SQL_SUCCESS) {
                return 1; 
            } else if (status == SQL_NO_DATA) {
                stmt.reset();
                return 0;
            }
            check("SQLFetch", SQL_HANDLE_STMT, stmt.stmt, status);
            return 0;
        }

        auto name(size_t idx) {
            auto d = &describe[idx];
            return cast(string) d.name[0..d.nameLen];
        }

        auto get(X:string)(Cell* cell) {
            checkType(cell.bind.bindType, SQL_C_CHAR);
            auto ptr = cast(immutable char*) cell.bind.data;
            return cast(string) ptr[0..cell.bind.len];
        }

        auto get(X:int)(Cell* cell) {
            //if (b.bindType == SQL_C_CHAR) return to!int(as!string()); // tmp hack
            checkType(cell.bind.bindType, SQL_C_LONG);
            return *(cast(int*) cell.bind.data);
        }

        auto get(X:Date)(Cell* cell) {
            return Date(2016,1,1); // fix
        }

        void checkType(SQLSMALLINT a, SQLSMALLINT b) {
            if (a != b) throw new DatabaseException("type mismatch");
        }

    }

    static void check()(string msg, SQLRETURN ret) {
        info(msg, ":", ret);
        if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO || ret == SQL_NO_DATA) return;
        throw new DatabaseException("odbc error: " ~ msg);
    }

    static void check()(string msg, SQLSMALLINT handle_type, SQLHANDLE handle, SQLRETURN ret) {
        info(msg, ":", ret);
        if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO || ret == SQL_NO_DATA) return;
        throw_detail(handle, handle_type, msg);
    }

    static void throw_detail()(SQLHANDLE handle, SQLSMALLINT type, string msg) {
        SQLSMALLINT i = 0;
        SQLINTEGER native;
        SQLCHAR[7] state;
        SQLCHAR[256] text;
        SQLSMALLINT len;
        SQLRETURN ret;

        string error;
        error ~= msg;
        error ~= ": ";

        do {
            ret = SQLGetDiagRec(
                    type,
                    handle,
                    ++i,
                    cast(char*) state,
                    &native,
                    cast(char*)text,
                    text.length,
                    &len);

            if (SQL_SUCCEEDED(ret)) {
                auto s = text[0..len];
                info("error: ", s);
                error ~= s;
                //writefln("%s:%ld:%ld:%s\n", state, i, native, text);
            }
        } while (ret == SQL_SUCCESS);
        throw new DatabaseException(error);
    }

}
