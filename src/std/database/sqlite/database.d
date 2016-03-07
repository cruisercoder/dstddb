module std.database.sqlite.database;
import std.experimental.allocator.mallocator;

pragma(lib, "sqlite3");

import std.string;
import core.stdc.stdlib;
import std.typecons;
import etc.c.sqlite3;

import std.database.common;
import std.database.exception;
import std.database.resolver;
import std.database.allocator;
import std.database.pool;
import std.experimental.logger;

import std.stdio;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

auto createDatabase(T)(string defaultURI="") {
    return Database!T(defaultURI);  
}

auto connection(T)(Database!T db, string source = "") {
    return Connection!T(db,source);
}

auto result(T)(Statement!T stmt) {
    return Result!T(stmt);  
}


struct Database(T) {
    alias Allocator = T.Allocator;
    //alias Connection = .Connection;
    //alias Statement = .Statement;
    //alias PoolType = Pool!(Database!T,Connection!T);
    //PoolType pool_;

    static const auto queryVariableType = QueryVariableType.QuestionMark;

    this(string defaultSource) {
        data_ = Data(defaultSource);
        //pool_ = PoolType(this);
        //info("Database: defaultSource: ", data_.defaultSource);
    }

    // temporary helper functions
    //auto connection(string uri) {return pool_.get(uri);}
    auto connection(string url="") {return Connection!T(this, url);}
    //auto connection() {return pool_.get();}
    auto execute(string sql) {return this.connection().execute(sql);}


    bool bindable() {return true;}

    // properties? 

    string defaultSource() {
        version (assert) if (!data_.refCountedStore.isInitialized) throw new DatabaseException("uninitialized");
        return data_.defaultSource;
    }

    private:

    struct Payload {
        string defaultSource;

        this(string defaultSource_) {
            Allocator allocator;
            defaultSource = defaultSource_;
        }
        this(this) { assert(false); }
        void opAssign(Database.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;
}

struct Connection(T) {
    alias Statement = .Statement;

    // temporary helper functions
    auto statement(string sql) {return Statement!T(this,sql);}
    //auto statement(X...) (string sql, X args) {return Statement!T(this,sql,args);}
    auto execute(string sql) {return statement(sql).execute();}
    auto execute(T...) (string sql, T args) {return statement(sql).execute(args);}

    void error(string msg, int ret) {throw_error(data_.sq, msg, ret);}


    private struct Payload {
        Database!T* db;
        string path;
        sqlite3* sq;

        this(Database!T* db_, string source_) {
            db = db_;

            auto source = source_.length == 0 ? db.data_.defaultSource : source_;
            Source src = resolve(source);

            // map server to path while resolution rules are refined
            path = src.path.length != 0 ? src.path : src.server; // fix

            writeln("sqlite opening file: ", path);

            int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;
            int rc = sqlite3_open_v2(toStringz(path), &sq, flags, null);
            if (rc) {
                writeln("error: rc: ", rc, sqlite3_errmsg(sq));
            }
        }

        ~this() {
            writeln("sqlite closing ", path);
            if (sq) {
                int rc = sqlite3_close(sq);
                sq = null;
            }
        }

        this(this) { assert(false); }
        void opAssign(Connection!T.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    package this(Database!T db, string url) {
        data_ = Data(&db,url);
    }
}

struct Statement(T) {
    alias Allocator = T.Allocator;
    //alias Result = .Result!T;
    //alias Range = .ResultRange!T;

    enum State {
        Init,
        Execute,
    }

    // temporary
    auto result() {return Result!T(this);} // private?
    auto opSlice() {return result().opSlice();}

    void error(string msg, int ret) {data_.con.error(msg, ret);}

    this(Connection!T con, string sql) {
        data_ = Data(con,sql);
        prepare();
        // must be able to detect binds in all DBs
        //if (!data_.binds) execute();
    }

    /*
    this(X...) (Connection!T con, string sql, X args) {
        data_ = Data(con,sql);
        prepare();
        execute(args);
    }
    */

    string sql() {return data_.sql;}

    void bind(int col, int value){
        int rc = sqlite3_bind_int(
                data_.st, 
                col,
                value);
        if (rc != SQLITE_OK) {
            throw_error("sqlite3_bind_int");
        }
    }

    void bind(int col, const char[] value){
        if(value is null) {
            int rc = sqlite3_bind_null(data_.st, col);
            if (rc != SQLITE_OK) throw_error("bind1");
        } else {
            //cast(void*)-1);
            int rc = sqlite3_bind_text(
                    data_.st, 
                    col,
                    value.ptr,
                    cast(int) value.length,
                    null);
            if (rc != SQLITE_OK) {
                writeln(rc);
                throw_error("bind2");
            }
        }
    }

    int binds() {return sqlite3_bind_parameter_count(data_.st);}

    auto execute() {
        //if (data_.state == State.Execute) throw new DatabaseException("already executed"); // restore
        if (data_.state == State.Execute) return result();
        data_.state = State.Execute;
        int status = sqlite3_step(data_.st);
        info("sqlite3_step: status: ", status);
        if (status == SQLITE_ROW) {
            data_.hasRows = true;
        } else if (status == SQLITE_DONE) {
            reset();
        } else throw new DatabaseException("step error");
        return result();
    }

    auto execute(T...) (T args) {
        int col;
        foreach (arg; args) {
            bind(++col, arg);
        }
        return execute();
    }

    bool hasRows() {
        return data_.hasRows;
    }

    private:

    struct Payload {
        Connection!T con;
        string sql;
        State state;
        sqlite3* sq;
        sqlite3_stmt *st;
        bool hasRows;
        int binds;

        this(Connection!T con_, string sql_) {
            con = con_;
            sql = sql_;
            state = State.Init;
            sq = con.data_.sq;
        }

        ~this() {
            //writeln("sqlite statement closing ", filename_);
            if (st) {
                int res = sqlite3_finalize(st);
                st = null;
            }
        }

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;


    void prepare() {
        if (!data_.st) { 
            int res = sqlite3_prepare_v2(
                    data_.sq, 
                    toStringz(data_.sql), 
                    cast(int) data_.sql.length + 1, 
                    &data_.st, 
                    null);
            if (res != SQLITE_OK) error("prepare", res);
            data_.binds = sqlite3_bind_parameter_count(data_.st);
        }
    }

    void reset() {
        int status = sqlite3_reset(data_.st);
        if (status != SQLITE_OK) throw new DatabaseException("sqlite3_reset error");
    }

}


struct Result(T) {
    //alias ResultRange = .ResultRange!T;
    //alias Row = .Row!T;

    private struct Payload {
        private Statement!T stmt_;
        private sqlite3_stmt *st_;
        int columns;
        int status_;

        this(Statement!T stmt) {
            stmt_ = stmt;
            st_ = stmt_.data_.st;
            columns = sqlite3_column_count(st_);
        }

        //~this() {}

        this(this) { assert(false); }
        void opAssign(Statement!T.Payload rhs) { assert(false); }

        bool next() {
            status_ = sqlite3_step(st_);
            if (status_ == SQLITE_ROW) return true;
            if (status_ == SQLITE_DONE) {
                stmt_.reset();
                return false;
            }
            //throw new DatabaseException("sqlite3_step error: status: " ~ to!string(status_));
            throw new DatabaseException("sqlite3_step error: status: ");
        }

    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    int columns() {return data_.columns;}

    this(Statement!T stmt) {
        data_ = Data(stmt);
    }

    auto opSlice() {return ResultRange!T(this);}

    public bool start() {return data_.stmt_.hasRows();}
    public bool next() {return data_.next();}

}


struct Value(T) {
    //alias Result = .Result!T;

    private Result!T* result_;
    private ulong idx_;

    public this(Result!T* result, ulong idx) {
        result_ = result;
        idx_ = idx;
    }

    auto as(T:int)() {
        // bounds check or covered?
        return sqlite3_column_int(result_.data_.st_, cast(int) idx_);
    }

    auto as(T:string)() {
        import core.stdc.string: strlen;
        auto ptr = cast(immutable char*) sqlite3_column_text(result_.data_.st_, cast(int) idx_);
        return cast(string) ptr[0..strlen(ptr)]; // fix with length
    }

    auto chars() {
        import core.stdc.string: strlen;
        auto data = sqlite3_column_text(result_.data_.st_, cast(int) idx_);
        return data ? data[0 .. strlen(data)] : data[0..0];
    }

    // char*, string_ref?

    const(char*) toStringz() {
        // this may not work either because it's not around for the whole row
        return sqlite3_column_text(result_.data_.st_, cast(int) idx_);
    }
}

struct Row(T) {
    //alias Value = .Value!T;
    //alias Result = .Result!T;

    private Result!T* result_;

    this(Result!T* result) {
        result_ = result;
    }

    int columns() {return result_.columns();}

    auto opIndex(size_t idx) {
        return Value!T(result_, idx);
    }
}

struct ResultRange(T) {
    // implements a One Pass Range
    alias Result = .Result!T;
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

    auto front() {
        return Row!T(&result_);
    }

    void popFront() {
        ok_ = result_.next();
    }
}

void throw_error()(sqlite3 *sq, string msg, int ret) {
    import core.stdc.string: strlen;
    const(char*) err = sqlite3_errmsg(sq);
    info(msg, ":", err[0..strlen(err)]);
    throw new DatabaseException("sqlite error: " ~ msg ~ ": "); // need to send err
}

void throw_error()(string label) {
    throw new DatabaseException(label);
}

void throw_error()(string label, char *msg) {
    // frees up pass char * as required by sqlite
    import core.stdc.string : strlen;
    char[] m;
    sizediff_t sz = strlen(msg);
    m.length = sz;
    for(int i = 0; i != sz; i++) m[i] = msg[i];
    sqlite3_free(msg);
    throw new DatabaseException(label ~ m.idup);
}

extern(C) int sqlite_callback(void* cb, int howmany, char** text, char** columns) {
    return 0;
}

