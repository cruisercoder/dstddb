module std.database.poly.database;

import std.string;
import core.stdc.stdlib;
import std.conv;
import std.experimental.logger;

public import std.database.exception;

import std.stdio;
import std.typecons;
import std.container.array;
import std.database.front;
import std.database.allocator;
import std.database.source;
import std.database.common;
import std.datetime;
import std.database.uri;
import std.variant;
import std.database.variant;

import std.meta;

alias Database(T) = BasicDatabase!(Driver!T,T);

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

auto registerDatabase(DB)(string name) {
    alias PolyDB = Database!DefaultPolicy;
    PolyDB.register!DB(name);
}

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

struct Driver(Policy) {
    alias Allocator = Policy.Allocator;
    alias Cell = BasicCell!(Driver,Policy);
    alias BindArgs = Array!Variant;

    // revise using allocator make

    static auto construct(T, A, X...)(ref A allocator, X args) {
        import core.memory : GC; // needed?
        auto s = cast(T[]) allocator.allocate(T.sizeof);
        GC.addRange(s.ptr, s.length);
        emplace!T(s, args);
        return cast(void[]) s; // cast apparently necessary or get array cast misallignment
        //return s; // cast apparently necessary or get array cast misallignment
    }

    static auto destruct(T,A)(ref A allocator, void[] data) {
        import core.memory : GC; // needed?
        .destroy(*(cast(T*) data.ptr));
        allocator.deallocate(data);
        GC.removeRange(data.ptr);
    }

    static auto toTypedPtr(T)(void[] data) {return (cast(T[]) data).ptr;}

    static struct DBVtable {
        void[] function(string defaultURI) create;
        void function(void[]) destroy;
        const(Feature[]) function(void[] db) features; // how to make parameter ref const(FeatureArray)
    }

    static struct ConVTable {
        void[] function(void[], Source source) create;
        void function(void[]) destroy;
    }

    static struct StmtVTable {
        void[] function(void[], string sql) create;
        void function(void[]) destroy;
        void function(void[] stmt) prepare;
        void function(void[] stmt) query;
        void function(void[] stmt, ref BindArgs ba) variadicQuery;
    }

    static struct DriverInfo {
        string name;
        DBVtable dbVtable;
        ConVTable conVtable;
        StmtVTable stmtVtable;
    }

    static struct DBGen(Driver) {
        private static Allocator alloc = MyMallocator();
        alias Database = Driver.Database;
        alias Connection = Driver.Connection;

        static void[] create(string uri) {return construct!Database(alloc, uri);}
        static void destroy(void[] db) {destruct!Database(alloc, db);}

        static const(Feature[]) features(void[] db) {
            //return DB.features;
            return (cast(Database*) db.ptr).features;
        }

        static DBVtable vtable = {
            &create,
            &destroy,
            &features,
        };
    }

    static struct ConGen(Driver) {
        private static Allocator alloc = MyMallocator();
        alias Database = Driver.Database;
        alias Connection = Driver.Connection;

        static void[] create(void[] db, Source source) {
            return construct!Connection(alloc, toTypedPtr!Database(db), source);
        }

        static void destroy(void[] con) {destruct!Connection(alloc, con);}

        static ConVTable vtable = {
            &create,
            &destroy,
        };
    }


    static struct StmtGen(Driver) {
        private static Allocator alloc = MyMallocator();
        alias Connection = Driver.Connection;
        alias Statement = Driver.Statement;

        // doesn't work outside of scope

        static void constructQuery(int i=0, A...)(Statement* stmt, A a) {
            // list of primitive types somewhere ?
            // dstring causes problems
            //alias Types = AliasSeq!(byte, ubyte, string, char, dchar, int, uint, long, ulong);
            alias Types = AliasSeq!(int, string, Date);

            static void call(int i, T, A...)(Statement* stmt, T v, A a) {
                constructQuery!(i+1)(stmt, a[0..i], v, a[(i+1)..$]);
            }

            static if (i == a.length) {
                stmt.query(a);
            } else {
                //log("type: ", a[i].type);
                foreach(T; Types) {
                    //log("--TYPE: ", typeid(T));
                    //if (a[i].type == typeid(T))
                    if (a[i].convertsTo!T) {
                        call!i(stmt,a[i].get!T,a);
                        return;
                    }
                }
                throw new DatabaseException("unknown type: " ~ a[i].type.toString);
            }
        }


        static auto create(void[] con, string sql) {
            return construct!Statement(alloc, toTypedPtr!Connection(con), sql);
        }

        static void destroy(void[] stmt) {destruct!Statement(alloc, stmt);}
        static void prepare(void[] stmt) {toTypedPtr!Statement(stmt).prepare();}
        static void query(void[] stmt) {toTypedPtr!Statement(stmt).query();}


        static void callVariadic(alias F,S,A...) (ref S s, A a) {
            //initial args come last in this call
            switch (s.length) {
                case 0: break;
                case 1: F(a,s[0]); break;
                case 2: F(a,s[0],s[1]); break;
                case 3: F(a,s[0],s[1],s[2]); break;
                case 4: F(a,s[0],s[1],s[2],s[3]); break;
                case 5: F(a,s[0],s[1],s[2],s[3],s[4]); break;
                default: throw new Exception("too many args");
            }
        }

        static void variadicQuery(void[] stmt, ref BindArgs a) {
            auto s = toTypedPtr!Statement(stmt);
            //callVariadic!constructQuery(a, s);

            //void F(A...) (A a) {stmt.query(a);}

            switch (a.length) {
                case 0: break;
                case 1: constructQuery(s,a[0]); break;
                case 2: constructQuery(s,a[0],a[1]); break;
                case 3: constructQuery(s,a[0],a[1],a[2]); break;
                default: throw new DatabaseException("too many args");
            }

        }

        static StmtVTable vtable = {
            &create,
            &destroy,
            &prepare,
            &query,
            &variadicQuery,
        };
    }

    //static struct QueryGen(Driver, T...)  // but you don't have driver and args at same time


    struct Database {
        private static Array!DriverInfo drivers;
        private string URI;

        private DriverInfo* driver;
        private void[] db;

        alias queryVariableType = QueryVariableType.Dollar;

        static void register(DB) (string name) {
            alias Driver = DB.Driver;
            DriverInfo driver;
            driver.name = name;
            driver.dbVtable = DBGen!Driver.vtable;
            driver.conVtable = ConGen!Driver.vtable;
            driver.stmtVtable = StmtGen!Driver.vtable;

            drivers ~= driver;

            info(
                    "poly register: ",
                    "name: ", name, ", "
                    "type: ", typeid(DB),
                    "index: ", drivers.length);
        }

        void setDatabase(string name) {
            driver = findDatabase(name);
            db = driver.dbVtable.create(URI);
        }

        bool isDatabaseSet() {return driver && db;}

        //Allocator allocator;

        const(Feature[]) features() {
            // strange feature behavior to get it working
            if (driver) return driver.dbVtable.features(db);
            static const FeatureArray f = [
                //Feature.InputBinding,
                //Feature.DateBinding,
                //Feature.ConnectionPool,
                //Feature.OutputArrayBinding,
                ];
            return f;
        }

        this(string URI_) {
            //allocator = Allocator();
            URI = URI_;
        }

        ~this() {
            if (isDatabaseSet) {
                if (!db.ptr) throw new DatabaseException("db not set");
                driver.dbVtable.destroy(db);
            }
        }

        private static DriverInfo* findDatabase(string name) {
            //import std.algorithm;
            //import std.range.primitives: empty;
            foreach(ref d; drivers) {
                if (d.name == name) return &d;
            }
            throw new DatabaseException("can't find database with name: " ~ name);
        }
    }

    struct Connection {
        Database* database;
        Source source;
        void[] con;

        auto driver() {return database.driver;}
        auto db() {return database.db;}

        this(Database* database_, Source source_) {
            database = database_;
            source = source_;
            if (!database.isDatabaseSet) throw new DatabaseException("no database set");
            con = driver.conVtable.create(db, source);
        }

        ~this() {
            driver.conVtable.destroy(con);
        }
    }

    struct Describe {
    }

    struct Bind {
        ValueType type;
    }

    struct Statement {
        Connection *connection;
        string sql;
        Allocator *allocator;
        void[] stmt;

        auto driver() {return connection.driver;}
        auto con() {return connection.con;}

        this(Connection* connection_, string sql_) {
            connection = connection_;
            sql = sql_;
            //allocator = &con.db.allocator;
            stmt = driver.stmtVtable.create(con, sql);
        }

        ~this() {
            driver.stmtVtable.destroy(stmt);
        }

        void exec() {
            //check("SQLExecDirect", SQLExecDirect(data_.stmt,cast(SQLCHAR*) toStringz(data_.sql), SQL_NTS));
        }

        void prepare() {
            driver.stmtVtable.prepare(stmt);
        }

        void query() {
            driver.stmtVtable.query(stmt);
        }

        void query(A...) (ref A args) {
            import std.range;
            //auto a = BindArgs(only(args));
            auto a = BindArgs();
            a.reserve(args.length);
            foreach(arg; args) a ~= Variant(arg);
            driver.stmtVtable.variadicQuery(stmt, a);
        }

        bool hasRows() {return true;} // fix


        void bind(int n, int value) {
        }

        void bind(int n, const char[] value){
        }

        void bind(int n, Date d) {
        }

        void reset() {}
    }

    struct Result {
        Statement *stmt;
        Allocator *allocator;
        Array!Bind bind;

        this(Statement* stmt_, int rowArraySize_) {
            stmt = stmt_;
            //allocator = &stmt.con.db.allocator;

            //build_describe();
            //build_bind();
        }

        ~this() {
            //foreach(ref b; bind) {
            //}
        }

        void build_describe() {
        }

        void build_bind() {
        }

        int columns() {return 0;}

        //bool hasResult() {return columns != 0;}
        bool hasResult() {return 0;}

        int fetch() {
            return 0;
        }

        auto name(size_t idx) {
            return "-name-";
        }

        auto get(X:string)(Cell* cell) {
            return "abc";
        }

        auto get(X:int)(Cell* cell) {
            return 0;
        }

        auto get(X:Date)(Cell* cell) {
            return Date(2016,1,1); // fix
        }

    }

}

