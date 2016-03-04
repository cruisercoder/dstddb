module std.database.mysql.database;
import std.conv;
import core.stdc.config;
import std.experimental.allocator.mallocator;

version(Windows) {
    pragma(lib, "libmysql");
}
else {
    pragma(lib, "mysqlclient");
}

import std.string;
import core.stdc.stdlib;

import std.database.mysql.bindings;
public import std.database.exception;
public import std.database.resolver;
public import std.database.allocator;
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

struct Database(T) {
    alias Allocator = T.Allocator;

    // temporary
    auto connection() {return Connection!T(this);}
    auto connection(string uri) {return Connection!T(this, uri);}
    void execute(string sql) {connection().execute(sql);}

    bool bindable() {return true;}

    private struct Payload {
        string defaultURI;
        Allocator allocator;

        this(string defaultURI_) {
            defaultURI = defaultURI_;
            allocator = Allocator();
        }
    }

    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

}

struct Connection(T) {
    //alias Database = .Database;
    //alias Statement = .Statement;

    // temporary helper functions
    auto statement(string sql) {return Statement!T(this,sql);}
    auto statement(X...) (string sql, X args) {return Statement!T(this,sql,args);}
    auto execute(string sql) {return statement(sql).execute();}
    auto execute(T...) (string sql, T args) {return statement(sql).execute(args);}

    private struct Payload {
        Database!T db;
        string uri;
        MYSQL *mysql;

        this(Database!T db_, string uri_) {
            db = db_;
            uri = uri_.length == 0 ? db_.data_.defaultURI : uri_;

            mysql = mysql_init(null);
            if (!mysql) {
                throw new DatabaseException("couldn't init mysql");
            }

            open();
        }

        ~this() {
            info("mysql closing ", uri);
            if (mysql) {
                mysql_close(mysql);
                mysql = null;
            }
        }

        this(this) { assert(false); }
        void opAssign(Connection!T.Payload rhs) { assert(false); }

        void open() {
            alias const(ubyte)* cstring;

            Source source = resolve(uri);

            if (!mysql_real_connect(
                        mysql,
                        cast(cstring) toStringz(source.server),
                        cast(cstring) toStringz(source.username),
                        cast(cstring) toStringz(source.password),
                        cast(cstring) toStringz(source.database),
                        0,
                        null,
                        0)) {
                throw new ConnectionException("couldn't connect");
            }
        }

    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    package this(Database!T db, string uri="") {
        data_ = Data(db,uri);
    }

}

struct Describe {
    int index;
    string name;
    //nd_mysql_type type;
    uint type;
    MYSQL_FIELD *field;
}

struct Bind {
    int mysql_type;
    int allocSize;
    void[] data;
    c_ulong length;
    my_bool is_null;
    my_bool error;
}

//GC.addRange(b.mb.buffer, allocSize);

void bindSetup()(ref Array!Bind bind, ref Array!MYSQL_BIND mysqlBind) {
    // make this efficient
    mysqlBind.clear();
    mysqlBind.reserve(bind.length);
    for(int i=0; i!=bind.length; ++i) {
        mysqlBind ~= MYSQL_BIND();
        //import core.stdc.string: memset;
        //memset(mb, 0, MYSQL_BIND.sizeof); // might not be needed: D struct
        auto b = &bind[i];
        auto mb = &mysqlBind[i];
        mb.buffer_type = b.mysql_type;
        mb.buffer = b.data.ptr;
        mb.buffer_length = b.allocSize;
        mb.length = &b.length;
        mb.is_null = &b.is_null;
        mb.error = &b.error;
    }
}


// non memeber needed to avoid forward error
//auto range(T)(Statement!T stmt) {return Result!T(stmt).range();}

struct Statement(T) {
    alias Allocator = T.Allocator;
    //alias Result = .Result;

    // temporary
    auto result() {return Result!T(this);}
    auto opSlice() {return result();}

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
        //execute();
    }

    string sql() {return data_.sql;}
    int binds() {return data_.binds;}

    void bind(int n, int value) {
        info("input bind: n: ", n, ", value: ", value);
        if (n==0) throw new DatabaseException("zero index");
        auto idx = n-1;
        if (idx > data_.inputBind.length) throw new DatabaseException("bind range error");

        if (idx == data_.inputBind.length) {
            Bind b;
            b.mysql_type = MYSQL_TYPE_LONG;
            b.allocSize = int.sizeof;
            inputBind(n, b);
        }

        {
            auto b = &data_.inputBind[idx];
            b.is_null = 0;
            b.error = 0;
            *cast(int*)(b.data.ptr) = value;
        }

    }

    void bind(int n, const char[] value){
        import core.stdc.string: strncpy;
        info("input bind: n: ", n, ", value: ", value);
        // need default allocSize, bounds checking
        if (n==0) throw new DatabaseException("zero index");
        auto idx = n-1;
        if (idx > data_.inputBind.length) throw new DatabaseException("bind range error");

        if (idx == data_.inputBind.length) {
            Bind b;
            b.mysql_type = MYSQL_TYPE_STRING;
            b.allocSize = cast(uint)(100 + 1);
            inputBind(n, b);
        }

        {
            auto b = &data_.inputBind[idx];
            b.is_null = 0;
            b.error = 0;

            auto p = cast(char*) b.data.ptr;
            strncpy(p, value.ptr, value.length);
            p[value.length] = 0;
            b.length = value.length;
            //info("BOUND VALUE: -", p[0..b.length], "-",
            //", length: ", b.length,
            //", is_null: ", cast(bool) b.is_null);
        }
    }

    private:

    void inputBind(int n, ref Bind bind) {
        data_.inputBind ~= bind;
        auto b = &data_.inputBind.back();
        b.data = data_.allocator.allocate(b.allocSize);
    }

    struct Payload {
        Connection!T con;
        string sql;
        Allocator *allocator;
        MYSQL_STMT *stmt;
        bool hasRows;
        uint binds;
        Array!Bind inputBind;
        Array!MYSQL_BIND mysqlBind;
        bool bindInit;

        this(Connection!T con_, string sql_) {
            con = con_;
            sql = sql_;
            allocator = &con.data_.db.data_.allocator;

            stmt = mysql_stmt_init(con.data_.mysql);
            if (!stmt) throw new DatabaseException("stmt error");
        }

        ~this() {
            foreach(b; inputBind) allocator.deallocate(b.data);
            if (stmt) mysql_stmt_close(stmt);
            // stmt = null? needed
        }

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }


        void prepare() {
            check("mysql_stmt_prepare", stmt, mysql_stmt_prepare(
                        stmt,
                        cast(char*) sql.ptr,
                        sql.length));

            binds = cast(uint) mysql_stmt_param_count(stmt);
        }

        void execute() {

            if (inputBind.length && !bindInit) {
                bindInit = true;

                bindSetup(inputBind, mysqlBind);

                check("mysql_stmt_bind_param",
                        stmt,
                        mysql_stmt_bind_param(stmt, &mysqlBind[0]));
            }

            check("mysql_stmt_execute", stmt, mysql_stmt_execute(stmt));
        }

    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

    void exec() {
        check("mysql_stmt_execute", data_.stmt, mysql_stmt_execute(
                    data_.stmt));
    }

    void prepare() {
        data_.prepare();
    }

    // clean up
    public:


    auto execute() {
        data_.execute();
        return result();
    }

    auto execute(X...) (X args) {
        int col;
        foreach (arg; args) {
            bind(++col, arg);
        }
        return execute();
    }

    void bindAll(T...) (T args) {
        int col;
        foreach (arg; args) {
            bind(++col, arg);
        }
    }

    private:

    void reset() {
        //SQLCloseCursor
    }

    static void check(string msg, MYSQL_STMT* stmt, int ret) {
        info(msg, ":", ret);
        if (ret) error(msg,stmt,ret);
    }

    static void error(string msg, MYSQL_STMT* stmt, int ret) {
        info(msg, ":", ret);
        if (!ret) return;
        import core.stdc.string: strlen;
        const(char*) err = mysql_stmt_error(stmt);
        info("error: ", err[0..strlen(err)]); //fix
        throw new DatabaseException("mysql error: " ~ msg);
    }

}


struct Result(T) {
    alias Allocator = T.Allocator;
    //alias Range = .ResultRange!T;
    //alias Row = .Row;

    int columns() {return data_.columns;}

    this(Statement!T stmt) {
        data_ = Data(stmt);
    }

    auto opSlice() {return ResultRange!T(this);}

package:

    bool start() {return data_.status == 0;}
    bool next() {return data_.next();}

    private:

    static const maxData = 256;

    struct Payload {
        Statement!T stmt;
        Allocator *allocator;
        uint columns;
        Array!Describe describe;
        Array!Bind bind;
        Array!MYSQL_BIND mysqlBind;
        MYSQL_RES *result_metadata;
        int status;

        this(Statement!T stmt_) {
            stmt = stmt_;
            allocator = stmt.data_.allocator;

            result_metadata = mysql_stmt_result_metadata(stmt.data_.stmt);
            if (!result_metadata) return;
            //columns = mysql_num_fields(result_metadata);

            build_describe();
            build_bind();
            next();
        }

        ~this() {
            foreach(b; bind) allocator.deallocate(b.data);
            if (result_metadata) mysql_free_result(result_metadata);
        }

        void build_describe() {
            import core.stdc.string: strlen;

            columns = cast(uint) mysql_stmt_field_count(stmt.data_.stmt);

            describe.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                describe ~= Describe();
                auto d = &describe.back();

                d.index = i;
                d.field = mysql_fetch_field(result_metadata);

                //d.name = to!string(d.field.name);
                const(char*) p = cast(const(char*)) d.field.name;
                d.name = to!string(p[0 .. strlen(p)]);

                //d.type = info[di.field.type].type;

                info("describe: name: ", d.name, ", mysql type: ", d.field.type);
            }
        }

        void build_bind() {
            import core.stdc.string: memset;
            import core.memory : GC;

            bind.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                auto d = &describe[i];
                bind ~= Bind();
                auto b = &bind.back();

                b.mysql_type = MYSQL_TYPE_STRING;
                b.allocSize = cast(uint)(d.field.length + 1);
                b.data = allocator.allocate(b.allocSize);
            }

            bindSetup(bind, mysqlBind);

            mysql_stmt_bind_result(stmt.data_.stmt, &mysqlBind.front());
        }

        bool next() {
            status = mysql_stmt_fetch(stmt.data_.stmt);
            if (!status) {
                return true;
            } else if (status == MYSQL_NO_DATA) {
                //rows_ = row_count_;
                return false;
            } else if (status == MYSQL_DATA_TRUNCATED) {
                throw new DatabaseException("fetch: database truncation");
            }

            stmt.error("mysql_stmt_fetch",stmt.data_.stmt,status);
            return false;
        }

        this(this) { assert(false); }
        void opAssign(Statement!T.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

}

struct Value(T) {
    package Bind* bind_;

    this(Bind* bind) {
        bind_ = bind;
    }

    auto as(X:int)() {
        if (bind_.mysql_type == MYSQL_TYPE_STRING) return to!int(as!string()); // tmp hack
        check(bind_.mysql_type, MYSQL_TYPE_LONG);
        return *cast(int*) bind_.data.ptr;
    }

    auto as(X:string)() {
        check(bind_.mysql_type, MYSQL_TYPE_STRING);
        auto ptr = cast(immutable char*) bind_.data.ptr;
        return cast(string) ptr[0..bind_.length];
    }

    //inout(char)[]
    auto chars() {
        check(bind_.mysql_type, MYSQL_TYPE_STRING);
        auto d = cast(char*) bind_.data.ptr;
        return d? d[0..bind_.length] : d[0..0];
    }

    private:

    void check(int a, int b) {
        if (a != b) {
            info("mismatch: ",a, ":", b); // fix
            throw new DatabaseException("type mismatch");
        }
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


