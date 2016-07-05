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
public import std.variant;

import std.range.primitives;

public import std.database.array;

/*
   require a specific minimum version of DMD (2.071)
   can't use yet because DMD is reporting wrong version

   import std.compiler;
   static assert(
   name != "Digital Mars D" ||
   (version_major == 2 && version_minor == 70));
 */

struct Time {
    this(uint h, uint m, uint s = 0, uint ms = 0) {
        hour = h;
        minute = m;
        second = s;
        msecond = ms;
    }

    uint hour;
    uint minute;
    uint second;
    uint msecond;

	string toString(){
		import std.string;
		import std.format;
		return format("%d:%d:%d.%d",hour,minute,second,msecond);
	}

	static Time formString(string str){
		import std.string;
		import std.array;
		import std.conv;
		int idx = cast(int)str.indexOf(".");
		string dt;
		uint msec = 0;
		if(idx > 0)
		{
			dt = str[0..idx];
			msec = to!uint(str[idx..$]);
		}
		else
		{
			dt = str;
		}
		string[] tm = dt.split(":");
		if(tm.length != 3)
			throw new Exception("erro string To Time : ", str);
		return Time(to!uint(tm[0]),to!uint(tm[1]),to!uint(tm[2]),msec);
	}
}

enum ValueType {
    Char,

    Short,
    Int,
    Long,

    Float,
    Double,

    String,

    Date,
    Time,
    DateTime,

    Raw
}
// improve
struct TypeInfo(T : char)
{
	static auto type() {
		return ValueType.Char;
	}
}

struct TypeInfo(T : short)
{
	static auto type() {
		return ValueType.Short;
	}
}

struct TypeInfo(T : int) {
    static auto type() {
        return ValueType.Int;
    }
}

struct TypeInfo(T : long) {
	static auto type() {
		return ValueType.Long;
	}
}

struct TypeInfo(T : float) {
	static auto type() {
		return ValueType.Float;
	}
}

struct TypeInfo(T : double) {
	static auto type() {
		return ValueType.Double;
	}
}

struct TypeInfo(T : string) {
    static auto type() {
        return ValueType.String;
    }
}

struct TypeInfo(T : Date) {
    static auto type() {
        return ValueType.Date;
    }
}

struct TypeInfo(T : Time) {
	static auto type() {
		return ValueType.Time;
	}
}

struct TypeInfo(T : DateTime) {
	static auto type() {
		return ValueType.DateTime;
	}
}

struct TypeInfo(T : ubyte[]) {
	static auto type() {
		return ValueType.Raw;
	}
}

/*struct TypeInfo(T : Variant) {
    static auto type() {
        return ValueType.Variant;
    }
}*/

enum Feature {
    InputBinding,
    DateBinding,
    ConnectionPool,
    OutputArrayBinding,
}

alias FeatureArray = Feature[];

struct BasicDatabase(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias Database = Driver.Database;
    alias Allocator = Policy.Allocator;
    alias Connection = BasicConnection!(Driver, Policy);
    alias Cell = BasicCell!(Driver, Policy);
    alias Pool = .Pool!(Driver.Connection);
    alias ScopedResource = .ScopedResource!Pool;

    alias queryVariableType = Database.queryVariableType;

    static auto create() {
        return BasicDatabase(null);
    }

    static auto create(string url) {
        return BasicDatabase(url);
    }

    auto connection() {
        return Connection(this);
    }

    auto connection(string uri) {
        return Connection(this, uri);
    }

    auto statement(string sql) {
        return connection().statement(sql);
    }

    auto statement(X...)(string sql, X args) {
        return connection.statement(sql, args);
    }

    auto query(string sql) {
        return connection().query(sql);
    }

    auto query(T...)(string sql, T args) {
        return statement(sql).query(args);
    }

    //static bool hasFeature(Feature feature);
    // go with non-static hasFeature for now to accomidate poly driver

    bool hasFeature(Feature feature) {
        return hasFeature(data_.database, feature);
    }

    auto ref driverDatabase() {
        return data_.database;
    }

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
        static void register(DB)(string name = "") {
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
        import std.range.primitives : empty;

        //auto r = find(Database.features, feature);
        auto r = find(db.features, feature);
        return !r.empty;
    }
}

struct BasicConnection(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias DriverConnection = Driver.Connection;
    alias Statement = BasicStatement!(Driver, Policy);
    alias Database = BasicDatabase!(Driver, Policy);
    alias Pool = Database.Pool;
    alias ScopedResource = Database.ScopedResource;
    alias DatabaseImpl = Driver.Database;

    auto statement(string sql) {
        return Statement(this, sql);
    }

    auto statement(X...)(string sql, X args) {
        return Statement(this, sql, args);
    }

    auto query(string sql) {
        return statement(sql).query();
    }

    auto query(T...)(string sql, T args) {
        return statement(sql).query(args);
    }

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

    package this(Database db) {
        this(db, "");
    }

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
        auto socket() {
            return driverConnection.socket;
        }
    }

    // handle()
    // be carful about Connection going out of scope or being destructed
    // while a handle is in use  (Use a connection variable to extend scope)

    static if (hasMember!(Database, "handle")) {
        auto handle() {
            return driverConnection.handle;
        }
    }

    /*
       this(Database db, ref Allocator allocator, string uri="") {
//db_ = db;
data_ = Data(&db.data_.refCountedPayload(),uri);
}
     */

}

struct BasicStatement(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias DriverStatement = Driver.Statement;
    alias Connection = BasicConnection!(Driver, Policy);
    alias Result = BasicResult!(Driver, Policy);
    alias RowSet = BasicRowSet!(Driver, Policy);
    alias ColumnSet = BasicColumnSet!(Driver, Policy);
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
        data_ = Data(con_.driverConnection, sql);
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

    string sql() {
        return data_.sql;
    }
    //int binds() {return data_.binds;}

    void bind(int n, int value) {
        data_.bind(n, value);
    }

    void bind(int n, const char[] value) {
        data_.bind(n, value);
    }

    auto query() {
        data_.query();
        state = State.Executed;
        return this;
    }

    auto query(X...)(X args) {
        data_.query(args);
        state = State.Executed;
        return this;
    }

    auto into(A...)(ref A args) {
        if (state != State.Executed)
            throw new DatabaseException("not executed");
        rows.into(args);
        return this;
    }

    bool hasRows() {
        return data_.hasRows;
    }

    // rows()
    // accessor for single rowSet returned
    // length should be the number of rows
    // alternate name: rowSet, table

    auto rows() {
        if (state != State.Executed)
            query();
        return RowSet(Result(this, rowArraySize_));
    }

    auto columns() {
        if (state != State.Executed)
            query();
        return ColumnSet(Result(this, rowArraySize_));
    }

    // results()
    // returns range for one or more things returned by a query
    auto results() {
        if (state != State.Executed)
            throw new DatabaseException("not executed");
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

    void reset() {
        data_.reset();
    } //SQLCloseCursor
}

struct BasicResult(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias ResultImpl = Driver.Result;
    alias Statement = BasicStatement!(Driver, Policy);
    alias RowSet = BasicRowSet!(Driver, Policy);
    //alias Allocator = Driver.Policy.Allocator;
    alias Bind = Driver.Bind;
    //alias Row = .Row;

    this(Statement stmt, int rowArraySize = 1) {
        stmt_ = stmt;
        rowArraySize_ = rowArraySize;
        data_ = Data(&stmt.data_.refCountedPayload(), rowArraySize_);
        if (!stmt_.hasRows)
            throw new DatabaseException("not a result query");
        rowsFetched_ = data_.fetch();
    }

    // disallow slicing to avoid confusion: must use rows/results
    //auto opSlice() {return ResultRange(this);}

package:
    int rowsFetched() {
        return rowsFetched_;
    }

    bool next() {
        if (++rowIdx_ == rowsFetched_) {
            rowsFetched_ = data_.fetch();
            if (!rowsFetched_)
                return false;
            rowIdx_ = 0;
        }
        return true;
    }

    auto ref result() {
        return data_.refCountedPayload();
    }

private:
    Statement stmt_;
    int rowArraySize_; //maybe move into RC
    int rowIdx_;
    int rowsFetched_;

    alias RefCounted!(ResultImpl, RefCountedAutoInitialize.no) Data;
    Data data_;

    // these need to move
    int width() {
        return data_.columns;
    }

    private size_t index(string name) {
        import std.uni;

        // slow name lookup, all case insensitive for now
        for (int i = 0; i != width; i++) {
            if (sicmp(data_.name(i), name) == 0)
                return i;
        }
        throw new DatabaseException("column name not found:" ~ name);
    }
}

struct BasicColumnSet(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver, Policy);
    alias Column = BasicColumn!(Driver, Policy);
    private Result result_;

    this(Result result) {
        result_ = result;
    }

    int width() {
        return result_.data_.columns;
    }

    struct Range {
        private Result result_;
        int idx;
        this(Result result) {
            result_ = result;
        }

        bool empty() {
            return idx == result_.data_.columns;
        }

        auto front() {
            return Column(result_, idx);
        }

        void popFront() {
            ++idx;
        }
    }

    auto opSlice() {
        return Range(result_);
    }
}

struct BasicColumn(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver, Policy);
    private Result result_;
    private size_t idx_;

    this(Result result, size_t idx) {
        result_ = result;
        idx_ = idx;
    }

    auto idx() {
        return idx_;
    }

    auto name() {
        return result_.data_.name(idx_);
    }

}

struct BasicRowSet(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver, Policy);
    alias Row = BasicRow!(Driver, Policy);
    alias ColumnSet = BasicColumnSet!(Driver, Policy);

    void rowSetTag();

    private Result result_;

    this(Result result) {
        result_ = result;
    }

    int width() {
        return result_.data_.columns;
    }

    // length will be for the number of rows (if defined)
    int length() {
        throw new Exception("not a completed/detached rowSet");
    }

    auto into(A...)(ref A args) {
        if (!result_.rowsFetched())
            throw new DatabaseException("no data");
        auto row = front();
        foreach (i, ref a; args) {
            alias T = A[i];
            static if (is(T == string)) {
                a = row[i].as!T.dup;
            }
            else {
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
    auto into(R)(R range) if (hasMember!(R, "put")) {
        // Row should have range
        // needs lots of work
        auto row = Row(this);
        for (int i = 0; i != width; i++) {
            auto f = row[i];
            switch (f.type) {
            case ValueType.Int:
                put(range, f.as!int);
                break;
            case ValueType.String:
                put(range, f.as!string);
                break;
                //case ValueType.Date: put(range, f.as!Date); break;
            default:
                throw new DatabaseException("switch error");
            }
        }
    }

    auto columns() {
        return ColumnSet(result_);
    }

    bool empty() {
        return result_.rowsFetched_ == 0;
    }

    auto front() {
        return Row(this);
    }

    void popFront() {
        result_.next();
    }
}

struct BasicRow(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver, Policy);
    alias RowSet = BasicRowSet!(Driver, Policy);
    alias Cell = BasicCell!(Driver, Policy);
    alias Value = BasicValue!(Driver, Policy);
    alias Column = BasicColumn!(Driver, Policy);

    private RowSet rows_;

    this(RowSet rows) {
        rows_ = rows;
    }

    int width() {
        return rows_.result_.data_.columns;
    }

    auto into(A...)(ref A args) {
        rows_.into(args);
        return this;
    }

    auto opIndex(Column column) {
        return opIndex(column.idx);
    }

    // experimental
    auto opDispatch(string s)() {
        return opIndex(rows_.result_.index(s));
    }

    Value opIndex(size_t idx) {
        auto result = &rows_.result_;
        // needs work
        // sending a ptr to cell instead of reference (dangerous)
        return Value(Cell(result, &result.data_.bind[idx], idx));
    }
}

struct BasicValue(D, P) {
    alias Driver = D;
    alias Policy = P;
    //alias Result = Driver.Result;
    alias Result = BasicResult!(Driver, Policy);
    alias Cell = BasicCell!(Driver, Policy);
    alias Bind = Driver.Bind;
    private Cell cell_;
    private Variant data_;
    alias Converter = .Converter!(Driver, Policy);

    this(Cell cell) {
        cell_ = cell;
        data_ = resultPtr.getValue(&cell_);
    }

    private auto resultPtr() {
        auto r = cell_.result_;
        return &(r.result()); // last parens matter here (something about delegate)
    }

    Variant value() {
        return data_;
    }

    ubyte[] rawData() {
        return resultPtr.rawData(&cell_);
    }

    auto type() {
        return cell_.bind.type;
    }

    auto as(T)() {
		return Converter.convert!T(cell_,this);
    }

    auto as(T : Variant)() {
        return data_;
    } //Converter.convert!T(resultPtr, cell_);}

    bool isNull() {
        return resultPtr.isNull(&cell_);
    } //fix

    string name() {
        return resultPtr.name(cell_.idx_);
    }

    auto get(T)() {
        if (data_.convertsTo!T())
            return Nullable!T(as!T);
        else
            return Nullable!T;
    }

    // not sure if this does anything
    //const(char)[] chars() {return as!string;}

    string toString() {
        return data_.toString();
    }

}

struct BasicCell(D, P) {
    alias Driver = D;
    alias Policy = P;
    alias Result = BasicResult!(Driver, Policy);
    alias Bind = Driver.Bind;
    alias Value = BasicValue!(Driver, Policy);
    private Bind* bind_;
    private int rowIdx_;
    private size_t idx_;
    private Result* result_;

    this(Result* r, Bind* b, size_t idx) {
        bind_ = b;
        result_ = r;
        rowIdx_ = r.rowIdx_;
        idx_ = idx;
    }

    private auto resultPtr() {
        return &result_.result(); // last parens matter here (something about delegate)
    }

    auto value() {
        return Value(this);
    }

    auto bind() {
        return bind_;
    }

    auto rowIdx() {
        return rowIdx_;
    }
}

/*
struct EfficientValue(T) {
	alias Driver = T.Driver;
	alias Bind = Driver.Bind;
	private Bind* bind_;
	alias Converter = .Converter!Driver;

	private Variant data_;
	
	this(Bind* bind) {bind_ = bind;}
	
	auto as(T:int)() {return Converter.convertDirect!T(bind_);}
	auto as(T:string)() {return Converter.convertDirect!T(bind_);}
	auto as(T:Date)() {return Converter.convertDirect!T(bind_);}
	auto as(T:Variant)() {return Converter.convertDirect!T(bind_);}
	
}*/

import std.traits;
//Converter now is not used, but if del it ,it will build error.
struct Converter(D,P) {
	alias Driver = D;
	alias Policy = P;
	//alias Result = Driver.Result;
	alias Bind = Driver.Bind;
	alias Cell = BasicCell!(Driver,Policy);
	alias Value = Cell.Value;

	static Y convert(Y)(ref Cell cell,ref Value value) {
		ValueType x = cell.bind.type, y = TypeInfo!Y.type;
		if (x == y) return value.data_.get!Y(); 
		auto e = lookup(x,y);
		if (!e) conversionError(x,y);
		Y val;
		e.convert(&(value.data_),&cell, &val);
		return val;
	}

	private:

	struct Elem {
		ValueType from,to;
		void function(Variant *,void *,void*) convert;
	}

	// only cross converters, todo: all converters
	static Elem[74] converters = [
		//to string
		{from: ValueType.Char, 		to: ValueType.String, &generate!(char,string).convert},
		{from: ValueType.Short, 	to: ValueType.String, &generate!(short,string).convert},
		{from: ValueType.Int, 		to: ValueType.String, &generate!(int,string).convert},
		{from: ValueType.Long, 		to: ValueType.String, &generate!(int,string).convert},
		{from: ValueType.Float, 	to: ValueType.String, &generate!(float,string).convert},
		{from: ValueType.Double, 	to: ValueType.String, &generate!(double,string).convert},
		{from: ValueType.Raw, 		to: ValueType.String, &generate!(ubyte[],string).convert},
		{from: ValueType.Time, 		to: ValueType.String, &generate!(Time,string).convert},
		{from: ValueType.Date, 		to: ValueType.String, &generate!(Date,string).convert},
		{from: ValueType.DateTime, 	to: ValueType.String, &generate!(DateTime,string).convert},
		// string to other
		{from: ValueType.String, 	to: ValueType.Char, &generate!(string,char).convert},
		{from: ValueType.String, 	to: ValueType.Short, &generate!(string,short).convert},
		{from: ValueType.String, 	to: ValueType.Int, &generate!(string,int).convert},
		{from: ValueType.String, 	to: ValueType.Long, &generate!(string,long).convert},
		{from: ValueType.String, 	to: ValueType.Float, &generate!(string,float).convert},
		{from: ValueType.String, 	to: ValueType.Double, &generate!(string,double).convert},
		{from: ValueType.String, 	to: ValueType.Raw, &generate!(string,ubyte[]).convert},
		{from: ValueType.String, 	to: ValueType.Time, &generate!(string,Time).convert},
		{from: ValueType.String, 	to: ValueType.Date, &generate!(string,Date).convert},
		{from: ValueType.String, 	to: ValueType.DateTime, &generate!(string,DateTime).convert},
		// char to other
		{from: ValueType.Char, 	to: ValueType.Short, &generate!(char,short).convert},
		{from: ValueType.Char, 	to: ValueType.Int, &generate!(char,int).convert},
		{from: ValueType.Char, 	to: ValueType.Long, &generate!(char,long).convert},
		{from: ValueType.Char, 	to: ValueType.Float, &generate!(char,float).convert},
		{from: ValueType.Char, 	to: ValueType.Double, &generate!(char,double).convert},
		{from: ValueType.Char, 	to: ValueType.Raw, &generate!(char,ubyte[]).convert},
		//short to other
		{from: ValueType.Short, to: ValueType.Char, &generate!(short,char).convert},
		{from: ValueType.Short, to: ValueType.Int, &generate!(short,int).convert},
		{from: ValueType.Short, to: ValueType.Long, &generate!(short,long).convert},
		{from: ValueType.Short, to: ValueType.Float, &generate!(short,float).convert},
		{from: ValueType.Short, to: ValueType.Double, &generate!(short,double).convert},
		{from: ValueType.Short, to: ValueType.Raw, &generate!(short,ubyte[]).convert},
		// int to other
		{from: ValueType.Int, to: ValueType.Char, &generate!(int,char).convert},
		{from: ValueType.Int, to: ValueType.Short, &generate!(int,short).convert},
		{from: ValueType.Int, to: ValueType.Long, &generate!(int,long).convert},
		{from: ValueType.Int, to: ValueType.Float, &generate!(int,float).convert},
		{from: ValueType.Int, to: ValueType.Double, &generate!(int,double).convert},
		{from: ValueType.Int, to: ValueType.Raw, &generate!(int,ubyte[]).convert},
		// long to Other
		{from: ValueType.Long, to: ValueType.Char, &generate!(long,char).convert},
		{from: ValueType.Long, to: ValueType.Short, &generate!(long,short).convert},
		{from: ValueType.Long, to: ValueType.Int, &generate!(long,int).convert},
		{from: ValueType.Long, to: ValueType.Float, &generate!(long,float).convert},
		{from: ValueType.Long, to: ValueType.Double, &generate!(long,double).convert},
		{from: ValueType.Long, to: ValueType.Raw, &generate!(long,ubyte[]).convert},
		{from: ValueType.Long, to: ValueType.DateTime, &generate!(int,DateTime).convert},
		//double to Other
		{from: ValueType.Double, to: ValueType.Char, &generate!(double,char).convert},
		{from: ValueType.Double, to: ValueType.Short, &generate!(double,short).convert},
		{from: ValueType.Double, to: ValueType.Int, &generate!(double,int).convert},
		{from: ValueType.Double, to: ValueType.Float, &generate!(double,float).convert},
		{from: ValueType.Double, to: ValueType.Long, &generate!(double,long).convert},
		{from: ValueType.Double, to: ValueType.Raw, &generate!(double,ubyte[]).convert},
		//float to Other
		{from: ValueType.Float, to: ValueType.Char, &generate!(float,char).convert},
		{from: ValueType.Float, to: ValueType.Short, &generate!(float,short).convert},
		{from: ValueType.Float, to: ValueType.Int, &generate!(float,int).convert},
		{from: ValueType.Float, to: ValueType.Double, &generate!(float,double).convert},
		{from: ValueType.Float, to: ValueType.Long, &generate!(float,long).convert},
		{from: ValueType.Float, to: ValueType.Raw, &generate!(float,ubyte[]).convert},
		//raw to other
		{from: ValueType.Raw, 	to: ValueType.Char, &generate!(ubyte[],char).convert},
		{from: ValueType.Raw, 	to: ValueType.Short, &generate!(ubyte[],short).convert},
		{from: ValueType.Raw, 	to: ValueType.Int, &generate!(ubyte[],int).convert},
		{from: ValueType.Raw, 	to: ValueType.Long, &generate!(ubyte[],long).convert},
		{from: ValueType.Raw, 	to: ValueType.Float, &generate!(ubyte[],float).convert},
		{from: ValueType.Raw, 	to: ValueType.Double, &generate!(ubyte[],double).convert},
		{from: ValueType.Raw, 	to: ValueType.Time, &generate!(ubyte[],Time).convert},
		{from: ValueType.Raw, 	to: ValueType.Date, &generate!(ubyte[],Date).convert},
		{from: ValueType.Raw, 	to: ValueType.DateTime, &generate!(ubyte[],DateTime).convert},
		//date to datetime
		{from: ValueType.Date, 	to: ValueType.DateTime, &generate!(Date,DateTime).convert},
		{from: ValueType.Date, 	to: ValueType.Raw, &generate!(Date,ubyte[]).convert},
		{from: ValueType.Time, 	to: ValueType.Raw, &generate!(Time,ubyte[]).convert},
		{from: ValueType.Time, 	to: ValueType.DateTime, &generate!(Time,DateTime).convert},
		// datetime to other
		{from: ValueType.DateTime, 	to: ValueType.Date, &generate!(DateTime,Date).convert},
		{from: ValueType.DateTime, 	to: ValueType.Time, &generate!(DateTime,Time).convert},
		{from: ValueType.DateTime, 	to: ValueType.Long, &generate!(DateTime,long).convert},
		{from: ValueType.DateTime, 	to: ValueType.Raw, &generate!(DateTime,ubyte[]).convert}
	];

	static Elem* lookup(ValueType x, ValueType y) {
	// rework into efficient array lookup
		foreach(ref i; converters) {
			if (i.from == x && i.to == y) return &i;
		}
		return null;
	}

	struct generate(X,Y) {
		static void convert(Variant * v_,void *x_, void *y_) {
			import std.conv;
			Cell* cell = cast(Cell*) x_;// why this must be have?
			*cast(Y*) y_ = to!Y(v_.get!X());
		}
	}

	struct generate(X : DateTime,Y : Time) {
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			DateTime dt = v_.get!X();
			*cast(Y*) y_ = Time(dt.hour, dt.minute, dt.second);
		} 
	}

	struct generate(X : DateTime,Y : long) {
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			DateTime dt = v_.get!X();
			*cast(Y*) y_ = SysTime(dt).toUnixTime() ;
		} 
	}

	struct generate(X : DateTime,Y : Date) {
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			DateTime dt = v_.get!X();
			*cast(Y*) y_ = dt.date;
		} 
	}

	struct generate(X : string,Y : Date) {
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			Date dt;
			dt.fromISOExtString(v_.get!X());
			*cast(Y*) y_  = dt;
		}
	}

	struct generate(X : string,Y : Time) {
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			*cast(Y*) y_ = Time.formString(v_.get!X());
		}
	}

	struct generate(X,Y : DateTime)
	{
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			static if(is (X == ubyte[]))
			{
				ubyte[] dt = v_.get!X();
				if(dt.length < Y.sizeof)
					throw new Exception("Raw Data Length is to smail!");
				auto data = dt[0..Y.sizeof];
				auto tm = cast(Y *) data.ptr;
				*cast(Y*) y_ = *tm;
			}
			else static if(is(X == string))
			{
				DateTime dt;
				dt.fromISOExtString(v_.get!X());
				*cast(Y*) y_  = dt;
			}
			else static if (is(X == long))
			{
					*cast(Y*) y_  = cast(DateTime)SysTime.fromUnixTime(v_.get!X());
			}
			else
			{
				string msg = "unsupported conversion from: " ~ X.stringof ~ " to " ~ Y.stringof;
				throw new DatabaseException(msg);
			}
		}
	}

	struct generate(X : char, Y)
	{
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			static if(is (Y == ubyte[]))
			{
				char a = v_.get!X();
				ubyte[] dt = new ubyte[1];
				dt[0] = cast(ubyte)a;
				*cast(Y*) y_ = dt;
			}
			else static if(is(Y == string))
			{
				string a;
				a ~=  v_.get!X();
				*cast(Y*) y_  = a;
			}
			else static if(isNumeric!Y)
			{
				*cast(Y*) y_  = v_.get!X();
			}
			else
			{
				string msg = "unsupported conversion from: " ~ X.stringof ~ " to " ~ Y.stringof;
				throw new DatabaseException(msg);
			}
		}
	}

	struct generate(X ,  Y : char)
	{
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			static if(is (X == ubyte[]))
			{
				ubyte[] dt = v_.get!X();
				*cast(Y*) y_ = cast(char)dt[0];
			}
			else static if(is(X == string))
			{
				string a =  v_.get!X();
				*cast(Y*) y_  = a[0];
			}
			else static if(isNumeric!Y)
			{
				*cast(Y*) y_  = cast(char)v_.get!X();
			}
			else
			{
				string msg = "unsupported conversion from: " ~ X.stringof ~ " to " ~ Y.stringof;
				throw new DatabaseException(msg);
			}
		}
	}

	struct generate(X : ubyte[], Y) if(!(is(Y == char) || is(Y == DateTime)))
	{
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			ubyte[] a =  v_.get!X();
			static if(is(X == string))
			{
				*cast(Y*) y_  = cast(string)a;
			}
			else 
			{
				if(a.length < Y.sizeof)
					throw new Exception("Raw Data Length is to smail!");
				auto data = a[0..Y.sizeof];
				auto tm = cast(Y *) data.ptr;
				*cast(Y*) y_ = *tm;
			}
		}
	}

	struct generate(X , Y : ubyte[]) if(!is(X == char))
	{
		static void convert(Variant * v_,void *x_, void *y_) {
			Cell* cell = cast(Cell*) x_;// why this must be have?
			static if(is(X == string))
			{
				string a =  v_.get!X();
				*cast(Y*) y_  = cast(ubyte[])a;
			}
			else 
			{
				ubyte[] data = new ubyte[X.sizeof];
				auto dt =  v_.get!X();
				ubyte * ptr = cast(ubyte *) &dt;
				data[] = ptr[0..X.sizeof];
				*cast(Y*) y_ = data;
			}
		}
	}



	static void conversionError(ValueType x, ValueType y) {
		import std.conv;
		string msg;
		msg ~= "unsupported conversion from: " ~ to!string(x) ~ " to " ~ to!string(y);
		throw new DatabaseException(msg);
	}
} 