module std.database.mysql.database;
import std.conv;
import core.stdc.config;

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
import std.container.array;
import std.experimental.logger;

import std.stdio;
import std.typecons;

struct Database {

    static Database create(string defaultURI) {
        return Database(defaultURI);
    }

    private struct Payload {}

    this(string defaultURI) {
    }

    Connection connection(string source) {
        return Connection(this, source);
    } 

}

struct Connection {
    alias Database = .Database;
    alias Statement = .Statement;

    private struct Payload {
        string url_;
        MYSQL *mysql_;

        this(Database db, string name) {
            writeln("name: ", name);

            mysql_ = mysql_init(null);
            if (!mysql_) {
                throw new DatabaseException("couldn't init mysql");
            }
        }

        ~this() {
            writeln("mysql closing ", url_);
            if (mysql_) {
                mysql_close(mysql_);
                mysql_ = null;
            }
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    package this(Database db, string url) {
        data_ = Data(db,url);
        open(url);
    }

    void open(string url) {

        alias const(ubyte)* cstring;

        Source source = resolve(url);

        if (!mysql_real_connect(
                    data_.mysql_,
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
    MYSQL_BIND *bind;
    c_ulong length;
    my_bool is_null;
    my_bool error;
}

void binder(int n, ref Bind b, ref MYSQL_BIND mb) {
    import core.stdc.string: memset;
    b.bind = &mb;
    memset(&mb, 0, MYSQL_BIND.sizeof);
    mb.buffer_type = b.mysql_type;
    mb.buffer = malloc(b.allocSize);
    mb.buffer_length = b.allocSize;
    mb.length = &b.length;
    mb.is_null = &b.is_null;
    mb.error = &b.error;

    log(
            "bind: index: ", n,
            ", type: ", mb.buffer_type,
            ", allocSize: ", b.allocSize);

    //GC.addRange(b.mb.buffer, allocSize);
}


struct Statement {
    alias Result = .Result;

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
        log("input bind: n: ", n, ", value: ", value);

        {
            Bind b;
            b.mysql_type = MYSQL_TYPE_LONG;
            b.allocSize = int.sizeof;
            inputBind(n, b);
        }

        {
            auto b = &data_.inputBind.back();
            b.is_null = 0;
            b.error = 0;
            *cast(int*)(b.bind.buffer) = value;
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
            b.is_null = 0;
            b.error = 0;

            auto p = cast(char*) b.bind.buffer;
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
        binder(n, data_.inputBind.back(), data_.mysqlBind.back());
    }

    struct Payload {
        Connection con;
        string sql;
        MYSQL_STMT *stmt;
        bool hasRows;
        uint binds;
        Array!Bind inputBind;
        Array!MYSQL_BIND mysqlBind;
        bool bindInit;

        this(Connection con_, string sql_) {
            con = con_;
            sql = sql_;
            stmt = mysql_stmt_init(con.data_.mysql_);
            if (!stmt) {
                throw new DatabaseException("stmt error");
            }
        }

        ~this() {
            for(int i = 0; i < mysqlBind.length; ++i) {
                free(mysqlBind[i].buffer);
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


struct Result {
    alias Range = .ResultRange;
    alias Row = .Row;

    int columns() {return data_.columns;}

    this(Statement stmt) {
        data_ = Data(stmt);
    }

    ResultRange range() {return ResultRange(this);}

    bool start() {return data_.status == 0;}
    bool next() {return data_.next();}

    private:

    static const maxData = 256;

    struct Payload {
        Statement stmt;
        uint columns;
        Array!Describe describe;
        Array!Bind bind;
        Array!MYSQL_BIND mysqlBind;
        MYSQL_RES *result_metadata;
        int status;

        this(Statement stmt_) {
            stmt = stmt_;

            result_metadata = mysql_stmt_result_metadata(stmt.data_.stmt);
            //columns = mysql_num_fields(result_metadata);

            build_describe();
            build_bind();
            next();
        }

        ~this() {
            for(int i = 0; i < mysqlBind.length; ++i) {
                free(mysqlBind[i].buffer);
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

                b.allocSize = cast(uint)(d.field.length + 1);
                b.mysql_type = MYSQL_TYPE_STRING;

                binder(i, bind.back(), mysqlBind.back());
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

    int toInt() {
        check(bind_.bind.buffer_type, MYSQL_TYPE_LONG);
        return *(cast(int*) bind_.bind.buffer);
    }

    //inout(char)[]
    auto chars() {
        check(bind_.bind.buffer_type, MYSQL_TYPE_STRING);
        import core.stdc.string: strlen;
        auto data = cast(char*) bind_.bind.buffer;
        return data ? data[0 .. strlen(data)] : data[0..0];
    }

    private:

    void check(int a, int b) {
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


