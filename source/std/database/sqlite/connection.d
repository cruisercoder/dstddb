module std.database.sqlite.connection;
pragma(lib, "sqlite3");

import std.string;
import std.typecons;
import std.c.stdlib;

public import std.database.exception;
public import std.database.sqlite.database;
public import std.database.sqlite.bindings;

import std.stdio;

struct Connection {

    private struct Payload {
        Database* db_;
        string filename_;
        sqlite3* sq_;

        this(Database* db, string filename) {
            db_ = db;
            filename_ = filename;
            writeln("sqlite opening ", filename_);
            int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;
            int rc = sqlite3_open_v2(toStringz(filename_), &sq_, flags, null);
            if (rc) {
                writeln("error: rc: ", rc, sqlite3_errmsg(sq_));
            }
        }

        ~this() {
            writeln("sqlite closing ", filename_);
            if (sq_) {
                int rc = sqlite3_close(sq_);
                sq_ = null;
            }
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    package this(Database db, string url) {
        data_ = Data(&db,url);
    }

    Statement statement(string sql) {
        return Statement(this, sql);
    }

    // statements with bind (variadic coming)
    Statement statement(string sql, int v1) {
        Statement stmt = Statement(this, sql);
        stmt.bind(1, v1);
        return stmt;
    }

    void execute(string sql) {
        writeln("sqlite execute ", sql);
        char* msg;
        int rc = sqlite3_exec(data_.sq_, toStringz(sql), &sqlite_callback, null, &msg);
        if (rc != SQLITE_OK) throw_error("execute", msg);
    }

    // private functions
}

struct Statement {
    alias Result = .Result;
    alias Range = .ResultRange;

    private struct Payload {
        Connection con_;
        string sql_;
        sqlite3* sq_;
        sqlite3_stmt *st_;
        int columns_;

        this(Connection con, string sql) {
            con_ = con;
            sql_ = sql;
            sq_ = con_.data_.sq_;
        }

        ~this() {
            //writeln("sqlite statement closing ", filename_);
            if (st_) {
                int res = sqlite3_finalize(st_);
                st_ = null;
            }
        }

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    this(Connection con, string sql) {
        data_ = Data(con,sql);
        execute();
    }

    string sql() {return data_.sql_;}
    int columns() {return data_.columns_;}

    void bind(int col, int value){
        int rc = sqlite3_bind_int(
                data_.st_, 
                col,
                value);
        if (rc != SQLITE_OK) {
            throw_error("sqlite3_bind_int");
        }
    }

    void bind(int col, const char[] value){
        if(value is null) {
            int rc = sqlite3_bind_null(data_.st_, col);
            if (rc != SQLITE_OK) throw_error("bind1");
        } else {
            //cast(void*)-1);
            int rc = sqlite3_bind_text(
                    data_.st_, 
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



    void execute() {
        if (!data_.st_) { 
            int res = sqlite3_prepare_v2(
                    data_.sq_, 
                    toStringz(data_.sql_), 
                    cast(int) data_.sql_.length + 1, 
                    &data_.st_, 
                    null);
            if (res != SQLITE_OK) throw new DatabaseException("prepare error: " ~ data_.sql_);

            data_.columns_ = sqlite3_column_count(data_.st_);
        }
    }

    ResultRange range() {
        return ResultRange(Result(this));
    }


}


struct Result {
    alias Row = .Row;

    private struct Payload {
        private Statement stmt_;
        private sqlite3_stmt *st_;
        int status_;

        this(Statement stmt) {
            stmt_ = stmt;
            st_ = stmt_.data_.st_;
        }

        //~this() {}

        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }

        bool fetch() {
            status_ = sqlite3_step(st_);
            if (status_ == SQLITE_ROW) return true;
            if (status_ == SQLITE_DONE) {
                reset();
                return false;
            }
            //throw new DatabaseException("sqlite3_step error: status: " ~ to!string(status_));
            throw new DatabaseException("sqlite3_step error: status: ");
        }

        void reset() {
            int status = sqlite3_reset(st_);
            if (status != SQLITE_OK) throw new DatabaseException("sqlite3_reset error");
        }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    int columns() {return data_.stmt_.columns();}

    this(Statement stmt) {
        data_ = Data(stmt);
    }

    ResultRange range() {return ResultRange(this);}

    public bool fetch() {return data_.fetch();}

}


struct Value {
    private Result* result_;
    private ulong idx_;

    public this(Result* result, ulong idx) {
        result_ = result;
        idx_ = idx;
    }

    int get(T) () {
        return toInt();
    }

    // bounds check or covered?
    int toInt() {
        return sqlite3_column_int((*result_).data_.st_, cast(int) idx_);
    }

    // not efficient
    string toString() {
        import std.conv;
        return to!string(sqlite3_column_text((*result_).data_.st_, cast(int) idx_));
    }

    // char*, string_ref?

    const(char*) toStringz() {
        // this may not work either because it's not around for the whole row
        return sqlite3_column_text((*result_).data_.st_, cast(int) idx_);
    }
}

struct Row {
    alias Value = .Value;

    private Result* result_;

    this(Result* result) {
        result_ = result;
    }

    int columns() {return result_.columns();}

    Value opIndex(size_t idx) {
        return Value(result_, idx);
    }
}

struct ResultRange {
    // implements a One Pass Range
    alias Row = .Row;

    private Result result_;
    private bool ok_;

    this(Result result) {
        result_ = result;
        ok_ = result_.fetch();
    }

    bool empty() {
        return !ok_;
    }

    Row front() {
        return Row(&result_);
    }

    void popFront() {
        ok_ = result_.fetch();
    }

}

void throw_error(string label) {
    throw new DatabaseException(label);
}

void throw_error(string label, char *msg) {
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
