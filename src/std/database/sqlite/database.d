module std.database.sqlite.database;

pragma(lib, "sqlite3");

import std.string;
import core.stdc.stdlib;
import std.typecons;
import etc.c.sqlite3;

import std.database.common;
import std.database.exception;
import std.database.source;
import std.database.allocator;
import std.database.pool;
import std.experimental.logger;
import std.database.front;

import std.container.array;
import std.datetime;

import std.stdio;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

alias Database(T) = BasicDatabase!(Driver!T,T);

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

auto createDatabase(T)(string defaultURI="") {
    return Database!T(defaultURI);  
}

struct Driver(Policy) {
    alias Allocator = Policy.Allocator;
    alias Cell = BasicCell!(Driver,Policy);

    struct Database {
        alias queryVariableType = QueryVariableType.QuestionMark;

        static const FeatureArray features = [
            Feature.InputBinding,
            //Feature.DateBinding,
            //Feature.ConnectionPool,
            ];

        this(string defaultSource_) {
        }
    }

    struct Connection {
        Database* db;
        Source source;
        string path;
        sqlite3* sq;

        this(Database* db_, Source source_) {
            db = db_;
            source = source_;

            // map server to path while resolution rules are refined
            path = source.path.length != 0 ? source.path : source.server; // fix

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

    struct Statement {

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
                if (res != SQLITE_OK) throw_error(sq, "prepare", res);
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
            } else {
                throw_error(sq, "step error", status);
            }
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

    }

    struct Bind {
        ValueType type;
        int idx;
    }

    struct Result {
        private Statement* stmt_;
        private sqlite3_stmt *st_;
        int columns;
        int status_;

        // artifical bind array (for now)
        Array!Bind bind;

        this(Statement* stmt, int rowArraySize_) {
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

        bool hasRows() {return stmt_.hasRows;}

        int fetch() {
            status_ = sqlite3_step(st_);
            if (status_ == SQLITE_ROW) return 1;
            if (status_ == SQLITE_DONE) {
                stmt_.reset();
                return 0;
            }
            //throw new DatabaseException("sqlite3_step error: status: " ~ to!string(status_));
            throw new DatabaseException("sqlite3_step error: status: ");
        }

        auto name(size_t idx) {
            import core.stdc.string: strlen;
            auto ptr = sqlite3_column_name(st_, cast(int) idx);
            return cast(string) ptr[0..strlen(ptr)];
        }

        auto get(X:string)(Cell* cell) {
            import core.stdc.string: strlen;
            auto ptr = cast(immutable char*) sqlite3_column_text(st_, cast(int) cell.bind.idx);
            return cast(string) ptr[0..strlen(ptr)]; // fix with length
        }

        auto get(X:int)(Cell* cell) {
            return sqlite3_column_int(st_, cast(int) cell.bind.idx);
        }

        auto get(X:Date)(Cell* cell) {
            return Date(2016,1,1); // fix
        }

    }

    private static void throw_error()(sqlite3 *sq, string msg, int ret) {
        import std.conv;
        import core.stdc.string: strlen;
        const(char*) err = sqlite3_errmsg(sq);
        throw new DatabaseException("sqlite error: " ~ msg ~ ": " ~ to!string(err)); // need to send err
    }

    private static void throw_error()(string label) {
        throw new DatabaseException(label);
    }

    private static void throw_error()(string label, char *msg) {
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

}
