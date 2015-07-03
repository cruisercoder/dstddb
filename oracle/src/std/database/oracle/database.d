module std.database.oracle.database;
pragma(lib, "occi");
pragma(lib, "clintsh");

import std.string;
import std.c.stdlib;
import std.conv;

public import std.database.oracle.bindings;
public import std.database.exception;
public import std.database.resolver;
import std.container.array;
import std.experimental.logger;

import std.stdio;
import std.typecons;

void check(string msg, sword status) {
    log(msg, ":", status);
    if (status == OCI_SUCCESS) return;
    throw new DatabaseException("OCI error: " ~ msg);
}

struct Database {

    static Database create(string defaultURI) {
        return Database(defaultURI);
    }

    private struct Payload {
        string defaultURI;
        OCIEnv* env;
        OCIError *error;

        this(string defaultURI_) {
            defaultURI = defaultURI_;
            writeln("oracle: opening database");
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
            writeln("oracle: closing database");
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

    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

}

struct Connection {
    alias Database = .Database;
    //alias Statement = .Statement;

    package this(Database db, string source) {
        data_ = Data(db,source);
    }

    private:

    struct Payload {
        Database db;
        string source;
        OCISvcCtx *svc_ctx;
        bool connected;

        this(Database db_, string source_) {
            db = db_;
            source = source_;

            Source src = resolve(source);
            string dbname = getDBName(src);

            check("OCILogon", OCILogon(
                        db_.data_.env,
                        db_.data_.error,
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
            if (svc_ctx) check("OCILogoff", OCILogoff(svc_ctx, db.data_.error));
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
            "(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=cdb1)))";
        return dbName;
    }

}

static const nameSize = 256;

struct Describe {
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

struct Bind {
    void* data;
    sb4 allocSize;
    ub2 type;
    void* ind;
    ub2 length;
}

struct Statement {
    //alias Result = .Result;
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
    int binds() {return data_.binds;}

    void bind(int n, int value) {
        /*
           log("input bind: n: ", n, ", value: ", value);

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
        Connection con;
        string sql;
        OCIStmt *stmt;
        ub2 stmt_type;
        bool hasRows;
        int binds;
        Array!Bind inputBind;

        this(Connection con_, string sql_) {
            con = con_;
            sql = sql_;

            check("OCIHandleAlloc", OCIHandleAlloc(
                        con.data_.db.data_.env,
                        cast(void**) &stmt,
                        OCI_HTYPE_STMT,
                        0,
                        null));
        }

        ~this() {
            for(int i = 0; i < inputBind.length; ++i) {
                free(inputBind[i].data);
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
                    data_.con.data_.db.data_.error,
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
                    data_.con.data_.db.data_.error));

        check("OCIAttrGet", OCIAttrGet(
                    data_.stmt,
                    OCI_HTYPE_STMT,
                    &data_.binds,
                    null,
                    OCI_ATTR_BIND_COUNT,
                    data_.con.data_.db.data_.error));

        log("binds: ", data_.binds);
    }

    void execute() {

        ub4 iters = data_.stmt_type == OCI_STMT_SELECT ? 0:1;
        log("iters: ", iters);

        check("OCIStmtExecute", OCIStmtExecute(
                    data_.con.data_.svc_ctx,
                    data_.stmt,
                    data_.con.data_.db.data_.error,
                    iters,
                    0,
                    null,
                    null,
                    OCI_COMMIT_ON_SUCCESS));
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

struct Result {
    alias Range = .ResultRange;
    alias Row = .Row;

    int columns() {return data_.columns;}

    this(Statement stmt) {
        data_ = Data(stmt);
    }

    ResultRange range() {return ResultRange(this);}

    bool start() {return data_.status == OCI_SUCCESS;}
    bool next() {return data_.next();}

    private:

    static const maxData = 256;

    struct Payload {
        Statement stmt;
        OCIError *error;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        ub4 row_array_size = 1;
        sword status;

        this(Statement stmt_) {
            stmt = stmt_;
            error = stmt.data_.con.data_.db.data_.error;
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
            sword numcols;
            check("OCIAttrGet", OCIAttrGet(
                        stmt.data_.stmt,
                        OCI_HTYPE_STMT,
                        &numcols,
                        null,
                        OCI_ATTR_PARAM_COUNT,
                        stmt.data_.con.data_.db.data_.error));
            columns = numcols;
            log("columns: ", columns);

            describe.reserve(columns);
            for(int i = 0; i < columns; ++i) {
                describe ~= Describe();
                auto d = &describe.back();

                OCIParam *col;
                check("OCIParamGet",OCIParamGet(
                            stmt.data_.stmt,
                            OCI_HTYPE_STMT,
                            stmt.data_.con.data_.db.data_.error,
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
                log("describe: name: ", d.name, ", type: ", d.type, ", size: ", d.size);
            }

        }

        void build_bind() {
            import core.memory : GC;

            bind.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                bind ~= Bind();
                auto b = &bind.back();
                auto d = &describe[i];

                b.allocSize = cast(sb4) (d.size + 1);
                b.data = malloc(b.allocSize);
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

            //log("OCIStmtFetch2");
            status = OCIStmtFetch2(
                    stmt.data_.stmt,
                    stmt.data_.con.data_.db.data_.error,
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
        check(bind_.type, SQLT_INT);
        return *(cast(int*) bind_.data);
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

