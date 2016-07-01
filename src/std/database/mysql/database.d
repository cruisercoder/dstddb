module std.database.mysql.database;
import std.conv;
import core.stdc.config;
import std.datetime;

import std.stdio;
import std.database.common;
import std.database.source;

version (Windows)
{
    pragma(lib, "libmysql");
}
else
{
    version (webscalesql)
    {
        pragma(lib, "webscalesql");
    }
    else
    {
        pragma(lib, "mysqlclient");
    }
}

import std.database.mysql.bindings;
import std.database.exception;
import std.database.allocator;
import std.database.front;
import std.container.array;
import std.experimental.logger;
import std.string;

// alias Database(T) = std.database.impl.Database!(T,DatabaseImpl!T); 

alias Database(T) = BasicDatabase!(Driver!T.Sync, T);

alias AsyncDatabase(T) = BasicDatabase!(Driver!T.Async, T);

struct DefaultPolicy
{
    alias Allocator = MyMallocator;
}

auto createDatabase()(string uri = "")
{
    return Database!DefaultPolicy(uri);
}

auto createDatabase(T)(string uri = "")
{
    return Database!T(uri);
}

private static bool isError()(int ret)
{
    return !(ret == 0 || ret == MYSQL_NO_DATA || ret == MYSQL_DATA_TRUNCATED);
}

private static T* check(T)(string msg, T* ptr)
{
    info(msg, ":", ptr);
    if (!ptr)
        raiseError(msg);
    return ptr;
}

private static int check()(string msg, MYSQL_STMT* stmt, int ret)
{
    info(msg, ":", ret);
    if (isError(ret))
        raiseError(msg, stmt, ret);
    return ret;
}

private static void raiseError()(string msg)
{
    throw new DatabaseException("mysql error: " ~ msg);
}

private static void raiseError()(string msg, int ret)
{
    throw new DatabaseException("mysql error: status: " ~ to!string(ret) ~ ":" ~ msg);
}

private static void raiseError()(string msg, MYSQL_STMT* stmt, int ret)
{
    import core.stdc.string : strlen;

    const(char*) err = mysql_stmt_error(stmt);
    throw new DatabaseException("mysql error: " ~ msg);
}

private struct Driver(Policy)
{

    struct Describe
    {
        int index;
        immutable(char)[] name;
        MYSQL_FIELD* field;
    }

    struct Bind
    {
        ValueType type;
        int mysql_type;
        int allocSize;
        void[] data;
        c_ulong length;
        my_bool is_null;
        my_bool error;
    }

    struct Sync
    {
        alias Allocator = Policy.Allocator;
        alias Cell = BasicCell!(Sync, Policy);
        alias const(ubyte)* cstring;

        alias Describe = Driver!Policy.Describe;
        alias Bind = Driver!Policy.Bind;

        struct Database
        {
            alias queryVariableType = QueryVariableType.QuestionMark;

            static const FeatureArray features = [Feature.InputBinding, Feature.DateBinding,
                //Feature.ConnectionPool,
                ];

            Allocator allocator;

            this(string uri)
            {
                allocator = Allocator();
                info("mysql client info: ", to!string(mysql_get_client_info()));
            }

            ~this()
            {
                log("~Database");
            }
        }

        struct Connection
        {
            Database* db;
            MYSQL* mysql;

            this(Database* db_, Source source)
            {
                db = db_;

                mysql = check("mysql_init", mysql_init(null));

                check("mysql_real_connect", mysql_real_connect(mysql,
                    cast(cstring) toStringz(source.server),
                    cast(cstring) toStringz(source.username),
                    cast(cstring) toStringz(source.password),
                    cast(cstring) toStringz(source.database), 0, null, 0));
            }

            ~this()
            {
                log("~Statement");
                if (mysql)
                    mysql_close(mysql);
                mysql = null;
            }

        }

        static void bindSetup(ref Array!Bind bind, ref Array!MYSQL_BIND mysqlBind)
        {
            // make this efficient
            mysqlBind.clear();
            mysqlBind.reserve(bind.length);
            for (int i = 0; i != bind.length; ++i)
            {
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

        struct Statement
        {
            Connection* con;
            string sql;
            Allocator* allocator;
            MYSQL_STMT* stmt;
            uint binds;
            Array!Bind inputBind;
            Array!MYSQL_BIND mysqlBind;
            bool bindInit;

            this(Connection* con_, string sql_)
            {
                con = con_;
                sql = sql_;
                allocator = &con.db.allocator;
                stmt = check("mysql_stmt_init", mysql_stmt_init(con.mysql));
            }

            ~this()
            {
                log("~Statement");
                foreach (b; inputBind)
                    allocator.deallocate(b.data);
                if (stmt)
                    mysql_stmt_close(stmt);
                // stmt = null? needed
            }

            // hoist?
            this(this)
            {
                assert(false);
            }

            void opAssign(Statement rhs)
            {
                assert(false);
            }

            void prepare()
            {
                check("mysql_stmt_prepare", stmt, mysql_stmt_prepare(stmt,
                    cast(char*) sql.ptr, sql.length));

                binds = cast(uint) mysql_stmt_param_count(stmt);
            }

            void query()
            {
                if (inputBind.length && !bindInit)
                {
                    bindInit = true;

                    bindSetup(inputBind, mysqlBind);

                    check("mysql_stmt_bind_param", stmt,
                        mysql_stmt_bind_param(stmt, &mysqlBind[0]));
                }

                info("execute: ", sql);
                check("mysql_stmt_execute", stmt, mysql_stmt_execute(stmt));
            }

            void query(X...)(X args)
            {
                bindAll(args);
                query();
            }

            bool hasRows()
            {
                return true;
            }

            void reset()
            {
            }

            private void bindAll(T...)(T args)
            {
                int col;
                foreach (arg; args)
                    bind(++col, arg);
            }

            void bind(int n, int value)
            {
                info("input bind: n: ", n, ", value: ", value);
                auto b = bindAlloc(n, MYSQL_TYPE_LONG, int.sizeof);
                b.is_null = 0;
                b.error = 0;
                *cast(int*)(b.data.ptr) = value;

            }

            void bind(int n, const char[] value)
            {
                import core.stdc.string : strncpy;

                info("input bind: n: ", n, ", value: ", value);

                auto b = bindAlloc(n, MYSQL_TYPE_STRING, 100 + 1); // fix
                b.is_null = 0;
                b.error = 0;

                auto p = cast(char*) b.data.ptr;
                strncpy(p, value.ptr, value.length);
                p[value.length] = 0;
                b.length = value.length;
            }

            void bind(int n, Date d)
            {
                auto b = bindAlloc(n, MYSQL_TYPE_DATE, MYSQL_TIME.sizeof);
                b.is_null = 0;
                b.error = 0;

                auto p = cast(MYSQL_TIME*) b.data.ptr;
                p.year = d.year;
                p.month = d.month;
                p.day = d.day;
            }

            Bind* bindAlloc(int n, int mysql_type, int allocSize)
            {
                if (n == 0)
                    throw new DatabaseException("zero index");
                auto idx = n - 1;
                if (idx > inputBind.length)
                    throw new DatabaseException("bind range error");
                if (idx == inputBind.length)
                    inputBind ~= Bind();
                auto b = &inputBind[idx];
                if (allocSize <= b.data.length)
                    return b; // fix
                b.mysql_type = mysql_type;
                b.allocSize = allocSize;
                b.data = allocator.allocate(b.allocSize);
                return b;
            }

        }

        struct Result
        {
            Statement* stmt;
            Allocator* allocator;
            uint columns;
            Array!Describe describe;
            Array!Bind bind;
            Array!MYSQL_BIND mysqlBind;
            MYSQL_RES* result_metadata;
            int status;

            static const maxData = 256;

            this(Statement* stmt_, int rowArraySize_)
            {
                stmt = stmt_;
                allocator = stmt.allocator;

                result_metadata = mysql_stmt_result_metadata(stmt.stmt);
                if (!result_metadata)
                    return;
                //columns = mysql_num_fields(result_metadata);

                build_describe();
                build_bind();
            }

            ~this()
            {
                log("~Result");
                foreach (b; bind)
                    allocator.deallocate(b.data);
                if (result_metadata)
                    mysql_free_result(result_metadata);
                log("~Result");
            }

            void build_describe()
            {
                import core.stdc.string : strlen;

                columns = cast(uint) mysql_stmt_field_count(stmt.stmt);

                describe.reserve(columns);

                for (int i = 0; i != columns; ++i)
                {
                    describe ~= Describe();
                    auto d = &describe.back();

                    d.index = i;
                    d.field = mysql_fetch_field(result_metadata);

                    auto p = cast(immutable(char)*) d.field.name;
                    d.name = p[0 .. strlen(p)];

                    info("describe: name: ", d.name, ", mysql type: ", d.field.type);
                }
            }

            void build_bind()
            {
                import core.stdc.string : memset;
                import core.memory : GC;

                bind.reserve(columns);

                for (int i = 0; i != columns; ++i)
                {
                    auto d = &describe[i];
                    bind ~= Bind();
                    auto b = &bind.back();
                    b.mysql_type = d.field.type;
                    switch (d.field.type)
                    {
                    case MYSQL_TYPE_TINY:
                        b.type = ValueType.Char;
                        break;
                    case MYSQL_TYPE_SHORT:
                        b.type = ValueType.Short;
                        break;
                        /*	case MYSQL_TYPE_INT24:
							b.mysql_type = MYSQL_TYPE_STRING;
							b.type = ValueType.
							goto case;*/
                    case MYSQL_TYPE_LONG:
                        b.type = ValueType.Int;
                        break;
                    case MYSQL_TYPE_LONGLONG:
                        b.type = ValueType.Long;
                        break;
                    case MYSQL_TYPE_FLOAT:
                        b.type = ValueType.Float;
                        break;
                    case MYSQL_TYPE_DOUBLE:
                        b.type = ValueType.Double;
                        break;

                    case MYSQL_TYPE_DATE:
                        b.type = ValueType.Date;
                        break;
                    case MYSQL_TYPE_TIME:
                    case MYSQL_TYPE_TIME2:
                        b.type = ValueType.Time;
                        break;
                    case MYSQL_TYPE_DATETIME2:
                    case MYSQL_TYPE_DATETIME:
                    case MYSQL_TYPE_TIMESTAMP2:
                    case MYSQL_TYPE_TIMESTAMP:
                        b.type = ValueType.DateTime;
                        break;
                    default:
                        b.mysql_type = MYSQL_TYPE_STRING;
                        b.type = ValueType.String;
                        break;

                    }
                    // let in ints for now
                    /*    if (d.field.type == MYSQL_TYPE_LONG) {
                        b.mysql_type = d.field.type;
                        b.type = ValueType.Int;
                    } else if (d.field.type == MYSQL_TYPE_DATE) {
                        b.mysql_type = d.field.type;
                        b.type = ValueType.Date;
                    } else {
                        b.mysql_type = MYSQL_TYPE_STRING;
                        b.type = ValueType.String;
                    }*/

                    b.allocSize = cast(uint)(d.field.length + 1);
                    b.data = allocator.allocate(b.allocSize);
                }

                bindSetup(bind, mysqlBind);

                mysql_stmt_bind_result(stmt.stmt, &mysqlBind.front());
            }

            bool hasResult()
            {
                return result_metadata != null;
            }

            int fetch()
            {
                status = check("mysql_stmt_fetch", stmt.stmt, mysql_stmt_fetch(stmt.stmt));
                if (!status)
                {
                    return 1;
                }
                else if (status == MYSQL_NO_DATA)
                {
                    //rows_ = row_count_;
                    return 0;
                }
                else if (status == MYSQL_DATA_TRUNCATED)
                {
                    raiseError("mysql_stmt_fetch: truncation", status);
                }

                raiseError("mysql_stmt_fetch", stmt.stmt, status);
                return 0;
            }

            // value getters

            Variant getValue(Cell* cell)
            {
                Variant value;
                switch (cell.bind.type)
                {
                case ValueType.Char:
                    {
                        auto t = (*cast(char*) cell.bind.data.ptr);
                        value = t;
                    }
                    break;
                case ValueType.Short:
                    {
                        auto t = (*cast(short*) cell.bind.data.ptr);
                        value = t;

                    }
                    break;
                case ValueType.Int:
                    {
                        auto t = (*cast(int*) cell.bind.data.ptr);
                        value = t;
                    }
                    break;
                case ValueType.Long:
                    {
                        auto t = (*cast(long*) cell.bind.data.ptr);
                        value = t;
                    }
                    break;
                case ValueType.Float:
                    {
                        auto t = (*cast(float*) cell.bind.data.ptr);
                        value = t;
                    }
                    break;
                case ValueType.Double:
                    {
                        auto t = (*cast(double*) cell.bind.data.ptr);
                        value = t;
                    }
                    break;
                case ValueType.String:
                    {
                        auto ptr = cast(char*) cell.bind.data.ptr;
                        value = cast(string)(ptr[0 .. cell.bind.length]);
                    }
                    break;
                case ValueType.Date:
                    {
                        MYSQL_TIME* t = cast(MYSQL_TIME*) cell.bind.data.ptr;
                        value = Date(t.year, t.month, t.day);
                    }
                    break;
                case ValueType.Time:
                    {
                        MYSQL_TIME* t = cast(MYSQL_TIME*) cell.bind.data.ptr;
                        value = Time(t.hour, t.minute, t.second);
                    }
                    break;
                case ValueType.DateTime:
                    {
                        MYSQL_TIME* t = cast(MYSQL_TIME*) cell.bind.data.ptr;
                        value = DateTime(t.year, t.month, t.day, t.hour, t.minute,
                            t.second);
                    }
                    break;
                default:
                    break;
                }
                return value;
            }

            /*
               char[] get(X:char[])(Bind *b) {
               auto ptr = cast(char*) b.data.ptr;
               return ptr[0..b.length];
               }
             */
            ubyte[] rawData(Cell* cell)
            {
                auto ptr = cast(ubyte*) cell.bind.data.ptr;
                return ptr[0 .. cell.bind.length];
            }

            bool isNull(Cell* cell)
            {
                return cell.bind.is_null > 0;
            }

            auto name(size_t idx)
            {
                return describe[idx].name;
            }

            auto get(X : string)(Cell* cell)
            {
                writeln("tostring``````````");
                return getValue(cell).toString();
            }

            auto get(X : int)(Cell* cell)
            {
                return getValue(cell).get!X();
            }

            auto get(X : Date)(Cell* cell)
            {
                return getValue(cell).get!X();
            }

            static void checkType(T)(Bind* b)
            {
                int x = TypeInfo!T.type();
                int y = b.mysql_type;
                if (x == y)
                    return;
                warning("type pair mismatch: ", x, ":", y);
                throw new DatabaseException("type mismatch");
            }

            // refactor as a better 1-n bind mapping
            struct TypeInfo(T : int)
            {
                static int type()
                {
                    return MYSQL_TYPE_LONG;
                }
            }

            struct TypeInfo(T : string)
            {
                static int type()
                {
                    return MYSQL_TYPE_STRING;
                }
            }

            struct TypeInfo(T : Date)
            {
                static int type()
                {
                    return MYSQL_TYPE_DATE;
                }
            }

        }
    }

    struct Async
    {
        alias Allocator = Policy.Allocator;
        alias Describe = Driver!Policy.Describe;
        alias Bind = Driver!Policy.Bind;
        alias Cell = BasicCell!(Async, Policy);

        struct Database
        {
            alias queryVariableType = QueryVariableType.QuestionMark;

            static const FeatureArray features = [Feature.InputBinding, Feature.DateBinding,
                //Feature.ConnectionPool,
                ];

            this(string defaultURI)
            {
                info("mysql client info: ", to!string(mysql_get_client_info()));
            }

            bool bindable()
            {
                return true;
            }

            bool dateBinding()
            {
                return true;
            }

            bool poolEnable()
            {
                return false;
            }
        }

        struct Connection
        {
            Database* db;
            MYSQL* mysql;

            this(Database* db_, Source source)
            {
                db = db_;

                mysql = check("mysql_init", mysql_init(null));

                check("mysql_real_connect", mysql_real_connect(mysql,
                    cast(cstring) toStringz(source.server),
                    cast(cstring) toStringz(source.username),
                    cast(cstring) toStringz(source.password),
                    cast(cstring) toStringz(source.database), 0, null, 0));
            }

            ~this()
            {
                log("~Statement");
                if (mysql)
                    mysql_close(mysql);
                mysql = null;
            }

        }

        static void bindSetup(ref Array!Bind bind, ref Array!MYSQL_BIND mysqlBind)
        {
            // make this efficient
            mysqlBind.clear();
            mysqlBind.reserve(bind.length);
            for (int i = 0; i != bind.length; ++i)
            {
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

        struct Statement
        {
            Connection* con;
            string sql;
            Allocator allocator;
            MYSQL_STMT* stmt;
            uint binds;
            Array!Bind inputBind;
            Array!MYSQL_BIND mysqlBind;
            bool bindInit;

            this(Connection* con_, string sql_)
            {
                con = con_;
                sql = sql_;
                //allocator = &con.db.allocator;
                stmt = mysql_stmt_init(con.mysql);
                if (!stmt)
                    throw new DatabaseException("stmt error");
            }

            ~this()
            {
                foreach (b; inputBind)
                    allocator.deallocate(b.data);
                if (stmt)
                    mysql_stmt_close(stmt);
                // stmt = null? needed
            }

            // hoist?
            this(this)
            {
                assert(false);
            }

            void opAssign(Statement rhs)
            {
                assert(false);
            }

            void prepare()
            {
                check("mysql_stmt_prepare", stmt, mysql_stmt_prepare(stmt,
                    cast(char*) sql.ptr, sql.length));

                binds = cast(uint) mysql_stmt_param_count(stmt);
            }

            void query()
            {
                if (inputBind.length && !bindInit)
                {
                    bindInit = true;

                    bindSetup(inputBind, mysqlBind);

                    check("mysql_stmt_bind_param", stmt,
                        mysql_stmt_bind_param(stmt, &mysqlBind[0]));
                }

                info("execute: ", sql);
                check("mysql_stmt_execute", stmt, mysql_stmt_execute(stmt));
            }

            void query(X...)(X args)
            {
                bindAll(args);
                query();
            }

            bool hasRows()
            {
                return true;
            }

            void reset()
            {
            }

            private void bindAll(T...)(T args)
            {
                int col;
                foreach (arg; args)
                    bind(++col, arg);
            }

            void bind(int n, int value)
            {
                info("input bind: n: ", n, ", value: ", value);
                auto b = bindAlloc(n, MYSQL_TYPE_LONG, int.sizeof);
                b.is_null = 0;
                b.error = 0;
                *cast(int*)(b.data.ptr) = value;

            }

            void bind(int n, const char[] value)
            {
                import core.stdc.string : strncpy;

                info("input bind: n: ", n, ", value: ", value);

                auto b = bindAlloc(n, MYSQL_TYPE_STRING, 100 + 1); // fix
                b.is_null = 0;
                b.error = 0;

                auto p = cast(char*) b.data.ptr;
                strncpy(p, value.ptr, value.length);
                p[value.length] = 0;
                b.length = value.length;
            }

            void bind(int n, Date d)
            {
                auto b = bindAlloc(n, MYSQL_TYPE_DATE, MYSQL_TIME.sizeof);
                b.is_null = 0;
                b.error = 0;

                auto p = cast(MYSQL_TIME*) b.data.ptr;
                p.year = d.year;
                p.month = d.month;
                p.day = d.day;
            }

            Bind* bindAlloc(int n, int mysql_type, int allocSize)
            {
                if (n == 0)
                    throw new DatabaseException("zero index");
                auto idx = n - 1;
                if (idx > inputBind.length)
                    throw new DatabaseException("bind range error");
                if (idx == inputBind.length)
                    inputBind ~= Bind();
                auto b = &inputBind[idx];
                if (allocSize <= b.data.length)
                    return b; // fix
                b.mysql_type = mysql_type;
                b.allocSize = allocSize;
                b.data = allocator.allocate(b.allocSize);
                return b;
            }

        }

        struct Result
        {
            Statement* stmt;
            Allocator allocator;
            uint columns;
            Array!Describe describe;
            Array!Bind bind;
            Array!MYSQL_BIND mysqlBind;
            MYSQL_RES* result_metadata;
            int status;

            static const maxData = 256;

            this(Statement* stmt_, int rowArraySize_)
            {
                stmt = stmt_;
                //allocator = stmt.allocator;

                result_metadata = mysql_stmt_result_metadata(stmt.stmt);
                //columns = mysql_num_fields(result_metadata);

                build_describe();
                build_bind();
            }

            ~this()
            {
                //log("~Result");
                foreach (b; bind)
                    allocator.deallocate(b.data);
                if (result_metadata)
                    mysql_free_result(result_metadata);
            }

            void build_describe()
            {
                import core.stdc.string : strlen;

                columns = cast(uint) mysql_stmt_field_count(stmt.stmt);

                describe.reserve(columns);

                for (int i = 0; i < columns; ++i)
                {
                    describe ~= Describe();
                    auto d = &describe.back();

                    d.index = i;
                    d.field = mysql_fetch_field(result_metadata);

                    auto p = cast(immutable(char)*) d.field.name;
                    d.name = p[0 .. strlen(p)];

                    info("describe: name: ", d.name, ", mysql type: ", d.field.type);
                }
            }

            void build_bind()
            {
                import core.stdc.string : memset;
                import core.memory : GC;

                bind.reserve(columns);

                for (int i = 0; i < columns; ++i)
                {
                    auto d = &describe[i];
                    bind ~= Bind();
                    auto b = &bind.back();

                    switch (d.field.type)
                    {
                    case MYSQL_TYPE_TINY:
                        b.type = ValueType.Char;
                        break;
                    case MYSQL_TYPE_SHORT:
                        b.type = ValueType.Short;
                        break;
                    case MYSQL_TYPE_INT24:
                        b.mysql_type = MYSQL_TYPE_LONG;
                        goto case;
                    case MYSQL_TYPE_LONG:
                        b.type = ValueType.Int;
                        break;
                    case MYSQL_TYPE_LONGLONG:
                        b.type = ValueType.Long;
                        break;
                    case MYSQL_TYPE_FLOAT:
                        b.type = ValueType.Float;
                        break;
                    case MYSQL_TYPE_DOUBLE:
                        b.type = ValueType.Double;
                        break;

                    case MYSQL_TYPE_DATE:
                        b.type = ValueType.Date;
                        break;
                    case MYSQL_TYPE_TIME:
                    case MYSQL_TYPE_TIME2:
                        b.type = ValueType.Time;
                        break;
                    case MYSQL_TYPE_DATETIME2:
                    case MYSQL_TYPE_DATETIME:
                    case MYSQL_TYPE_TIMESTAMP2:
                    case MYSQL_TYPE_TIMESTAMP:
                        b.type = ValueType.DateTime;
                        break;
                    default:
                        b.mysql_type = MYSQL_TYPE_STRING;
                        b.type = ValueType.String;
                        break;

                    }

                    b.allocSize = cast(uint)(d.field.length + 1);
                    b.data = allocator.allocate(b.allocSize);
                }

                bindSetup(bind, mysqlBind);

                mysql_stmt_bind_result(stmt.stmt, &mysqlBind.front());
            }

            int fetch()
            {
                status = check("mysql_stmt_fetch", stmt.stmt, mysql_stmt_fetch(stmt.stmt));
                if (!status)
                {
                    return 1;
                }
                else if (status == MYSQL_NO_DATA)
                {
                    //rows_ = row_count_;
                    return 0;
                }
                else if (status == MYSQL_DATA_TRUNCATED)
                {
                    raiseError("mysql_stmt_fetch: truncation", status);
                }

                raiseError("mysql_stmt_fetch", stmt.stmt, status);
                return 0;
            }

            Variant getValue(Cell* cell)
            {
                Variant value;
                switch (cell.bind.type)
                {
                case ValueType.Char:
                    value = (*cast(char*) cell.bind.data.ptr);
                    break;
                case ValueType.Short:
                    value = (*cast(short*) cell.bind.data.ptr);
                    break;
                case ValueType.Int:
                    value = (*cast(int*) cell.bind.data.ptr);
                    break;
                case ValueType.Long:
                    value = (*cast(long*) cell.bind.data.ptr);
                    break;
                case ValueType.Float:
                    value = (*cast(float*) cell.bind.data.ptr);
                    break;
                case ValueType.Double:
                    value = (*cast(double*) cell.bind.data.ptr);
                    break;
                case ValueType.String:
                    {
                        auto ptr = cast(char*) cell.bind.data.ptr;
                        value = cast(string)(ptr[0 .. cell.bind.length]);
                    }
                    break;
                case ValueType.Date:
                    {
                        MYSQL_TIME* t = cast(MYSQL_TIME*) cell.bind.data.ptr;
                        value = Date(t.year, t.month, t.day);
                    }
                    break;
                case ValueType.Time:
                    {
                        MYSQL_TIME* t = cast(MYSQL_TIME*) cell.bind.data.ptr;
                        value = Time(t.hour, t.minute, t.second);
                    }
                    break;
                case ValueType.DateTime:
                    {
                        MYSQL_TIME* t = cast(MYSQL_TIME*) cell.bind.data.ptr;
                        value = DateTime(t.year, t.month, t.day, t.hour, t.minute,
                            t.second);
                    }
                    break;
                default:
                    break;
                }
                return value;
            }

            // value getters

            auto name(size_t idx)
            {
                return describe[idx].name;
            }

            ubyte[] rawData(Cell* cell)
            {
                auto ptr = cast(ubyte*) cell.bind.data.ptr;
                return ptr[0 .. cell.bind.length];
            }

            bool isNull(Cell* cell)
            {
                return cell.bind.is_null > 0;
            }

            auto get(X : string)(Cell* cell)
            {
                return getValue(cell).toString();
            }

            auto get(X : int)(Cell* cell)
            {
                return getValue(cell).get!X();
            }

            auto get(X : Date)(Cell* cell)
            {
                return getValue(cell).get!X();
            }

            static void checkType(T)(Bind* b)
            {
                int x = TypeInfo!T.type();
                int y = b.mysql_type;
                if (x == y)
                    return;
                warning("type pair mismatch: ", x, ":", y);
                throw new DatabaseException("type mismatch");
            }

            // refactor as a better 1-n bind mapping
            struct TypeInfo(T : int)
            {
                static int type()
                {
                    return MYSQL_TYPE_LONG;
                }
            }

            struct TypeInfo(T : string)
            {
                static int type()
                {
                    return MYSQL_TYPE_STRING;
                }
            }

            struct TypeInfo(T : Date)
            {
                static int type()
                {
                    return MYSQL_TYPE_DATE;
                }
            }

        }
    }

}
