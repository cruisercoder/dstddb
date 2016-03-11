module std.database.reference.database;

import std.string;

import std.database.common;
import std.database.exception;
import std.container.array;
import std.experimental.logger;

public import std.database.allocator;

import std.stdio;
import std.typecons;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

// this function is module specific because it allows 
// a default template to be specified
auto createDatabase()(string defaultUrl=null) {
    return Database!DefaultPolicy(defaultUrl);  
}

//one for specfic type
auto createDatabase(T)(string defaultUrl=null) {
    return Database!T(defaultUrl);  
}

// these functions can be moved into util once a solution to forward bug is found

auto connection(T)(Database!T db, string source) {
    return Connection!T(db,source);
}

auto statement(T) (Connection!T con, string sql) {
    return Statement!T(con, sql);
}

auto statement(T, X...) (Connection!T con, string sql, X args) {
    return Statement!T(con, sql, args);
}

auto result(T)(Statement!T stmt) {
    return Result!T(stmt);  
}

struct Database(T) {
    alias Allocator = T.Allocator;

    static const auto queryVariableType = QueryVariableType.QuestionMark;


    private struct Payload {
        string defaultURI;
        Allocator allocator;

        this(string defaultURI_) {
            info("opening database resource");
            defaultURI = defaultURI_;
            allocator = Allocator();
        }

        ~this() {
            info("closing database resource");
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


struct Connection(T) {
    alias Database = .Database!T;
    //alias Statement = .Statement!T;

    auto statement(string sql) {return Statement!T(this,sql);}
    auto statement(X...) (string sql, X args) {return Statement!T(this,sql,args);}
    auto query(string sql) {return statement(sql).query();}
    auto query(T...) (string sql, T args) {return statement(sql).query(args);}

    package this(Database db, string source) {
        data_ = Data(db,source);
    }

    private:

    struct Payload {
        Database db;
        string source;
        bool connected;

        this(Database db_, string source_) {
            db = db_;
            source = source_;
            connected = true;
        }

        ~this() {
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;
}

struct Statement(T) {
    alias Connection = .Connection!T;

    alias Result = .Result;
    //alias Range = Result.Range; // error Result.Payload no size yet for forward reference

    // temporary
    auto result() {return Result!T(this);}
    auto opSlice() {return result();}

    this(Connection con, string sql) {
        data_ = Data(con,sql);
        //prepare();
        // must be able to detect binds in all DBs
        //if (!data_.binds) query();
    }

    this(T...) (Connection con, string sql, T args) {
        data_ = Data(con,sql);
        //prepare();
        //bindAll(args);
        //query();
    }

    //string sql() {return data_.sql;}
    //int binds() {return data_.binds;}

    void bind(int n, int value) {
    }

    void bind(int n, const char[] value){
    }

    private:

    struct Payload {
        Connection con;
        string sql;
        bool hasRows;
        int binds;

        this(Connection con_, string sql_) {
            con = con_;
            sql = sql_;
        }

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

    public:

    void exec() {}
    void prepare() {}

    auto query() {
        return result();
    }

    auto query(X...) (X args) {
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
    }
}

struct Result(T) {
    alias Statement = .Statement!T;
    alias ResultRange = .ResultRange!T;
    alias Range = .ResultRange;
    alias Row = .Row;

    this(Statement stmt) {
        data_ = Data(stmt);
    }

    auto opSlice() {return ResultRange(this);}

    bool start() {return true;}
    bool next() {return data_.next();}

    private:

    struct Payload {
        Statement stmt;

        this(Statement stmt_) {
            stmt = stmt_;
            next();
        }

        bool next() {
            return false;
        }

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

}

struct Value {
    auto as(T:int)() {
        return 0;
    }

    auto as(T:string)() {
        return "value";
    }

    auto chars() {return "value";}
}

struct ResultRange(T) {
    alias Result = .Result!T;
    alias Row = .Row!T;
    private Result result_;
    private bool ok_;

    this(Result result) {
        result_ = result;
        ok_ = result_.start();
    }

    bool empty() {return !ok_;}
    Row front() {return Row(&result_);}
    void popFront() {ok_ = result_.next();}
}


struct Row(T) {
    alias Result = .Result!T;
    alias Value = .Value;
    this(Result* result) { result_ = result;}
    Value opIndex(size_t idx) {return Value();}
    private Result* result_;

    int columns() {return 0;}
}

