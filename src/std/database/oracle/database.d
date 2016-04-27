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
import std.container.array;
import std.experimental.logger;

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




struct Driver(Policy) {
    alias Allocator = Policy.Allocator;

    // experimental
    struct BindContext {
        this(Describe* d, Bind* b) {describe = d; bind = b;}
        const Describe* describe;
        Bind* bind;

    }
    static void binder(ref BindContext ctx) {}

    static void strBind(ref BindContext ctx) { //fix fixed length
        ctx.bind.type = ValueType.String;
        ctx.bind.oType = SQLT_STR;
        //ctx.bind.allocSize = cast(sb4) (ctx.describe.size + 1);
        ctx.bind.allocSize = 1024;
        ctx.bind.data = cast(void*)(allocator.allocate(b.allocSize));
        emplace(cast(OCIDate*) ctx.bind.data);

        // include byte for null terminator
        //d.buf_size = d.size ? d.size+1 : 1024*10; // FIX

        /*
           d.buf = new char[d.buf_size * ctx.row_array_size];
           d.valuep = d.buf;
           d.ind = new sb2[ctx.row_array_size];
           d.length = new ub2[ctx.row_array_size];
           d.unbind = oracle_str_unbind;
         */
    }

    struct BindInfo {
        ub2 colType;
        ub2 bindType;
        void function(ref BindContext ctx) bind;
        static const BindInfo[3] info = [
        {SQLT_INT,SQLT_INT,&binder},
        {SQLT_NUM,SQLT_STR,&binder},
        {SQLT_CHR,SQLT_STR,&binder}
        ];
    }


    struct Database {
        alias queryVariableType = QueryVariableType.Dollar;

        Allocator allocator;
        OCIEnv* env;
        OCIError *error;

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

        bool bindable() {return false;}
        bool dateBinding() {return false;}
        bool poolEnable() {return false;}
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

            check("OCILogon", OCILogon(
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
        void* data;
        sb4 allocSize;
        ub2 oType;
        void* ind;
        ub2 length;
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
        bool hasRows;
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
            check("OCIAttrGet", OCIAttrGet(
                        stmt,
                        OCI_HTYPE_STMT,
                        &stmt_type,
                        null,
                        OCI_ATTR_STMT_TYPE,
                        error));

            check("OCIAttrGet", OCIAttrGet(
                        stmt,
                        OCI_HTYPE_STMT,
                        &binds,
                        null,
                        OCI_ATTR_BIND_COUNT,
                        error));

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
            bindAll(args);
            query();
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
    }

    struct Result {
        Statement *stmt;
        Allocator *allocator;
        OCIError *error;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        ub4 row_array_size = 1;
        sword status;

        this(Statement* stmt_) {
            stmt = stmt_;
            allocator = &stmt.con.db.allocator;
            error = stmt.error;
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
                        stmt.stmt,
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
            import core.memory : GC; // needed?

            bind.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                bind ~= Bind();
                auto b = &bind.back();
                auto d = &describe[i];

                if (d.oType == SQLT_DAT) {
                    b.type = ValueType.Date;
                    b.oType = SQLT_ODT;
                    //d.define_type = SQLT_ODT;
                    b.allocSize = OCIDate.sizeof;
                    b.data = cast(void*)(allocator.allocate(b.allocSize));
                    emplace(cast(OCIDate*) b.data);
                } else {
                    //auto ctx = BindContext(d,b);
                    //strBind(ctx);
                    b.type = ValueType.String;
                    b.oType = SQLT_STR;
                    b.allocSize = cast(sb4) (d.size + 1);
                    b.data = cast(void*)(allocator.allocate(b.allocSize));
                }

                // initialize date?

                GC.addRange(b.data, b.allocSize);

                log("bind: type: ", b.oType, ", allocSize:", b.allocSize);

                check("OCIDefineByPos", OCIDefineByPos(
                            stmt.stmt,
                            &d.define,
                            error,
                            cast(ub4) i+1,
                            b.data,
                            b.allocSize,
                            b.oType,
                            &b.ind,
                            &b.length,
                            null,
                            OCI_DEFAULT));
            }
        }

        bool start() {return status == OCI_SUCCESS;}

        bool next() {

            //info("OCIStmtFetch2");
            status = OCIStmtFetch2(
                    stmt.stmt,
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

        auto get(X:string)(Bind *b) {
            import core.stdc.string: strlen;
            checkType(b.oType, SQLT_STR);
            auto ptr = cast(immutable char*) b.data;
            return cast(string) ptr[0..strlen(ptr)]; // fix with length
        }

        auto get(X:int)(Bind *b) {
            checkType(b.oType, SQLT_INT);
            return *(cast(int*) b.data);
        }

        auto get(X:Date)(Bind *b) {
            //return Date(2016,1,1); // fix
            checkType(b.oType, SQLT_ODT);
            auto d = cast(OCIDate*) b.data;
            return Date(d.OCIDateYYYY,d.OCIDateMM,d.OCIDateDD);
        }

        static void checkType(ub2 a, ub2 b) {
            if (a != b) throw new DatabaseException("type mismatch");
        }

    }
}

