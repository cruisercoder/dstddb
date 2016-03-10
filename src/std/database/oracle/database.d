module std.database.oracle.database;
pragma(lib, "occi");
pragma(lib, "clintsh");

import std.string;
import core.stdc.stdlib;
import std.conv;
import std.experimental.allocator.mallocator;

import std.database.oracle.bindings;
import std.database.common;
import std.database.exception;
import std.database.resolver;
import std.database.allocator;
import std.container.array;
import std.experimental.logger;

import std.stdio;
import std.typecons;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

auto createDatabase(T)(string defaultURI="") {
    return Database!T(defaultURI);  
}

/*
   auto connection(T)(Database!T db, string source = "") {
   return Connection!T(db,source);
   }

   auto result(T)(Statement!T stmt) {
   return Result!T(stmt);  
   }
 */


void check()(string msg, sword status) {
    info(msg, ":", status);
    if (status == OCI_SUCCESS) return;
    throw new DatabaseException("OCI error: " ~ msg);
}

//struct Database() {
    //static auto create()(string uri="") {return Database!DefaultPolicy();}
//}

struct Database(T=DefaultPolicy) {
    alias Allocator = T.Allocator;
    //alias Connection = .Connection!T;

    static const auto queryVariableType = QueryVariableType.QuestionMark;

    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

    // temporary
    auto connection() {return Connection!T(this);}
    auto connection(string uri) {return Connection!T(this, uri);}
    void query(string sql) {connection().query(sql);}

    bool bindable() {return false;}

    private struct Payload {
        Allocator allocator;
        string defaultURI;
        OCIEnv* env;
        OCIError *error;

        this(string defaultURI_) {
            allocator = Allocator();
            defaultURI = defaultURI_;
            info("oracle: opening database");
            ub4 mode = OCI_THREADED | OCI_OBJECT;

            check("OCIEnvCreate", OCIEnvCreate(
                        &env,
                        mode,
                        null,
                        null,
                        null,
                        null,
                        0,
                        null));

            check("OCIHandleAlloc", OCIHandleAlloc(
                        env, 
                        cast(void**) &error,
                        OCI_HTYPE_ERROR,
                        0,
                        null));
        }

        ~this() {
            info("oracle: closing database");
            if (env) {
                sword status = OCIHandleFree(env, OCI_HTYPE_ENV);
                env = null;
            }
        }

        this(this) { assert(false); }
        void opAssign(Database.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

}

struct Connection(T) {
    //alias Database = .Database!T;
    //alias Statement = .Statement!T;

    // temporary
    auto statement (string sql) { return Statement!T(this, sql); }
    auto statement(X...) (string sql, X args) {return Statement!T(this, sql, args);}
    auto query(string sql) {return statement(sql).query();}
    auto query(T...) (string sql, T args) {return statement(sql).query(args);}

    package this(Database!T db, string source="") {
        data_ = Data(db,source);
    }

    private:

    struct Payload {
        Database!T db;
        string source;
        OCIError *error;
        OCISvcCtx *svc_ctx;
        bool connected;

        this(Database!T db_, string source_) {
            db = db_;
            source = source_.length == 0 ? db.data_.defaultURI : source_;
            error = db.data_.error;

            Source src = resolve(source);
            string dbname = getDBName(src);

            check("OCILogon", OCILogon(
                        db_.data_.env,
                        error,
                        &svc_ctx,
                        cast(const OraText*) src.username.ptr,
                        cast(ub4) src.username.length,
                        cast(const OraText*) src.password.ptr,
                        cast(ub4) src.password.length,
                        cast(const OraText*) dbname.ptr, 
                        cast(ub4) dbname.length));

            connected = true;
        }

        ~this() {
            if (svc_ctx) check("OCILogoff", OCILogoff(svc_ctx, error));
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    static string getDBName(Source src) {
        string dbName = 
            "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)" ~
            "(HOST=" ~ src.server ~ ")" ~
            "(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=XE)))"; // need service name
        return dbName;
    }

}

static const nameSize = 256;

struct Describe(T) {
    //char[nameSize] name;

    OraText* ora_name;
    string name;
    int index;
    ub4 name_len;
    //string name;
    ub2 type;
    ub2 size;
    //const nd_oracle_type_info *type_info;
    //oracle_bind_type bind_type;
    OCIParam *param;
    OCIDefine *define;
}

struct Bind(T) {
    void* data;
    sb4 allocSize;
    ub2 type;
    void* ind;
    ub2 length;
}

// non memeber needed to avoid forward error
//auto range(T)(Statement!T stmt) {return Result!T(stmt).range();}

struct Statement(T) {
    alias Allocator = T.Allocator;
    alias Bind = .Bind!T;
    //alias Connection = .Connection!T;
    //alias Result = .Result;
    //alias Range = Result.Range;

    //ResultRange!T range() {return Result!T(this).range();} // no size error

    // temporary
    auto result() {return Result!T(this);}
    auto opSlice() {return Result!T(this);} // no size error

    this(Connection!T con, string sql) {
        data_ = Data(con,sql);
        prepare();
        // must be able to detect binds in all DBs
        //if (!data_.binds) query();
    }

    this(X...) (Connection!T con, string sql, X args) {
        data_ = Data(con,sql);
        prepare();
        bindAll(args);
        //query();
    }

    string sql() {return data_.sql;}
    int binds() {return data_.binds;}

    void bind(int n, int value) {
        /*
           info("input bind: n: ", n, ", value: ", value);

           Bind b;
           b.type = SQL_C_LONG;
           b.dbtype = SQL_INTEGER;
           b.size = SQLINTEGER.sizeof;
           b.allocSize = b.size;
           b.data = malloc(b.allocSize);
           inputBind(n, b);

         *(cast(SQLINTEGER*) data_.inputBind[n-1].data) = value;
         */
    }

    void bind(int n, const char[] value){
        /*
           import core.stdc.string: strncpy;
           info("input bind: n: ", n, ", value: ", value);
        // no null termination needed

        Bind b;
        b.type = SQL_C_CHAR;
        b.dbtype = SQL_CHAR;
        b.size = cast(SQLSMALLINT) value.length;
        b.allocSize = b.size;
        b.data = malloc(b.allocSize);
        inputBind(n, b);

        strncpy(cast(char*) b.data, value.ptr, b.size);
         */
    }

    private:

    void inputBind(int n, ref Bind bind) {
        /*
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
         */
    }

    struct Payload {
        Connection!T con;
        string sql;
        Allocator *allocator;
        OCIError *error;
        OCIStmt *stmt;
        ub2 stmt_type;
        bool hasRows;
        int binds;
        Array!Bind inputBind;

        this(Connection!T con_, string sql_) {
            con = con_;
            sql = sql_;
            allocator = &con.data_.db.data_.allocator;
            error = con.data_.error;

            check("OCIHandleAlloc", OCIHandleAlloc(
                        con.data_.db.data_.env,
                        cast(void**) &stmt,
                        OCI_HTYPE_STMT,
                        0,
                        null));
        }

        ~this() {
            for(int i = 0; i < inputBind.length; ++i) {
                allocator.deallocate(inputBind[i].data[0..inputBind[i].allocSize]);
            }
            if (stmt) check("OCIHandleFree", OCIHandleFree(stmt,OCI_HTYPE_STMT));
            // stmt = null? needed
        }

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

    void exec() {
        //check("SQLExecDirect", SQLExecDirect(data_.stmt,cast(SQLCHAR*) toStringz(data_.sql), SQL_NTS));
    }

    void prepare() {

        check("OCIStmtPrepare", OCIStmtPrepare(
                    data_.stmt,
                    data_.error,
                    cast(OraText*) data_.sql.ptr,
                    cast(ub4) data_.sql.length,
                    OCI_NTV_SYNTAX,
                    OCI_DEFAULT));


        // get the type of statement
        check("OCIAttrGet", OCIAttrGet(
                    data_.stmt,
                    OCI_HTYPE_STMT,
                    &data_.stmt_type,
                    null,
                    OCI_ATTR_STMT_TYPE,
                    data_.error));

        check("OCIAttrGet", OCIAttrGet(
                    data_.stmt,
                    OCI_HTYPE_STMT,
                    &data_.binds,
                    null,
                    OCI_ATTR_BIND_COUNT,
                    data_.error));

        info("binds: ", data_.binds);
    }

    public:

    auto query() {
        ub4 iters = data_.stmt_type == OCI_STMT_SELECT ? 0:1;
        info("iters: ", iters);
        info("execute sql: ", data_.sql);

        check("OCIStmtExecute", OCIStmtExecute(
                    data_.con.data_.svc_ctx,
                    data_.stmt,
                    data_.error,
                    iters,
                    0,
                    null,
                    null,
                    OCI_COMMIT_ON_SUCCESS));
        return result();
    }

    auto query(X...) (X args) {
        int col;
        foreach (arg; args) {
            bind(++col, arg);
        }
        return query();
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

struct Result(T) {
    alias Allocator = T.Allocator;
    alias Describe = .Describe!T;
    alias Bind = .Bind!T;
    //alias Statement = .Statement!T;
    //alias ResultRange = .ResultRange!T;
    alias Range = ResultRange;
    alias Row = .Row;

    int columns() {return data_.columns;}

    this(Statement!T stmt) {
        data_ = Data(stmt);
    }

    auto opSlice() {return ResultRange!T(this);}

    bool start() {return data_.status == OCI_SUCCESS;}
    bool next() {return data_.next();}

    private:

    static const maxData = 256;

    struct Payload {
        Statement!T stmt;
        Allocator *allocator;
        OCIError *error;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        ub4 row_array_size = 1;
        sword status;

        this(Statement!T stmt_) {
            stmt = stmt_;
            allocator = &stmt.data_.con.data_.db.data_.allocator;
            error = stmt.data_.error;
            build_describe();
            build_bind();
            next();
        }

        ~this() {
            for(int i = 0; i < bind.length; ++i) {
                allocator.deallocate(bind[i].data[0..bind[i].allocSize]);
            }
        }

        void build_describe() {
            sword numcols;
            check("OCIAttrGet", OCIAttrGet(
                        stmt.data_.stmt,
                        OCI_HTYPE_STMT,
                        &numcols,
                        null,
                        OCI_ATTR_PARAM_COUNT,
                        error));
            columns = numcols;
            info("columns: ", columns);

            describe.reserve(columns);
            for(int i = 0; i < columns; ++i) {
                describe ~= Describe();
                auto d = &describe.back();

                OCIParam *col;
                check("OCIParamGet",OCIParamGet(
                            stmt.data_.stmt,
                            OCI_HTYPE_STMT,
                            error,
                            cast(void**) &col,
                            i+1));

                check("OCIAttrGet", OCIAttrGet(
                            col,
                            OCI_DTYPE_PARAM,
                            &d.ora_name,
                            &d.name_len,
                            OCI_ATTR_NAME,
                            error));

                check("OCIAttrGet", OCIAttrGet(
                            col,
                            OCI_DTYPE_PARAM,
                            &d.type,
                            null,
                            OCI_ATTR_DATA_TYPE,
                            error));

                check("OCIAttrGet", OCIAttrGet(
                            col,
                            OCI_DTYPE_PARAM,
                            &d.size,
                            null,
                            OCI_ATTR_DATA_SIZE,
                            error));

                d.name = to!string(cast(char*)(d.ora_name)[0..d.name_len]);
                info("describe: name: ", d.name, ", type: ", d.type, ", size: ", d.size);
            }

        }

        void build_bind() {
            import core.memory : GC; // needed?

            bind.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                bind ~= Bind();
                auto b = &bind.back();
                auto d = &describe[i];

                b.allocSize = cast(sb4) (d.size + 1);
                b.data = cast(void*)(allocator.allocate(b.allocSize));
                GC.addRange(b.data, b.allocSize);

                // just str for now
                b.type = SQLT_STR;

                check("OCIDefineByPos", OCIDefineByPos(
                            stmt.data_.stmt,
                            &d.define,
                            error,
                            cast(ub4) i+1,
                            b.data,
                            b.allocSize,
                            b.type,
                            &b.ind,
                            &b.length,
                            null,
                            OCI_DEFAULT));
            }
        }

        bool next() {

            //info("OCIStmtFetch2");
            status = OCIStmtFetch2(
                    stmt.data_.stmt,
                    error,
                    row_array_size,
                    OCI_FETCH_NEXT,
                    0,
                    OCI_DEFAULT);

            if (status == OCI_SUCCESS) {
                return true; 
            } else if (status == OCI_NO_DATA) {
                stmt.reset();
                return false;
            }

            //check("SQLFetch", SQL_HANDLE_STMT, stmt.data_.stmt, status);
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

    auto as(X:int)() {
        if (bind_.type == SQLT_STR) return to!int(as!string()); // tmp hack
        check(bind_.type, SQLT_INT);
        return *(cast(int*) bind_.data);
    }

    auto as(X:string)() {
        import core.stdc.string: strlen;
        check(bind_.type, SQLT_STR);
        auto ptr = cast(immutable char*) bind_.data;
        return cast(string) ptr[0..strlen(ptr)]; // fix with length
    }

    //inout(char)[]
    auto chars() {
        check(bind_.type, SQLT_STR);
        import core.stdc.string: strlen;
        auto data = cast(char*) bind_.data;
        return data ? data[0 .. strlen(data)] : data[0..0];
    }

    private:

    void check(ub2 a, ub2 b) {
        if (a != b) throw new DatabaseException("type mismatch");
    }
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


struct Row(T) {
    alias Result = .Result!T;
    alias Value = .Value;

    this(Result* result) {
        result_ = result;
    }

    int columns() {return result_.columns();}

    auto opIndex(size_t idx) {
        return Value!T(&result_.data_.bind[idx]);
    }

    private Result* result_;
}

