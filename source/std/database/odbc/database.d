module std.database.odbc.database;
//pragma(lib, "something");

import std.string;
import std.c.stdlib;

public import std.database.odbc.bindings;
public import std.database.exception;

import std.stdio;
import std.typecons;

struct Database {

    private struct Payload {
        string defaultURI;
        void* env_;

        this(string defaultURI_) {
            defaultURI = defaultURI_;
            writeln("odbc: opening database");
            SQLRETURN ret;
            ret = SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &env_);
            //if (!SQL_SUCCEEDED(ret)) {
            //throw std::runtime_error("error");
            //}
        }

        ~this() {
            writeln("odbc: closing database");
            if (env_) {
                SQLRETURN ret;
                ret = SQLFreeHandle(SQL_HANDLE_ENV, env_);
                env_ = null;
            }
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


