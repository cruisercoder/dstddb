module std.database.front;
import std.experimental.logger;
import std.database.exception;
import std.datetime;

import std.typecons;
import std.database.common;
import std.database.pool;
import std.database.resolver;
import std.database.source;

import std.database.allocator;
import std.traits;
import std.container.array;
import std.variant;

import std.range.primitives;
import std.database.option;

public import std.database.array;

/*
   require a specific minimum version of DMD (2.071)
   can't use yet because DMD is reporting wrong version

   import std.compiler;
   static assert(
   name != "Digital Mars D" ||
   (version_major == 2 && version_minor == 70));
 */


enum ValueType {
    Int,
    String,
    Date,
    Variant,
}

// improve
struct TypeInfo(T:int) {static auto type() {return ValueType.Int;}}
struct TypeInfo(T:string) {static auto type() {return ValueType.String;}}
struct TypeInfo(T:Date) {static auto type() {return ValueType.Date;}}
struct TypeInfo(T:Variant) {static auto type() {return ValueType.Variant;}}


enum Feature {
    InputBinding,
    DateBinding,
    ConnectionPool,
    OutputArrayBinding,
}

alias FeatureArray = Feature[];

struct BasicDatabase(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias Database = Driver.Database;
    alias Allocator = Policy.Allocator;
    alias Connection = BasicConnection!(Driver,Policy);
    alias Cell = BasicCell!(Driver,Policy);
    alias Pool = .Pool!(Driver.Connection);
    alias ScopedResource = .ScopedResource!Pool;

    alias queryVariableType = Database.queryVariableType;

    static auto create() {return BasicDatabase(null);}
    static auto create(string url) {return BasicDatabase(url);}

    auto connection() {return Connection(this);}
    auto connection(string uri) {return Connection(this, uri);}

    auto statement(string sql) {return connection().statement(sql);}
    auto statement(X...) (string sql, X args) {return connection.statement(sql,args);}

    auto query(string sql) {return connection().query(sql);}
    auto query(T...) (string sql, T args) {return statement(sql).query(args);}

    //static bool hasFeature(Feature feature);
    // go with non-static hasFeature for now to accomidate poly driver

    bool hasFeature(Feature feature) {return hasFeature(data_.database, feature);}
auto ref driverDatabase() {return data_.database;}

    private struct Payload {
        string defaultURI;
        Database database;
        Pool pool;
        this(string defaultURI_) {
            defaultURI = defaultURI_;
            database = Database(defaultURI_);
            bool poolEnable = hasFeature(database, Feature.ConnectionPool);
            pool = Pool(poolEnable);
        }

    }

    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    // for poly
    static if (hasMember!(Database, "register")) {
        static void register(DB) (string name = "") {
            Database.register!DB(name); 
        }

        auto database(string name) {
            auto db = BasicDatabase(data_.defaultURI); 
            db.data_.database.setDatabase(name);
            return db;
        }
    }

    private static bool hasFeature(ref Database db, Feature feature) {
        import std.algorithm;
        import std.range.primitives: empty;
        //auto r = find(Database.features, feature);
        auto r = find(db.features, feature);
        return !r.empty;
    }
}

struct BasicConnection(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias DriverConnection = Driver.Connection;
    alias Statement = BasicStatement!(Driver,Policy);
    alias Database = BasicDatabase!(Driver,Policy);
    alias Pool = Database.Pool;
    alias ScopedResource = Database.ScopedResource;
    alias DatabaseImpl = Driver.Database;

    auto statement(string sql) {return Statement(this,sql);}
    auto statement(X...) (string sql, X args) {return Statement(this,sql,args);}
    auto query(string sql) {return statement(sql).query();}
    auto query(T...) (string sql, T args) {return statement(sql).query(args);}

    auto rowArraySize(int rows) {
        rowArraySize_ = rows;
        return this;
    }

    private alias RefCounted!(ScopedResource, RefCountedAutoInitialize.no) Data;

    //private Database db_; // problem (fix in 2.072)
    private Data data_;
    private Pool* pool_;
    string uri_;
    int rowArraySize_ = 1;

    package this(Database db) {this(db,"");}

    package this(Database db, string uri) {
        //db_ = db;
        uri_ = uri.length != 0 ? uri : db.data_.defaultURI;
        pool_ = &db.data_.pool;
        Source source = resolve(uri_);
        data_ = Data(*pool_, pool_.acquire(&db.driverDatabase(), source));
    }

    auto autoCommit(bool enable) {
        return this;
    }

    auto begin() {
        return this;
    }

    auto commit() {
        return this;
    }

    auto rollback() {
        return this;
    }

    private auto ref driverConnection() {
        return data_.resource.resource;
    }

    static if (hasMember!(Database, "socket")) {
        auto socket() {return driverConnection.socket;}
    }

    // handle()
    // be carful about Connection going out of scope or being destructed
    // while a handle is in use  (Use a connection variable to extend scope)

    static if (hasMember!(Database, "handle")) {
        auto handle() {return driverConnection.handle;}
    }

    /*
       this(Database db, ref Allocator allocator, string uri="") {
//db_ = db;
data_ = Data(&db.data_.refCountedPayload(),uri);
}
     */


}

struct BasicStatement(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias DriverStatement = Driver.Statement;
    alias Connection = BasicConnection!(Driver,Policy);
    alias Result = BasicResult!(Driver,Policy);
    alias RowSet = BasicRowSet!(Driver,Policy);
    alias ColumnSet = BasicColumnSet!(Driver,Policy);
    //alias Allocator = Policy.Allocator;
    alias ScopedResource = Connection.ScopedResource;

    /*
       auto result() {
       if (state != State.Executed) throw new DatabaseException("statement not executed");
       return Result(this);
       }
     */
    //auto opSlice() {return result();} //fix

    enum State {
        Undef,
        Prepared,
        Executed,
    }


    this(Connection con, string sql) {
        con_ = con;
        data_ = Data(con_.driverConnection,sql);
        rowArraySize_ = con.rowArraySize_;
        prepare();
    }

    /*
    // determine if needed and how to do
    this(X...) (Connection con, string sql, X args) {
    con_ = con;
    data_ = Data(&con.data_.refCountedPayload(),sql);
    prepare();
    bindAll(args);
    }
     */

    string sql() {return data_.sql;}
    //int binds() {return data_.binds;}

    void bind(int n, int value) {data_.bind(n, value);}
    void bind(int n, const char[] value){data_.bind(n,value);}

    auto query() {
        data_.query();
        state = State.Executed;
        return this;
    }

    auto query(X...) (X args) {
        data_.query(args);
        state = State.Executed;
        return this;
    }

    auto into(A...) (ref A args) {
        if (state != State.Executed) throw new DatabaseException("not executed");
        return this;
    }

    bool hasRows() {return data_.hasRows;}

    // rows()
    // accessor for single rowSet returned
    // length should be the number of rows
    // alternate name: rowSet, table

    auto rows() {
        if (state != State.Executed) query();
        return RowSet(Result(this, rowArraySize_));
    }

    auto columns() {
        if (state != State.Executed) query();
        return ColumnSet(Result(this, rowArraySize_));
    }

    // results()
    // returns range for one or more things returned by a query
    auto results() {
        if (state != State.Executed) throw new DatabaseException("not executed");
        return 0; // fill in
    }


    private:
    alias RefCounted!(DriverStatement, RefCountedAutoInitialize.no) Data;

    Data data_;
    Connection con_;
    State state;
    int rowArraySize_;

    void prepare() {
        data_.prepare();
        state = State.Prepared;
    }

    void reset() {data_.reset();} //SQLCloseCursor
}


struct BasicResult(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias ResultImpl = Driver.Result;
    alias Statement = BasicStatement!(Driver,Policy);
    alias RowSet = BasicRowSet!(Driver,Policy);
    //alias Allocator = Driver.Policy.Allocator;
    alias Bind = Driver.Bind;
    //alias Row = .Row;

    this(Statement stmt, int rowArraySize = 1) {
        stmt_ = stmt;
        rowArraySize_ = rowArraySize;
        data_ = Data(&stmt.data_.refCountedPayload(), rowArraySize_);
        if (!stmt_.hasRows) throw new DatabaseException("not a result query");
        rowsFetched_ = data_.fetch();
    }

    // disallow slicing to avoid confusion: must use rows/results
    //auto opSlice() {return ResultRange(this);}

package:
    int rowsFetched() {return rowsFetched_;}

    bool next() {
        if (++rowIdx_ == rowsFetched_) {
            rowsFetched_ = data_.fetch();
            if (!rowsFetched_) return false;
            rowIdx_ = 0;
        }
        return true;
    }

    auto ref result() {return data_.refCountedPayload();}

    private:
    Statement stmt_;
    int rowArraySize_; //maybe move into RC
    int rowIdx_;
    int rowsFetched_;

    alias RefCounted!(ResultImpl, RefCountedAutoInitialize.no) Data;
    Data data_;

    // these need to move
    int width() {return data_.columns;}

    private size_t index(string name) {
        import std.uni;
        // slow name lookup, all case insensitive for now
        for(int i=0; i!=width; i++) {
            if (sicmp(data_.name(i), name) == 0) return i;
        }
        throw new DatabaseException("column name not found:" ~ name);
    }
}

struct BasicColumnSet(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver,Policy);
    alias Column = BasicColumn!(Driver,Policy);
    private Result result_;

    this(Result result) {
        result_ = result;
    }

    int width() {return result_.data_.columns;}

    struct Range {
        private Result result_;
        int idx;
        this(Result result) {result_ = result;}
        bool empty() {return idx == result_.data_.columns;}
        auto front() {return Column(result_, idx);}
        void popFront() {++idx;}
    }

    auto opSlice() {return Range(result_);}
}


struct BasicColumn(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver,Policy);
    private Result result_;
    private size_t idx_;

    this(Result result, size_t idx) {
        result_ = result;
        idx_ = idx;
    }

    auto idx() {return idx_;}
    auto name() {return "abc";}

}


struct BasicRowSet(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver,Policy);
    alias Row = BasicRow!(Driver,Policy);
    alias ColumnSet = BasicColumnSet!(Driver,Policy);

    void rowSetTag();

    private Result result_;
    private bool ok_;

    this(Result result) {
        result_ = result;
        ok_ = result.rowsFetched != 0;
    }

    int width() {return result_.data_.columns;}

    // length will be for the number of rows (if defined)
    int length() {
        throw new Exception("not a completed/detached rowSet");
    }

    auto into(A...) (ref A args) {
        if (!result_.rowsFetched()) throw new DatabaseException("no data");

        auto row = front();
        foreach(i, ref a; args) {
            alias T = A[i];
            static if (is(T == string)) {
                a = row[i].as!T.dup;
            } else {
                a = row[i].as!T;
            }
        }

        // don't consume so we can do into at row level
        // range.popFront;
        //if (!range.empty) throw new DatabaseException("result has more than one row");

        return this;
    }


    // into for output range: experimental
    //if (isOutputRange!(R,E))
    auto into(R) (R range) 
        if (hasMember!(R, "put")) {
            // Row should have range
            // needs lots of work
            auto row = Row(this);
            for(int i=0; i != width; i++) {
                auto f = row[i];
                switch (f.type) {
                    case ValueType.Int: put(range, f.as!int); break;
                    case ValueType.String: put(range, f.as!string); break;
                                           //case ValueType.Date: put(range, f.as!Date); break;
                    default: throw new DatabaseException("switch error");
                }
            }
        }

    auto columns() {
        return ColumnSet(result_);
    }


    bool empty() {return !ok_;}
    auto front() {return Row(this);}
    void popFront() {ok_ = result_.next();}
}

struct BasicRow(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver,Policy);
    alias RowSet = BasicRowSet!(Driver,Policy);
    alias Cell = BasicCell!(Driver,Policy);
    alias Value = BasicValue!(Driver,Policy);
    alias Column = BasicColumn!(Driver,Policy);

    private RowSet rows_;

    this(RowSet rows) {
        rows_ = rows;
    }

    int width() {return rows_.result_.data_.columns;}

    auto into(A...) (ref A args) {
        rows_.into(args);
        return this;
    }

    auto opIndex(Column column) {return opIndex(column.idx);}

    // experimental
    auto opDispatch(string s)() {
        return opIndex(rows_.result_.index(s));
    }

    Value opIndex(size_t idx) {
        auto result = &rows_.result_;
        // needs work
        // sending a ptr to cell instead of reference (dangerous)
        auto cell = Cell(result, &result.data_.bind[idx], idx);
        return Value(result, cell);
    }
}


struct BasicValue(D,P) {
    alias Driver = D;
    alias Policy = P;
    //alias Result = Driver.Result;
    alias Result = BasicResult!(Driver,Policy);
    alias Cell = BasicCell!(Driver,Policy);
    alias Bind = Driver.Bind;
    private Result* result_;
    private Bind* bind_;
    private Cell cell_;
    alias Converter = .Converter!(Driver,Policy);

    this(Result* result, Cell cell) {
        result_ = result;
        //bind_ = bind;
        cell_ = cell;
    }

    private auto resultPtr() {
        return &result_.result(); // last parens matter here (something about delegate)
    }

    auto type() {return cell_.bind.type;}

    auto as(T:int)() {return Converter.convert!T(resultPtr, cell_);}
    auto as(T:string)() {return Converter.convert!T(resultPtr, cell_);}
    auto as(T:Date)() {return Converter.convert!T(resultPtr, cell_);}
    auto as(T:Nullable!T)() {return Nullable!T(as!T);}

    // should be nothrow?
    auto as(T:Variant)() {return Converter.convert!T(resultPtr, cell_);}

    bool isNull() {return false;} //fix

    string name() {return resultPtr.name(cell_.idx_);}

    auto get(T)() {return Nullable!T(as!T);}

    // experimental
    auto option(T)() {return Option!T(as!T);}

    // not sure if this does anything
    const(char)[] chars() {return as!string;}

    string toString() {return as!string;}

}


// extra stuff


struct EfficientValue(T) {
    alias Driver = T.Driver;
    alias Bind = Driver.Bind;
    private Bind* bind_;
    alias Converter = .Converter!Driver;

    this(Bind* bind) {bind_ = bind;}

    auto as(T:int)() {return Converter.convertDirect!T(bind_);}
    auto as(T:string)() {return Converter.convertDirect!T(bind_);}
    auto as(T:Date)() {return Converter.convertDirect!T(bind_);}
    auto as(T:Variant)() {return Converter.convertDirect!T(bind_);}

}


struct BasicCell(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver,Policy);
    alias Bind = Driver.Bind;
    private Bind* bind_;
    private int rowIdx_;
    private size_t idx_;

    this(Result *r, Bind *b, size_t idx) {
        bind_ = b;
        rowIdx_ = r.rowIdx_;
        idx_ = idx;
    }

    auto bind() {return bind_;}
    auto rowIdx() {return rowIdx_;}
}

struct Converter(D,P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = Driver.Result;
    alias Bind = Driver.Bind;
    alias Cell = BasicCell!(Driver,Policy);

    static Y convert(Y)(Result *r, ref Cell cell) {
        ValueType x = cell.bind.type, y = TypeInfo!Y.type;
        if (x == y) return r.get!Y(&cell); // temporary
        auto e = lookup(x,y);
        if (!e) conversionError(x,y);
        Y value;
        e.convert(r, &cell, &value);
        return value;
    }

    static Y convert(Y:Variant)(Result *r, ref Cell cell) {
        //return Y(123);
        ValueType x = cell.bind.type, y = ValueType.Variant;
        auto e = lookup(x,y);
        if (!e) conversionError(x,y);
        Y value;
        e.convert(r, &cell, &value);
        return value;
    }

    static Y convertDirect(Y)(Result *r, ref Cell cell) {
        assert(b.type == TypeInfo!Y.type);
        return r.get!Y(&cell);
    }

    private:

    struct Elem {
        ValueType from,to;
        void function(Result*,void*,void*) convert;
    }

    // only cross converters, todo: all converters
    static Elem[6] converters = [
    {from: ValueType.Int, to: ValueType.String, &generate!(int,string).convert},
    {from: ValueType.String, to: ValueType.Int, &generate!(string,int).convert},
    {from: ValueType.Date, to: ValueType.String, &generate!(Date,string).convert},
    // variants
    {from: ValueType.Int, to: ValueType.Variant, &generate!(int,Variant).convert},
    {from: ValueType.String, to: ValueType.Variant, &generate!(string,Variant).convert},
    {from: ValueType.Date, to: ValueType.Variant, &generate!(Date,Variant).convert},
    ];

    static Elem* lookup(ValueType x, ValueType y) {
        // rework into efficient array lookup
        foreach(ref i; converters) {
            if (i.from == x && i.to == y) return &i;
        }
        return null;
    }

    struct generate(X,Y) {
        static void convert(Result *r, void *x_, void *y_) {
            import std.conv;
            Cell* cell = cast(Cell*) x_;
            *cast(Y*) y_ = to!Y(r.get!X(cell));
        }
    }

    struct generate(X,Y:Variant) {
        static void convert(Result *r, void *x_, void *y_) {
            Cell* cell = cast(Cell*) x_;
            *cast(Y*) y_ = r.get!X(cell);
        }
    }

    static void conversionError(ValueType x, ValueType y) {
        import std.conv;
        string msg;
        msg ~= "unsupported conversion from: " ~ to!string(x) ~ " to " ~ to!string(y);
        throw new DatabaseException(msg);
    }

}

