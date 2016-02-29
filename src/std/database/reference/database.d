module std.database.reference.database;

import std.string;

public import std.database.exception;
import std.container.array;
import std.experimental.logger;

import std.stdio;
import std.typecons;

struct DefaultPolicy {}

// this function is module specific because it allows 
// a default template to be specified
auto createDatabase()(string defaultUrl=null) {
    return Database!int.create(defaultUrl);  
}

//one for specfic type
auto createDatabase(T)(string defaultUrl=null) {
    return Database!T.create(defaultUrl);  
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

    static Database create(string defaultURI) {
        //abc();
        return Database!T(defaultURI);
    }

    private struct Payload {
        string defaultURI;

        this(string defaultURI_) {
            writeln("opening database resource");
            defaultURI = defaultURI_;
        }

        ~this() {
            writeln("closing database resource");
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

    void execute(string sql) {

    }

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

    this(Connection con, string sql) {
        data_ = Data(con,sql);
        //prepare();
        // must be able to detect binds in all DBs
        //if (!data_.binds) execute();
    }

    this(T...) (Connection con, string sql, T args) {
        data_ = Data(con,sql);
        //prepare();
        //bindAll(args);
        //execute();
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

    void exec() {}
    void prepare() {}
    void execute() {}

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

    ResultRange range() {return ResultRange(this);}

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
    int get(T) () { return 0; }
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

