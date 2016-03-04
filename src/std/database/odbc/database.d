module std.database.odbc.database;
pragma(lib, "odbc");

public import std.database.exception;
public import std.database.resolver;
public import std.database.pool;
import std.database.odbc.sql;
import std.database.odbc.sqltypes;
import std.database.odbc.sqlext;
import std.experimental.allocator.mallocator;

import std.string;
import core.stdc.stdlib;
import std.conv;
import std.typecons;
import std.container.array;
import std.experimental.logger;
public import std.database.allocator;

//alias long SQLLEN;
//alias ubyte SQLULEN;

alias SQLINTEGER SQLLEN;
alias SQLUINTEGER SQLULEN;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}


struct Database(T) {
    alias Allocator = T.Allocator;
    //alias ConnectionPool = Pool!(Connection!T);

    // temporary

    // special treatment for connections
    auto connection(string uri="") {
        /*
           if (!cachedConnection.data_.refCountedStore.isInitialized) {
           cachedConnection = Connection!T(this, uri);
           }
         */
        return Connection!T(this, uri);
    }

    //ConnectionPool pool;

    void execute(string sql) {connection().execute(sql);}

    bool bindable() {return false;}

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
        info("DRIVERS:");
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
            info(driver.ptr[0..strlen(driver.ptr)], ": ", attr.ptr[0..strlen(attr.ptr)]);
            //if (ret == SQL_SUCCESS_WITH_INFO) printf("\tdata truncation\n");
        }
    }

    private:

    struct Payload {
        string defaultURI;
        Allocator allocator;
        SQLHENV env;

        //Connection!T cachedConnection;  // no size error

        this(string defaultURI_) {
            defaultURI = defaultURI_;
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
            info("odbc: closing database");
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

struct Connection(T) {
    //alias Database = .Database;
    //alias Statement = .Statement;

    // temporary helper functions
    auto statement(string sql) {return Statement!T(this,sql);}
    auto statement(X...) (string sql, X args) {return Statement!T(this,sql,args);}
    auto execute(string sql) {return statement(sql).execute();}
    auto execute(string sql, T...) (T args) {return statement(sql).execute(args);}

    package this(Database!T db, string source="") {
        data_ = Data(db,source);
    }

    private:

    struct Payload {
        Database!T db;
        string source;
        SQLHDBC con;
        bool connected;

        this(Database!T db_, string source_ = "") {
            db = db_;
            source = source_.length == 0 ? db.data_.defaultURI : source_;

            info("ODBC opening connection: ", source);

            char[1024] outstr;
            SQLSMALLINT outstrlen;
            //string DSN = "DSN=testdb";

            Source src = resolve(source);

            SQLRETURN ret = SQLAllocHandle(SQL_HANDLE_DBC,db.data_.env,&con);
            if ((ret != SQL_SUCCESS) && (ret != SQL_SUCCESS_WITH_INFO)) {
                throw new DatabaseException("SQLAllocHandle error: " ~ to!string(ret));
            }

            check("SQLConnect", SQL_HANDLE_DBC, con, SQLConnect(
                        con,
                        cast(SQLCHAR*) toStringz(src.server),
                        SQL_NTS,
                        cast(SQLCHAR*) toStringz(src.username),
                        SQL_NTS,
                        cast(SQLCHAR*) toStringz(src.password),
                        SQL_NTS));
            connected = true;
        }

        ~this() {
            info("ODBC closing connection: ", source);
            if (connected) check("SQLDisconnect", SQLDisconnect(con));
            check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_DBC, con));
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

}

struct Statement(T) {
    alias Allocator = T.Allocator;
    alias Bind = .Bind!T;
    //alias Result = .Result;
    //alias Range = Result.Range; // error Result.Payload no size yet for forward reference

    // temporary
    auto result() {return Result!T(this);}
    auto opSlice() {return result();} // no size error

    this(Connection!T con, string sql) {
        data_ = Data(con,sql);
        prepare();
        // must be able to detect binds in all DBs
        //if (!data_.binds) execute();
    }

    this(X...) (Connection!T con, string sql, X args) {
        data_ = Data(con,sql);
        prepare();
        bindAll(args);
    }

    string sql() {return data_.sql;}
    int binds() {return data_.binds;}

    void bind(int n, int value) {
        info("input bind: n: ", n, ", value: ", value);

        Bind b;
        b.type = SQL_C_LONG;
        b.dbtype = SQL_INTEGER;
        b.size = SQLINTEGER.sizeof;
        b.allocSize = b.size;
        b.data = cast(void*)(data_.allocator.allocate(b.allocSize));
        inputBind(n, b);

        *(cast(SQLINTEGER*) data_.inputBind[n-1].data) = value;
    }

    void bind(int n, const char[] value){
        import core.stdc.string: strncpy;
        info("input bind: n: ", n, ", value: ", value);
        // no null termination needed

        Bind b;
        b.type = SQL_C_CHAR;
        b.dbtype = SQL_CHAR;
        b.size = cast(SQLSMALLINT) value.length;
        b.allocSize = b.size;
        b.data = cast(void*)(data_.allocator.allocate(b.allocSize));
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
        Connection!T con;
        string sql;
        Allocator *allocator;
        SQLHSTMT stmt;
        bool hasRows;
        int binds;
        Array!Bind inputBind;

        this(Connection!T con_, string sql_) {
            con = con_;
            sql = sql_;
            allocator = &con.data_.db.data_.allocator;
            check("SQLAllocHandle", SQLAllocHandle(SQL_HANDLE_STMT, con.data_.con, &stmt));
        }

        ~this() {
            for(int i = 0; i < inputBind.length; ++i) {
                allocator.deallocate(inputBind[i].data[0..inputBind[i].allocSize]);
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
        info("binds: ", data_.binds);
    }

    public:

    void execute() {
        if (!data_.binds) {
            info("sql execute direct: ", data_.sql);
            check("SQLExecDirect", SQLExecDirect(
                        data_.stmt,
                        cast(SQLCHAR*) toStringz(data_.sql),
                        SQL_NTS));
        } else {
            info("sql execute prepared: ", data_.sql);
            SQLRETURN ret = SQLExecute(data_.stmt);
            check("SQLExecute()", SQL_HANDLE_STMT, data_.stmt, ret);
        }
    }

    void execute(X...) (X args) {
        int col;
        foreach (arg; args) {
            bind(++col, arg);
        }
        execute();
    }

    private:

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


struct Describe(T) {
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

struct Bind(T) {
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

struct Result(T) {
    alias Allocator = T.Allocator;
    alias Describe = .Describe!T;
    alias Bind = .Bind!T;
    alias Range = .ResultRange!T;
    alias Row = .Row!T;

    int columns() {return data_.columns;}

    this(Statement!T stmt) {
        data_ = Data(stmt);
    }

    auto opSlice() {return ResultRange!T(this);}

    bool start() {return data_.status == SQL_SUCCESS;}
    bool next() {return data_.next();}

    private:

    static const maxData = 256;

    struct Payload {
        Statement!T stmt;
        Allocator *allocator;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        SQLRETURN status;

        this(Statement!T stmt_) {
            stmt = stmt_;
            allocator = stmt.data_.allocator;
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

            SQLSMALLINT v;
            check("SQLNumResultCols", SQLNumResultCols (stmt.data_.stmt, &v));
            columns = v;
            info("columns: ", columns);

            describe.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                describe ~= Describe();
                auto d = &describe.back();

                check("SQLDescribeCol", SQLDescribeCol(
                            stmt.data_.stmt,
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
                        b.type = SQL_C_CHAR;
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

                info(
                        "output bind: index: ", i,
                        ", type: ", b.type,
                        ", size: ", b.size,
                        ", allocSize: ", b.allocSize);
            }
        }

        bool next() {
            //info("SQLFetch");
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
        void opAssign(Statement!T.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

}

struct Value(T) {
    alias Bind = .Bind!T;
    package Bind* bind_;

    this(Bind* bind) {
        bind_ = bind;
    }

    auto as(T:int)() {
        if (bind_.type == SQL_C_CHAR) return to!int(as!string()); // tmp hack
        check(bind_.type, SQL_C_LONG);
        return *(cast(int*) bind_.data);
    }

    auto as(T:string)() {
        check(bind_.type, SQL_C_CHAR);
        auto ptr = cast(immutable char*) bind_.data;
        return cast(string) ptr[0..bind_.len];
    }

    //inout(char)[]
    auto chars() {
        check(bind_.type, SQL_C_CHAR);
        auto data = cast(char*) bind_.data;
        return data ? data[0..bind_.len] : data[0..0];
    }

    private:

    void check(SQLSMALLINT a, SQLSMALLINT b) {
        if (a != b) throw new DatabaseException("type mismatch");
    }

}

struct Row(T) {
    alias Result = .Result!T;
    alias Value = .Value!T;

    this(Result* result) {
        result_ = result;
    }

    int columns() {return result_.columns();}

    Value opIndex(size_t idx) {
        return Value(&result_.data_.bind[idx]);
    }

    private Result* result_;
}

struct ResultRange(T) {
    // implements a One Pass Range
    alias Result = .Result!T;
    alias Row = .Row!T;

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

void check()(string msg, SQLRETURN ret) {
    info(msg, ":", ret);
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) return;
    throw new DatabaseException("odbc error: " ~ msg);
}

void check()(string msg, SQLSMALLINT handle_type, SQLHANDLE handle, SQLRETURN ret) {
    info(msg, ":", ret);
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) return;
    throw_detail(handle, handle_type, msg);
}

void throw_detail()(SQLHANDLE handle, SQLSMALLINT type, string msg) {
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
            //error =~ s;
            //writefln("%s:%ld:%ld:%s\n", state, i, native, text);
        }
    } while (ret == SQL_SUCCESS);
    throw new DatabaseException(error);
}


