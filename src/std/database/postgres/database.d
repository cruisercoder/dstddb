module std.database.postgres.database;
pragma(lib, "pq");

import std.string;
import core.stdc.stdlib;
import std.experimental.allocator.mallocator;

import std.database.postgres.bindings;
import std.database.common;
import std.database.exception;
import std.database.resolver;
import std.database.allocator;
import std.container.array;
import std.experimental.logger;

import std.stdio;
import std.typecons;

struct DefaultPolicy {
    alias Allocator = MyMallocator;
}

auto createDatabase()(string defaultURI="") {
    return Database!DefaultPolicy(defaultURI);  
}

auto createDatabase(T)(string defaultURI="") {
    return Database!T(defaultURI);  
}

struct Database(T=DefaultPolicy) {
    alias Allocator = T.Allocator;
    //alias Connection = .Connection!T;

    static const auto queryVariableType = QueryVariableType.Dollar;

    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

    // temporary
    auto connection() {return Connection!T(this);}
    auto connection(string uri) {return Connection!T(this, uri);}
    void query(string sql) {connection().query(sql);}

    bool bindable() {return true;}

    private struct Payload {
        Allocator allocator;
        string defaultURI;

        this(string defaultURI_) {
            allocator = Allocator();
            defaultURI = defaultURI_;
        }

        ~this() {
        }

        this(this) { assert(false); }
        void opAssign(Database.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

}

struct Connection(T) {
    //alias Database = .Database!T;
    //alias Statement = .Statement!T;

    // temporary
    auto statement (string sql) { return Statement!T(this, sql); }
    auto statement(X...) (string sql, X args) {return Statement!T(this, sql, args);}
    auto query(string sql) {return statement(sql).query();}
    auto query(T...) (string sql, T args) {return statement(sql).query(args);}

    package this(Database!T db, string source="") {
        data_ = Data(db,source);
    }

    private:

    struct Payload {
        Database!T db;
        string source;
        PGconn *con;

        this(Database!T db_, string source_) {
            db = db_;
            source = source_.length == 0 ? db.data_.defaultURI : source_;

            Source src = resolve(source);
            string conninfo;
            conninfo ~= "dbname=" ~ src.database;
            con = PQconnectdb(toStringz(conninfo));
            if (PQstatus(con) != CONNECTION_OK) error("login error");
        }

        void error(string msg) {
            import std.conv;
            auto s = msg ~ to!string(PQerrorMessage(con));
            throw new DatabaseException(msg);
        }

        ~this() {
            PQfinish(con);
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;
}


struct Statement(T) {
    alias Allocator = T.Allocator;
    //alias Connection = .Connection!T;
    //alias Result = .Result;
    //alias Range = Result.Range;

    //ResultRange!T range() {return Result!T(this).range();} // no size error

    // temporary
    auto result() {return Result!T(this);}
    auto opSlice() {return Result!T(this);} // no size error

    this(Connection!T con, string sql) {
        data_ = Data(con,sql);
        prepare();
    }

    this(X...) (Connection!T con, string sql, X args) {
        data_ = Data(con,sql);
        prepare();
        bindAll(args);
    }

    string sql() {return data_.sql;}

    void bind(int n, int value) {
    }

    void bind(int n, const char[] value) {
    }

    int binds() {return cast(int) data_.bindValue.length;} // fix

    private:

    struct Payload {
        this(this) { assert(false); }
        void opAssign(Statement.Payload rhs) { assert(false); }

        Connection!T connection;
        string sql;
        Allocator *allocator;
        PGconn *con;
        string name;
        PGresult *prepareRes;
        PGresult *res;

        Array!(char*) bindValue;
        Array!(Oid) bindType;
        Array!(int) bindLength;
        Array!(int) bindFormat;

        this(Connection!T connection_, string sql_) {
            connection = connection_;
            sql = sql_;
            allocator = &connection.data_.db.data_.allocator;
            con = connection.data_.con;
            //prepare();
        }
        ~this() {
            for(int i = 0; i != bindValue.length; ++i) {
                auto ptr = bindValue[i];
                auto length = bindLength[i];
                allocator.deallocate(ptr[0..length]);
            }
        }

        void query() {
            info("query sql: ", sql);

            if (0) {
                if (!prepareRes) prepare();

                auto n = bindValue.length;

                res = PQexecPrepared(
                        con,
                        toStringz(name),
                        cast(int) n,
                        n ? cast(const char **) &bindValue[0] : null,
                        n ? cast(int*) &bindLength[0] : null,
                        n ? cast(int*) &bindFormat[0] : null,
                        0);

            } else {
                if (!PQsendQuery(con, toStringz(sql))) throw error("PQsendQuery");
                res = PQgetResult(con);
            }

            // problem with PQsetSingleRowMode and prepared statements
            // if (!PQsetSingleRowMode(con)) throw error("PQsetSingleRowMode");
        }

        void query(X...) (X args) {
            info("query sql: ", sql);

            // todo: stack allocation

            bindValue.clear();
            bindType.clear();
            bindLength.clear();
            bindFormat.clear();

            foreach (ref arg; args) bind(arg);

            auto n = bindValue.length;

            /*
               types must be set in prepared
               res = PQexecPrepared(
               con,
               toStringz(name),
               cast(int) n,
               n ? cast(const char **) &bindValue[0] : null,
               n ? cast(int*) &bindLength[0] : null,
               n ? cast(int*) &bindFormat[0] : null,
               0);
             */

            int resultForamt = 0;

            res = PQexecParams(
                    con,
                    toStringz(sql),
                    cast(int) n,
                    n ? cast(Oid*) &bindType[0] : null,
                    n ? cast(const char **) &bindValue[0] : null,
                    n ? cast(int*) &bindLength[0] : null,
                    n ? cast(int*) &bindFormat[0] : null,
                    resultForamt);

        }

        void bind(string v) {
            import core.stdc.string: strncpy;
            void[] s = allocator.allocate(v.length+1);
            char *p = cast(char*) s.ptr;
            strncpy(p, v.ptr, v.length);
            p[v.length] = 0;
            bindValue ~= p;
            bindType ~= 0;
            bindLength ~= 0;
            bindFormat ~= 0;
        }

        void bind(int v) {
            import std.bitmanip;
            void[] s = allocator.allocate(int.sizeof);
            *cast(int*) s.ptr = peek!(int, Endian.bigEndian)(cast(ubyte[]) (&v)[0..1]);
            bindValue ~= cast(char*) s.ptr;
            bindType ~= 23; //INT4OID
            bindLength ~= cast(int) s.length;
            bindFormat ~= 1;
        }

        void prepare()  {
            const Oid* paramTypes;
            prepareRes = PQprepare(
                    con,
                    toStringz(name),
                    toStringz(sql),
                    0,
                    paramTypes);
        }

        auto error(string msg) {
            import std.conv;
            string s;
            s ~= msg ~ ", " ~ to!string(PQerrorMessage(con));
            return new DatabaseException(s);
        }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

    void prepare() {
    }

    public:

    auto query() {
        data_.query();
        return result();
    }

    auto query(X...) (X args) {
        data_.query(args);
        return result();
    }

    private:

    void bindAll(T...) (T args) {
        int col;
        foreach (arg; args) {
            bind(++col, arg);
        }
    }

    void reset() {
        //SQLCloseCursor
    }
}

struct Describe(T) {
    int type;
    int fmt;
}


struct Bind {
    int type;
    int fmt;
    void *data;
    int len;
    int isNull; 
}

struct Result(T) {
    alias Allocator = T.Allocator;
    alias Describe = .Describe!T;
    //alias Bind = .Bind!T;
    //alias Statement = .Statement!T;
    //alias ResultRange = .ResultRange!T;
    //alias Range = ResultRange;
    //alias Row = .Row;

    this(Statement!T stmt) {
        data_ = Data(stmt);
    }

    int columns() {return data_.columns;}

    auto opSlice() {return ResultRange!T(this);}

    //bool start() {return data_.status == PGRES_SINGLE_TUPLE;}
    bool start() {return data_.row != data_.rows;}
    bool next() {return data_.next();}

    struct Payload {
        Statement!T stmt;
        PGconn *con;
        PGresult *res;
        int columns;
        Array!Describe describe;
        Array!Bind bind;
        ExecStatusType status;
        int row;
        int rows;

        this(Statement!T stmt_) {
            stmt = stmt_;
            con = stmt.data_.con;
            res = stmt.data_.res;

            if (!setup()) return;
            build_describe();
            build_bind();
        }

        ~this() {
            if (res) close();
        }

        void build_describe() {
            // called after next()
            columns = PQnfields(res);
            for (int col = 0; col != columns; col++) {
                describe ~= Describe();
                auto d = &describe.back();
                d.type = cast(int) PQftype(res, col);
                d.fmt = PQfformat(res, col);
            }
        }

        void build_bind() {
        }

        bool setup() {
            if (!res) {
                info("no result");
                return false;
            }
            status = PQresultStatus(res);
            rows = PQntuples(res);

            // not handling PGRESS_SINGLE_TUPLE yet
            if (status == PGRES_COMMAND_OK) {
                close();
                return false;
            } else if (status == PGRES_EMPTY_QUERY) {
                close();
                return false;
            } else if (status == PGRES_TUPLES_OK) {
                return true;
            } else throw error(status);
        }

        bool next() {
            return ++row != rows;
        }

        bool singleRownext() {
            if (res) PQclear(res);
            res = PQgetResult(con);
            if (!res) return false;
            status = PQresultStatus(res);

            if (status == PGRES_COMMAND_OK) {
                close();
                return false;
            } else if (status == PGRES_SINGLE_TUPLE) return true;
            else if (status == PGRES_TUPLES_OK) {
                close();
                return false;
            } else throw error(status);
        }



        void close() {
            if (!res) throw error("couldn't close result: result was not open");
            res = PQgetResult(con);
            if (res) throw error("couldn't close result: was not finished");
            res = null;
        }

        auto error(string msg) {
            return new DatabaseException(msg);
        }

        auto error(ExecStatusType status) {
            import std.conv;
            string s = "result error: " ~ to!string(PQresStatus(status));
            return new DatabaseException(s);
        }


        this(this) { assert(false); }
        void opAssign(Statement!T.Payload rhs) { assert(false); }
    }


    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;

}

struct ResultRange(T) {
    // implements a One Pass Range
    alias Result = .Result!T;
    alias Row = .Row!T;

    private Result result_;
    private bool ok_;

    this(Result result) {
        result_ = result;
        ok_ = result_.start();
    }

    bool empty() {
        return !ok_;
    }

    Row front() {
        return Row(&result_);
    }

    void popFront() {
        ok_ = result_.next();
    }
}


struct Row(T) {
    alias Result = .Result!T;
    alias Value = .Value;

    this(Result* result) {
        result_ = result;
    }

    int columns() {return result_.columns();}

    auto opIndex(int col) {
        return Value!T(result_, col);
    }

    private Result* result_;
}


struct Value(T) {
    alias Result = .Result!T;
    Result *result;
    int column;
    //Describe desceibe;

    this(Result *result_, int column_) {
        result = result_;
        column = column_;
        //describe = &result.data_.describe[column];
    }

    auto as(X:int)() {
        import std.conv;
        return to!X(as!string());
    }

    auto as(X:string)() {
        immutable char *ptr = cast(immutable char*) data;
        return cast(string) ptr[0..len];
    }

    auto chars() {
        return (cast(char*) data)[0..len];
    }

    private:

    void* data() {return PQgetvalue(result.data_.res, result.data_.row, column);}
    bool isNull() {return PQgetisnull(result.data_.res, result.data_.row, column) != 0;}
    int type() {return result.data_.describe[column].type;}
    int fmt() {return result.data_.describe[column].fmt;}
    int len() {return PQgetlength(result.data_.res, result.data_.row, column);}

}


