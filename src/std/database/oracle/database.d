module std.database.oracle.database;
pragma(lib, "occi");
pragma(lib, "clntsh");

import std.string;
import core.stdc.stdlib;
import std.conv;

import std.database.oracle.bindings;
import std.database.common;
import std.database.exception;
import std.database.source;
import std.database.allocator;
import std.experimental.logger;
import std.container.array;

import std.datetime;

import std.database.front;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

alias Database(T) = BasicDatabase!(Driver!T,T);

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

auto createDatabase(T)(string defaultURI="") {
    return Database!T(defaultURI);  
}

void check()(string msg, sword status) {
    info(msg, ":", status);
    if (status == OCI_SUCCESS) return;
    throw new DatabaseException("OCI error: " ~ msg);
}

//struct Database() {
//static auto create()(string uri="") {return Database!DefaultPolicy();}
//}


T attrGet(T)(OCIStmt *stmt, OCIError *error, ub4 attribute) {
    T value;
    ub4 sz = T.sizeof;
    attrGet!T(stmt, error, attribute, value);
    return value;
}

void attrGet(T)(OCIStmt *stmt, OCIError *error, ub4 attribute, ref T value) {
    return attrGet(stmt, OCI_HTYPE_STMT, error, attribute, value);
}

void attrGet(T)(void* handle, ub4 handleType, OCIError* error, ub4 attribute, ref T value) {
    ub4 sz = T.sizeof;
    check("OCIAttrGet", OCIAttrGet(
                handle,
                OCI_HTYPE_STMT,
                &value,
                &sz,
                attribute,
                error));
}




struct Driver(Policy) {
    alias Allocator = Policy.Allocator;
    alias Cell = BasicCell!(Driver,Policy);



    static void attrSet(T)(OCIStmt *stmt, ub4 attribute, ref T value) {
        return attrSet(stmt, OCI_HTYPE_STMT, attribute, value);
    }

    static void attrSet(T)(void* handle, ub4 handleType, ub4 attribute, T value) {
        ub4 sz = T.sizeof;
        check("OCIAttrSet", OCIAttrSet(
                    stmt,
                    OCI_HTYPE_STMT,
                    &value,
                    sz,
                    attribute,
                    error));
    }

    struct BindContext {
        Describe* describe; // const?
        Bind* bind;
        Allocator* allocator;
        int rowArraySize;
    }

    static void basicCtor(T) (ref BindContext ctx) {
        emplace(cast(T*) ctx.bind.data);
    }

    static void charBinder(ref BindContext ctx) {
        auto d = ctx.describe, b = ctx.bind;
        b.type = ValueType.String;
        b.oType = SQLT_STR;
        //b.allocSize = cast(sb4) (ctx.describe.size + 1);
        b.allocSize = 1024; // fix this

        // include byte for null terminator
        //d.buf_size = d.size ? d.size+1 : 1024*10; // FIX
    }

    static void dateBinder(int type, T)(ref BindContext ctx) {
        auto d = ctx.describe, b = ctx.bind;
        b.type = ValueType.Date;
        b.oType = type;
        b.allocSize = T.sizeof;
        b.ctor = &basicCtor!T;
    }

    struct Conversion {
        int colType, bindType;

        private static const Conversion[4] info = [
        {SQLT_INT,SQLT_INT},
        {SQLT_NUM,SQLT_STR},
        {SQLT_CHR,SQLT_STR},
        {SQLT_DAT,SQLT_DAT}
        ];

        static int get(int colType) {
            // needs improvement
            foreach(ref i; info) {
                if (i.colType == colType) return i.bindType;
            }
            throw new DatabaseException(
                    "unknown conversion for column: " ~ to!string(colType));
        }
    }

    struct BindInfo {
        ub2 bindType;
        void function(ref BindContext ctx) binder;

        static const BindInfo[4] info = [
        {SQLT_INT,&charBinder},
        {SQLT_STR,&charBinder},
        {SQLT_STR,&charBinder},
        {SQLT_DAT,&dateBinder!(SQLT_ODT,OCIDate)}
        ];

        static void bind(ref BindContext ctx) {
            import core.memory : GC; // needed?
            auto d = ctx.describe, b = ctx.bind;
            auto colType = ctx.describe.oType;
            auto bindType = Conversion.get(colType);
            auto allocator = ctx.allocator;

            // needs improvement
            foreach(ref i; info) {
                if (i.bindType == bindType) {
                    i.binder(ctx);
                    b.data = allocator.allocate(b.allocSize * ctx.rowArraySize);
                    b.ind = allocator.allocate(sb2.sizeof * ctx.rowArraySize);
                    b.length = allocator.allocate(ub2.sizeof * ctx.rowArraySize);
                    if (b.ctor) b.ctor(ctx);
                    GC.addRange(b.data.ptr, b.data.length);
                    return;
                }
            }

            throw new DatabaseException(
                    "bind not supported: " ~ to!string(colType));
        }

    }


    struct Database {
        alias queryVariableType = QueryVariableType.Dollar;

        Allocator allocator;
        OCIEnv* env;
        OCIError *error;

        static const FeatureArray features = [
            //Feature.InputBinding,
            //Feature.DateBinding,
            //Feature.ConnectionPool,
            Feature.OutputArrayBinding,
            ];

        this(string defaultURI_) {
            allocator = Allocator();
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

    }

    struct Connection {
        Database* db;
        Source source;
        OCIError *error;
        OCISvcCtx *svc_ctx;
        bool connected;

        this(Database* db_, Source source_) {hhkk:
            db = db_;
            source = source_;
            error = db.error;

            string dbname = getDBName(source);

            check("OCILogon: ", OCILogon(
                        db_.env,
                        error,
                        &svc_ctx,
                        cast(const OraText*) source.username.ptr,
                        cast(ub4) source.username.length,
                        cast(const OraText*) source.password.ptr,
                        cast(ub4) source.password.length,
                        cast(const OraText*) dbname.ptr, 
                        cast(ub4) dbname.length));

            connected = true;
        }

        ~this() {
            if (svc_ctx) check("OCILogoff", OCILogoff(svc_ctx, error));
        }

        static string getDBName(Source src) {
            string dbName = 
                "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)" ~
                "(HOST=" ~ src.server ~ ")" ~
                "(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=XE)))"; // need service name
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
        ub2 oType;
        ub2 size;
        //const nd_oracle_type_info *type_info;
        //oracle_bind_type bind_type;
        OCIParam *param;
        OCIDefine *define;
    }

    struct Bind {
        ValueType type;
        void[] data;
        sb4 allocSize;
        ub2 oType;
        void[] ind;
        void[] length;
        void function(ref BindContext ctx) ctor;
        void function(void[] data) dtor;
    }

    // non memeber needed to avoid forward error
    //auto range(T)(Statement!T stmt) {return Result!T(stmt).range();}

    struct Statement {
        Connection *con;
        string sql;
        Allocator *allocator;
        OCIError *error;
        OCIStmt *stmt;
        ub2 stmt_type;
        int binds;
        Array!Bind inputBind;

        this(Connection* con_, string sql_) {
            con = con_;
            sql = sql_;
            allocator = &con.db.allocator;
            error = con.error;

            check("OCIHandleAlloc", OCIHandleAlloc(
                        con.db.env,
                        cast(void**) &stmt,
                        OCI_HTYPE_STMT,
                        0,
                        null));

            //attrSet!ub4(OCI_ATTR_PREFETCH_ROWS, 1000);
        }

        ~this() {
            for(int i = 0; i < inputBind.length; ++i) {
                allocator.deallocate(inputBind[i].data[0..inputBind[i].allocSize]);
            }
            if (stmt) check("OCIHandleFree", OCIHandleFree(stmt,OCI_HTYPE_STMT));
            // stmt = null? needed
        }

        void exec() {
            //check("SQLExecDirect", SQLExecDirect(data_.stmt,cast(SQLCHAR*) toStringz(data_.sql), SQL_NTS));
        }

        void prepare() {

            check("OCIStmtPrepare", OCIStmtPrepare(
                        stmt,
                        error,
                        cast(OraText*) sql.ptr,
                        cast(ub4) sql.length,
                        OCI_NTV_SYNTAX,
                        OCI_DEFAULT));


            // get the type of statement
            stmt_type = attrGet!ub2(OCI_ATTR_STMT_TYPE);
            binds = attrGet!ub4(OCI_ATTR_BIND_COUNT);
            info("binds: ", binds);
        }

        void query() {
            ub4 iters = stmt_type == OCI_STMT_SELECT ? 0:1;
            info("iters: ", iters);
            info("execute sql: ", sql);

            check("OCIStmtExecute", OCIStmtExecute(
                        con.svc_ctx,
                        stmt,
                        error,
                        iters,
                        0,
                        null,
                        null,
                        OCI_COMMIT_ON_SUCCESS));
        }

        void query(X...) (X args) {
            foreach (arg; args) {
                info("ARG: ", arg);
            }

            info("variadic query not implemented yet");
            //bindAll(args);
            //query();
        }

        bool hasRows() {
            // need a better way
            int columns = attrGet!ub4(OCI_ATTR_PARAM_COUNT);
            return columns != 0;
        }

        private void bindAll(T...) (T args) {
            int col;
            foreach (arg; args) bind(++col, arg);
        }

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

        void bind(int n, Date d) {
            throw new DatabaseException("Date input binding not yet implemented");
        }

        void reset() {}
        //: Error: template std.database.oracle.database.Driver!(DefaultPolicy).Driver.Statement.attrGet cannot deduce function from argument types !(ushort)(OCIStmt*, uint), candidates are:

        private T attrGet(T)(ub4 attribute) {return attrGet!T(stmt, error, attribute);}
        private void attrGet(T)(ub4 attribute, ref T value) { return attrGet(stmt, error, attribute, value);}
        private void attrSet(T)(ub4 attribute, T value) {return attrSet(stmt, error, attribute, value);}

        static T attrGet(T)(OCIStmt *stmt, OCIError *error, ub4 attribute) {
            T value;
            ub4 sz = T.sizeof;
            attrGet!T(stmt, error, attribute, value);
            return value;
        }

        static void attrGet(T)(OCIStmt *stmt, OCIError *error, ub4 attribute, ref T value) {
            return attrGet(stmt, OCI_HTYPE_STMT, error, attribute, value);
        }

        static void attrGet(T)(void* handle, ub4 handleType, OCIError* error, ub4 attribute, ref T value) {
            ub4 sz = T.sizeof;
            check("OCIAttrGet", OCIAttrGet(
                        handle,
                        OCI_HTYPE_STMT,
                        &value,
                        &sz,
                        attribute,
                        error));
        }

    }

    struct Result {
        Statement *stmt;
        Allocator *allocator;
        OCIError *error;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        ub4 rowArraySize;
        sword status;

        this(Statement* stmt_, int rowArraySize_) {
            stmt = stmt_;
            rowArraySize = rowArraySize_;
            allocator = &stmt.con.db.allocator;
            error = stmt.error;
            columns = stmt_.attrGet!ub4(OCI_ATTR_PARAM_COUNT);
            build_describe();
            build_bind();
    }

    ~this() {
        foreach(ref b; bind) {
            if (b.dtor)  b.dtor(b.data);
            allocator.deallocate(b.data);
            allocator.deallocate(b.ind);
            allocator.deallocate(b.length);
        }
    }

    void build_describe() {

        describe.reserve(columns);
        for(int i = 0; i < columns; ++i) {
            describe ~= Describe();
            auto d = &describe.back();

            OCIParam *col;
            check("OCIParamGet",OCIParamGet(
                        stmt.stmt,
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
                        &d.oType,
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
            info("describe: name: ", d.name, ", type: ", d.oType, ", size: ", d.size);
        }

    }

    void build_bind() {
        auto allocator = Allocator();

        import core.memory : GC; // needed?

        bind.reserve(columns);

        for(int i = 0; i < columns; ++i) {
            bind ~= Bind();
            auto d = &describe[i];
            auto b = &bind.back();

            BindContext ctx;
            ctx.describe = d;
            ctx.bind = b;
            ctx.allocator = &allocator;
            ctx.rowArraySize = rowArraySize;

            BindInfo.bind(ctx);

            info("bind: type: ", b.oType, ", allocSize:", b.allocSize);

            check("OCIDefineByPos", OCIDefineByPos(
                        stmt.stmt,
                        &d.define,
                        error,
                        cast(ub4) i+1,
                        b.data.ptr,
                        b.allocSize,
                        b.oType,
                        cast(dvoid *) b.ind.ptr, // check
                        cast(ub2*) b.length.ptr,
                        null,
                        OCI_DEFAULT));

            if (rowArraySize > 1) {
                check("OCIDefineArrayOfStruct", OCIDefineArrayOfStruct(
                            d.define,
                            error,
                            b.allocSize,        
                            sb2.sizeof,
                            ub2.sizeof,
                            0));
            }
        }
    }

    int fetch() {
        if (status == OCI_NO_DATA) return 0;

        int rowsFetched;

        //info("OCIStmtFetch2");

        status = OCIStmtFetch2(
                stmt.stmt,
                error,
                rowArraySize,
                OCI_FETCH_NEXT,
                0,
                OCI_DEFAULT);

        if (rowArraySize > 1) {
            // clean up
            ub4 value;
            check("OCIAttrGet",OCIAttrGet(
                        stmt.stmt,
                        OCI_HTYPE_STMT,
                        &value,
                        null,
                        OCI_ATTR_ROWS_FETCHED,
                        error));
            rowsFetched = value;
        } else {
            rowsFetched = (status == OCI_NO_DATA ? 0 : 1);
        }

        if (status == OCI_SUCCESS) {
            return rowsFetched; 
        } else if (status == OCI_NO_DATA) {
            //stmt.reset();
            return rowsFetched;
        }

        throw new DatabaseException("fetch error"); // fix
        //check("SQLFetch", SQL_HANDLE_STMT, stmt.data_.stmt, status);
        //return 0;
    }

    auto get(X:string)(Cell* cell) {
        import core.stdc.string: strlen;
        checkType(cell.bind.oType, SQLT_STR);
        auto ptr = cast(immutable char*) data(cell);
        return cast(string) ptr[0..strlen(ptr)]; // fix with length
    }

    auto name(size_t idx) {
        return describe[idx].name;
    }

    auto get(X:int)(Cell* cell) {
        checkType(cell.bind.oType, SQLT_INT);
        return *(cast(int*) data(cell));
    }

    auto get(X:Date)(Cell* cell) {
        //return Date(2016,1,1); // fix
        checkType(cell.bind.oType, SQLT_ODT);
        auto d = cast(OCIDate*) data(cell);
        return Date(d.OCIDateYYYY,d.OCIDateMM,d.OCIDateDD);
    }

    private void* data(Cell* cell) {
        return cell.bind.data.ptr + cell.bind.allocSize * cell.rowIdx;
    }

    private static void checkType(ub2 a, ub2 b) {
        if (a != b) throw new DatabaseException("type mismatch");
    }

}

}


