module std.database.odbc.database;
pragma(lib, "iodbc");

import std.string;
import std.c.stdlib;

import std.database.odbc.sql;
import std.database.odbc.sqlext;

public import std.database.exception;

import std.stdio;
import std.typecons;

struct Database {
    public:

        static Database create(string defaultURI) {
            return Database(defaultURI);
        }


        this(string defaultURI) {
            data_ = Data(defaultURI);
        }

    private:

        struct Payload {
            string defaultURI;
            void* env_;

            this(string defaultURI_) {
                defaultURI = defaultURI_;
                check("SQLAllocHandle", SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &env_));
            }

            ~this() {
                writeln("odbc: closing database");
                if (!env_) return;
                check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_ENV, env_));
                env_ = null;
            }

            this(this) { assert(false); }
            void opAssign(Database.Payload rhs) { assert(false); }
        }

        private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
        private Data data_;

        static void check(string msg, SQLRETURN ret) {
            writeln(msg);
            if (ret == SQL_SUCCESS) return;
            throw new DatabaseException("odbc error: " ~ msg);
        }
}


