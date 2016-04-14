module std.database.sqlite.database;

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
import std.database.impl;

import std.container.array;
import std.datetime;

import std.stdio;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

alias Database(T) = BasicDatabase!(DatabaseImpl!T);
alias Connection(T) = BasicConnection!(ConnectionImpl!T);
alias Statement(T) = BasicStatement!(StatementImpl!T);
alias Result(T) = BasicResult!(ResultImpl!T);
alias ResultRange(T) = BasicResultRange!(Result!T);
alias Row(T) = BasicRow!(ResultImpl!T);
alias Value(T) = BasicValue!(ResultImpl!T);

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

auto createDatabase(T)(string defaultURI="") {
    return Database!T(defaultURI);  
}

struct DatabaseImpl(T) {
    alias Allocator = T.Allocator;
    alias Connection = .ConnectionImpl!T;
    alias queryVariableType = QueryVariableType.QuestionMark;

    bool bindable() {return true;}
    bool dateBinding() {return false;}

    // properties? 

    /*
       string defaultSource() {
       version (assert) if (!refCountedStore.isInitialized) throw new DatabaseException("uninitialized");
       return defaultSource;
       }
     */

    string defaultSource;

    this(string defaultSource_) {
        Allocator allocator;
        defaultSource = defaultSource_;
    }
}

struct ConnectionImpl(T) {
    alias Allocator = T.Allocator;
    alias Database = .DatabaseImpl!T;
    alias Statement = .StatementImpl!T;

    Database* db;
    string path;
    sqlite3* sq;

    this(Database* db_, string source_) {
        db = db_;

        auto source = source_.length == 0 ? db.defaultSource : source_;
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
}

struct StatementImpl(T) {
    alias Connection = .ConnectionImpl!T;
    alias Bind = .Bind!T;
    alias Result = .ResultImpl!T;
    alias Allocator = T.Allocator;

    enum State {
        Init,
        Execute,
    }

    Connection* con;
    string sql;
    State state;
    sqlite3* sq;
    sqlite3_stmt *st;
    bool hasRows;
    int binds_;

    this(Connection* con_, string sql_) {
        con = con_;
        sql = sql_;
        state = State.Init;
        sq = con.sq;
    }

    ~this() {
        //writeln("sqlite statement closing ", filename_);
        if (st) {
            int res = sqlite3_finalize(st);
            st = null;
        }
    }

    void bind(int col, int value){
        int rc = sqlite3_bind_int(
                st, 
                col,
                value);
        if (rc != SQLITE_OK) {
            throw_error("sqlite3_bind_int");
        }
    }

    void bind(int col, const char[] value){
        if(value is null) {
            int rc = sqlite3_bind_null(st, col);
            if (rc != SQLITE_OK) throw_error("bind1");
        } else {
            //cast(void*)-1);
            int rc = sqlite3_bind_text(
                    st, 
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

    void bind(int n, Date d) {
        throw new DatabaseException("Date input binding not yet implemented");
    }

    int binds() {return binds_;}

    void prepare() {
        if (!st) { 
            int res = sqlite3_prepare_v2(
                    sq, 
                    toStringz(sql), 
                    cast(int) sql.length + 1, 
                    &st, 
                    null);
            if (res != SQLITE_OK) error("prepare", res);
            binds_ = sqlite3_bind_parameter_count(st);
        }
    }

    void query() {
        //if (state == State.Execute) throw new DatabaseException("already executed"); // restore
        if (state == State.Execute) return;
        state = State.Execute;
        int status = sqlite3_step(st);
        info("sqlite3_step: status: ", status);
        if (status == SQLITE_ROW) {
            hasRows = true;
        } else if (status == SQLITE_DONE) {
            reset();
        } else throw new DatabaseException("step error");
    }

    void query(X...) (X args) {
        bindAll(args);
        query();
    }

    private void bindAll(T...) (T args) {
        int col;
        foreach (arg; args) bind(++col, arg);
    }

    void reset() {
        int status = sqlite3_reset(st);
        if (status != SQLITE_OK) throw new DatabaseException("sqlite3_reset error");
    }

    void error(string msg, int ret) {con.error(msg, ret);}

}

struct Bind(T) {
    ValueType type;
    int idx;
}

struct ResultImpl(T) {
    //alias ResultRange = .ResultRange!T;
    //alias Row = .Row!T;
    alias Statement = .StatementImpl!T;
    alias Bind = .Bind!T;
    alias Allocator = T.Allocator;

    private Statement* stmt_;
    private sqlite3_stmt *st_;
    int columns;
    int status_;

    // artifical bind array (for now)
    Array!Bind bind;

    this(Statement* stmt) {
        stmt_ = stmt;
        st_ = stmt_.st;
        columns = sqlite3_column_count(st_);

        // artificial bind setup
        bind.reserve(columns);
        for(int i = 0; i < columns; ++i) {
            bind ~= Bind();
            auto b = &bind.back();
            b.type = ValueType.String;
            b.idx = i;
        }
    }

    //~this() {}

    bool start() {return stmt_.hasRows;}

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

    auto get(X:string)(Bind *b) {
        import core.stdc.string: strlen;
        auto ptr = cast(immutable char*) sqlite3_column_text(st_, cast(int) b.idx);
        return cast(string) ptr[0..strlen(ptr)]; // fix with length
    }

    auto get(X:int)(Bind *b) {
        return sqlite3_column_int(st_, cast(int) b.idx);
    }

    auto get(X:Date)(Bind *b) {
        return Date(2016,1,1); // fix
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

/*

auto as(T:string)() {
import core.stdc.string: strlen;
auto ptr = cast(immutable char*) sqlite3_column_text(result_.st_, cast(int) idx_);
return cast(string) ptr[0..strlen(ptr)]; // fix with length
}

auto chars() {
import core.stdc.string: strlen;
auto data = sqlite3_column_text(result_.st_, cast(int) idx_);
return data ? data[0 .. strlen(data)] : data[0..0];
}

// char*, string_ref?

const(char*) toStringz() {
// this may not work either because it's not around for the whole row
return sqlite3_column_text(result_.st_, cast(int) idx_);
}

*/

extern(C) int sqlite_callback(void* cb, int howmany, char** text, char** columns) {
    return 0;
}
