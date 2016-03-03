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
import std.c.stdlib;

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
        Allocator allocator;
        string defaultURI;
        this(string defaultURI_) {
            defaultURI = defaultURI_;
            allocator = MyMallocator();
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
    auto execute(string sql) {auto stmt = Statement!T(this, sql);}

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
            writeln("mysql closing ", uri);
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
    //MYSQL_BIND *bind; //bad
    c_ulong length;
    my_bool is_null;
    my_bool error;
}

void binder(T)(ref T allocator, int n, Bind *b, MYSQL_BIND *mb) {
    import core.stdc.string: memset;
    memset(mb, 0, MYSQL_BIND.sizeof);
    mb.buffer_type = b.mysql_type;

    mb.buffer = cast(void*)(allocator.allocate(b.allocSize));

    mb.buffer_length = b.allocSize;
    mb.length = &b.length;
    mb.is_null = &b.is_null;
    mb.error = &b.error;

    /*
       log(
       "bind: index: ", n,
       ", type: ", mb.buffer_type,
       ", allocSize: ", b.allocSize);
     */

    //GC.addRange(b.mb.buffer, allocSize);
}

// non memeber needed to avoid forward error
//auto range(T)(Statement!T stmt) {return Result!T(stmt).range();}

struct Statement(T) {
    alias Allocator = T.Allocator;
    //alias Result = .Result;

    // temporary
    auto result() {return Result!T(this);}
    auto range() {return result().range();} // no size error

    this(Connection!T con, string sql) {
        data_ = Data(con,sql);
        prepare();
        // must be able to detect binds in all DBs
        if (!data_.binds) execute();
    }

    this(X...) (Connection!T con, string sql, X args) {
        data_ = Data(con,sql);
        prepare();
        bindAll(args);
        execute();
    }

    string sql() {return data_.sql;}
    int binds() {return data_.binds;}

    void bind(int n, int value) {
        log("input bind: n: ", n, ", value: ", value);
        if (n==0) throw new DatabaseException("zero index");

        {
            Bind b;
            b.mysql_type = MYSQL_TYPE_LONG;
            b.allocSize = int.sizeof;
            inputBind(n, b);
        }

        {
            auto b = &data_.inputBind.back();
            auto mb = &data_.mysqlBind.back();
            b.is_null = 0;
            b.error = 0;
            *cast(int*)(mb.buffer) = value;
        }

    }

    void bind(int n, const char[] value){
        import core.stdc.string: strncpy;
        log("input bind: n: ", n, ", value: ", value);
        // need default allocSize, bounds checking

        {
            Bind b;
            b.mysql_type = MYSQL_TYPE_STRING;
            b.allocSize = cast(uint)(100 + 1);
            inputBind(n, b);
        }

        {
            auto b = &data_.inputBind.back();
            auto mb = &data_.mysqlBind.back();
            b.is_null = 0;
            b.error = 0;

            auto p = cast(char*) mb.buffer;
            strncpy(p, value.ptr, value.length);
            p[value.length] = 0;
            b.length = value.length;
            //writeln("BOUND VALUE: -", p[0..b.length], "-",
            //", length: ", b.length,
            //", is_null: ", cast(bool) b.is_null);
        }
    }

    private:

    void inputBind(int n, ref Bind bind) {
        data_.inputBind ~= bind;
        data_.mysqlBind ~= MYSQL_BIND();

        auto b = &data_.inputBind.back();
        auto mb = &data_.mysqlBind.back();

        binder(data_.allocator, n, b, mb);
    }

    struct Payload {
        Connection!T con;
        Allocator *allocator;
        string sql;
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
            for(int i = 0; i < mysqlBind.length; ++i) {
                allocator.deallocate(mysqlBind[i].buffer[0..inputBind[i].allocSize]);
            }

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

    void execute() {
        data_.execute();
    }

    void execute(X...) (X args) {
        int col;
        foreach (arg; args) {
            bind(++col, arg);
        }
        execute();
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


    static void check(string msg, MYSQL_STMT* stmt, int ret) {
        log(msg, ":", ret);
        if (!ret) return;
        import core.stdc.string: strlen;
        const(char*) err = mysql_stmt_error(stmt);
        writeln("error: ", err[0..strlen(err)]);
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

    ResultRange!T range() {return ResultRange!T(this);}

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
            //columns = mysql_num_fields(result_metadata);

            build_describe();
            build_bind();
            next();
        }

        ~this() {
            for(int i = 0; i < mysqlBind.length; ++i) {
                allocator.deallocate(mysqlBind[i].buffer[0..bind[i].allocSize]);
            }

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

                log("describe: name: ", d.name, ", mysql type: ", d.field.type);
            }
        }

        void build_bind() {
            import core.stdc.string: memset;
            import core.memory : GC;

            bind.reserve(columns);
            mysqlBind.reserve(columns);

            for(int i = 0; i < columns; ++i) {
                auto d = &describe[i];
                bind ~= Bind();
                auto b = &bind.back();
                mysqlBind ~= MYSQL_BIND();
                auto mb = &mysqlBind.back();

                b.allocSize = cast(uint)(d.field.length + 1);
                b.mysql_type = MYSQL_TYPE_STRING;

                binder(allocator, i, b, mb);
            }

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
            throw new DatabaseException("fetch error");
        }

        this(this) { assert(false); }
        void opAssign(Statement!T.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

}

struct Value(T) {
    package Bind* bind_;
    private MYSQL_BIND *mysqlBind_;

    this(Bind* bind, MYSQL_BIND *mysqlBind) {
        bind_ = bind;
        mysqlBind_ = mysqlBind;
    }

    int get(X) () {
        return toInt();
    }

    int toInt() {
        check(mysqlBind_.buffer_type, MYSQL_TYPE_LONG);
        return *cast(int*) mysqlBind_.buffer;
        //return *(cast(int*) bind_.bind.buffer);
    }

    //inout(char)[]
    auto chars() {
        check(mysqlBind_.buffer_type, MYSQL_TYPE_STRING);
        import core.stdc.string: strlen;
        auto d = cast(char*) mysqlBind_.buffer;
        return d? d[0 .. strlen(d)] : d[0..0]; //fix
    }

    private:

    void check(int a, int b) {
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
        return Value(&result_.data_.bind[idx],&result_.data_.mysqlBind[idx]);
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


