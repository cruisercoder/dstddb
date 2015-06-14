module std.database.odbc.database;
pragma(lib, "odbc");

public import std.database.exception;
import std.database.odbc.sql;
import std.database.odbc.sqltypes;
import std.database.odbc.sqlext;

import std.string;
import std.c.stdlib;
import std.conv;
import std.typecons;
import std.container.array;
import std.experimental.logger;

//alias long SQLLEN;
//alias ubyte SQLULEN;

alias SQLINTEGER SQLLEN;
alias SQLUINTEGER SQLULEN;

struct Database {
    static Database create(string defaultURI) {
        return Database(defaultURI);
    }

    this(string defaultURI) {
        data_ = Data(defaultURI);
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
        log("DRIVERS:");
        while(SQL_SUCCEEDED(ret = SQLDrivers(
                        data_.env, 
                        direction,
                        driver.ptr, 
                        driver.sizeof, 
                        &driver_ret,
                        attr.ptr, 
                        attr.sizeof, 
                        &attr_ret))) {
            direction = SQL_FETCH_NEXT;
            log(driver.ptr[0..strlen(driver.ptr)], ": ", attr.ptr[0..strlen(attr.ptr)]);
            //if (ret == SQL_SUCCESS_WITH_INFO) printf("\tdata truncation\n");
        }
    }

    private:

    struct Payload {
        string defaultURI;
        SQLHENV env;

        this(string defaultURI_) {
            defaultURI = defaultURI_;
            check(
                    "SQLAllocHandle", 
                    SQLAllocHandle(
                        SQL_HANDLE_ENV, 
                        SQL_NULL_HANDLE,
                        &env));
            SQLSetEnvAttr(env, SQL_ATTR_ODBC_VERSION, cast(void *) SQL_OV_ODBC3, 0);
        }

        ~this() {
            log("odbc: closing database");
            if (!env) return;
            check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_ENV, env));
            env = null;
        }

        this(this) { assert(false); }
        void opAssign(Database.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

}

struct Connection {
    alias Database = .Database;
    alias Statement = .Statement;

    package this(Database db, string source) {
        data_ = Data(db,source);
    }

    private:

    struct Payload {
        Database db;
        string source;
        SQLHDBC con;
        bool connected;

        this(Database db_, string source_) {
            db = db_;
            source = source_;

            char[1024] outstr;
            SQLSMALLINT outstrlen;
            string DSN = "DSN=testdb";

            log("ODBC opening: ", source);

            SQLRETURN ret = SQLAllocHandle(SQL_HANDLE_DBC,db.data_.env,&con);
            if ((ret != SQL_SUCCESS) && (ret != SQL_SUCCESS_WITH_INFO)) {
                throw new DatabaseException("SQLAllocHandle error: " ~ to!string(ret));
            }

            string server = source;
            string un = "";
            string pw = "";

            check("SQLConnect", SQL_HANDLE_DBC, con, SQLConnect(
                        con,
                        cast(SQLCHAR*) toStringz(server),
                        SQL_NTS,
                        cast(SQLCHAR*) toStringz(un),
                        SQL_NTS,
                        cast(SQLCHAR*) toStringz(pw),
                        SQL_NTS));
            connected = true;
        }

        ~this() {
            log("ODBC closing ", source);
            if (connected) check("SQLDisconnect", SQLDisconnect(con));
            check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_DBC, con));
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

}

struct Statement {
    alias Result = .Result;
    //alias Range = Result.Range; // error Result.Payload no size yet for forward reference

    this(Connection con, string sql) {
        data_ = Data(con,sql);
        prepare();
        // must be able to detect binds in all DBs
        if (!data_.binds) execute();
    }

    this(T...) (Connection con, string sql, T args) {
        data_ = Data(con,sql);
        prepare();
        bindAll(args);
        execute();
    }

    string sql() {return data_.sql;}
    int columns() {return data_.columns;}
    int binds() {return data_.binds;}

    void bind(int n, int value) {
        log("input bind: n: ", n, ", value: ", value);

        Bind b;
        b.type = SQL_C_LONG;
        b.dbtype = SQL_INTEGER;
        b.size = SQLINTEGER.sizeof;
        b.allocSize = b.size;
        b.data = malloc(b.allocSize);
        inputBind(n, b);

        *(cast(SQLINTEGER*) data_.inputBind[n-1].data) = value;
    }

    void bind(int n, const char[] value){
        import core.stdc.string: strncpy;
        log("input bind: n: ", n, ", value: ", value);
        // no null termination needed

        Bind b;
        b.type = SQL_C_CHAR;
        b.dbtype = SQL_CHAR;
        b.size = cast(SQLSMALLINT) value.length;
        b.allocSize = b.size;
        b.data = malloc(b.allocSize);
        inputBind(n, b);

        strncpy(cast(char*) b.data, value.ptr, b.size);
    }

    private:

    void inputBind(int n, ref Bind bind) {
        data_.inputBind ~= bind;
        auto b = &data_.inputBind.back();

        check("SQLBindParameter", SQLBindParameter(
                    data_.stmt,
                    cast(SQLSMALLINT) n,
                    SQL_PARAM_INPUT,
                    b.type,
                    b.dbtype,
                    0,
                    0,
                    b.data,
                    b.allocSize,
                    null));
    }

    struct Payload {
        Connection con;
        string sql;
        SQLHSTMT stmt;
        bool hasRows;
        int columns;
        int binds;
        Array!Bind inputBind;

        this(Connection con_, string sql_) {
            con = con_;
            sql = sql_;
            check("SQLAllocHandle", SQLAllocHandle(SQL_HANDLE_STMT, con.data_.con, &stmt));
        }

        ~this() {
            for(int i = 0; i < inputBind.length; ++i) {
                free(inputBind[i].data);
            }
            if (stmt) check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_STMT, stmt));
            // stmt = null? needed
        }

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

    void exec() {
        check("SQLExecDirect", SQLExecDirect(data_.stmt,cast(SQLCHAR*) toStringz(data_.sql), SQL_NTS));
    }

    void prepare() {
        //if (!data_.st)
        check("SQLPrepare", SQLPrepare(
                    data_.stmt,
                    cast(SQLCHAR*) toStringz(data_.sql),
                    SQL_NTS));

        SQLSMALLINT v;
        check("SQLNumParams", SQLNumParams(data_.stmt, &v));
        data_.binds = v;
        check("SQLNumResultCols", SQLNumResultCols (data_.stmt, &v));
        data_.columns = v;
        log("prepare info: binds: ", data_.binds, ", columns: ", data_.columns);
    }

    void execute() {
        SQLRETURN ret = SQLExecute(data_.stmt);
        check("SQLExecute()", SQL_HANDLE_STMT, data_.stmt, ret);
    }

    void bindAll(T...) (T args) {
        int col;
        foreach (arg; args) {
            bind(++col, arg);
        }
    }

    void reset() {
        //SQLCloseCursor
    }

}

static const nameSize = 256;

struct Describe {
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
    SQLSMALLINT type;
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
    alias Range = .ResultRange;
    alias Row = .Row;

    int columns() {return data_.stmt.columns();}

    this(Statement stmt) {
        data_ = Data(stmt);
    }

    ResultRange range() {return ResultRange(this);}

    bool start() {return data_.status == SQL_SUCCESS;}
    bool next() {return data_.next();}

    private:

    static const maxData = 256;

    struct Payload {
        Statement stmt;
        Array!Describe describe;
        Array!Bind bind;
        SQLRETURN status;

        this(Statement stmt_) {
            stmt = stmt_;
            build_describe();
            build_bind();
            next();
        }

        ~this() {
            for(int i = 0; i < bind.length; ++i) {
                free(bind[i].data);
            }
        }

        void build_describe() {
            describe.reserve(stmt.data_.columns);

            for(int i = 0; i < stmt.data_.columns; ++i) {
                describe ~= Describe();
                auto d = &describe.back();

                check("SQLDescribeCol", SQLDescribeCol(
                            stmt.data_.stmt,
                            cast(SQLUSMALLINT) (i+1),
                            cast(SQLCHAR *) d.name,
                            cast(SQLSMALLINT) nameSize,
                            &d.nameLen,
                            &d.type,
                            &d.size,
                            &d.digits,
                            &d.nullable));

                //log("NAME: ", d.name, ", type: ", d.type);
            }
        }

        void build_bind() {
            import core.memory : GC;

            bind.reserve(stmt.data_.columns);

            for(int i = 0; i < stmt.data_.columns; ++i) {
                bind ~= Bind();
                auto b = &bind.back();
                auto d = &describe[i];

                b.size = d.size;
                b.allocSize = cast(SQLULEN) (b.size + 1);
                b.data = malloc(b.allocSize);
                GC.addRange(b.data, b.allocSize);

                // just INT and VARCHAR for now
                switch (d.type) {
                    case SQL_INTEGER:
                        b.type = SQL_C_LONG;
                        break;
                    case SQL_VARCHAR:
                        b.type = SQL_C_CHAR;
                        break;
                    default: 
                        throw new DatabaseException("bind error: type: " ~ to!string(d.type));
                }

                check("SQLBINDCol", SQLBindCol (
                            stmt.data_.stmt,
                            cast(SQLUSMALLINT) (i+1),
                            b.type,
                            b.data,
                            b.size,
                            &b.len));

                log(
                        "output bind: index: ", i,
                        ", type: ", b.type,
                        ", size: ", b.size,
                        ", allocSize: ", b.allocSize);
            }
        }

        bool next() {
            //log("SQLFetch");
            status = SQLFetch(stmt.data_.stmt);
            if (status == SQL_SUCCESS) {
                return true; 
            } else if (status == SQL_NO_DATA) {
                stmt.reset();
                return false;
            }
            check("SQLFetch", SQL_HANDLE_STMT, stmt.data_.stmt, status);
            return false;
        }

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

}

struct Value {
    package Bind* bind_;

    this(Bind* bind) {
        bind_ = bind;
    }

    int get(T) () {
        return toInt();
    }

    // bounds check or covered?
    int toInt() {
        check(bind_.type, SQL_C_LONG);
        return *(cast(int*) bind_.data);
    }

    //inout(char)[]
    auto chars() {
        check(bind_.type, SQL_C_CHAR);
        import core.stdc.string: strlen;
        auto data = cast(char*) bind_.data;
        return data ? data[0 .. strlen(data)] : data[0..0];
    }

    private:

    void check(SQLSMALLINT a, SQLSMALLINT b) {
        if (a != b) throw new DatabaseException("type mismatch");
    }

}

struct Row {
    alias Result = .Result;
    alias Value = .Value;

    this(Result* result) {
        result_ = result;
    }

    int columns() {return result_.columns();}

    Value opIndex(size_t idx) {
        return Value(&result_.data_.bind[idx]);
    }

    private Result* result_;
}

struct ResultRange {
    // implements a One Pass Range
    alias Result = .Result;
    alias Row = .Row;

    private Result result_;
    private bool ok_;

    this(Result result) {
        result_ = result;
        ok_ = result_.start();
    }

    bool empty() {
        return !ok_;
    }

    Row front() {
        return Row(&result_);
    }

    void popFront() {
        ok_ = result_.next();
    }
}

void check(string msg, SQLRETURN ret) {
    log(msg, ":", ret);
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) return;
    throw new DatabaseException("odbc error: " ~ msg);
}

void check(string msg, SQLSMALLINT handle_type, SQLHANDLE handle, SQLRETURN ret) {
    log(msg, ":", ret);
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) return;
    throw_detail(handle, handle_type, msg);
}

void throw_detail(SQLHANDLE handle, SQLSMALLINT type, string msg) {
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
            log("error: ", s);
            //error =~ s;
            //writefln("%s:%ld:%ld:%s\n", state, i, native, text);
        }
    } while (ret == SQL_SUCCESS);
    throw new DatabaseException(error);
}


