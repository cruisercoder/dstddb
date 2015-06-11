module std.database.odbc.database;
pragma(lib, "odbc");

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

        void showDrivers() {
            SQLUSMALLINT direction;

            SQLCHAR driver[256];
            SQLCHAR attr[256];
            SQLSMALLINT driver_ret;
            SQLSMALLINT attr_ret;
            SQLRETURN ret;

            direction = SQL_FETCH_FIRST;
            writeln("DRIVERS:");
            while(SQL_SUCCEEDED(ret = SQLDrivers(
                            data_.env, 
                            direction,
                            driver.ptr, 
                            driver.sizeof, 
                            &driver_ret,
                            attr.ptr, 
                            attr.sizeof, 
                            &attr_ret))) {
                direction = SQL_FETCH_NEXT;
                printf("%s - %s\n", driver.ptr, attr.ptr);
                if (ret == SQL_SUCCESS_WITH_INFO) printf("\tdata truncation\n");
            }
        }

    private:

        struct Payload {
            string defaultURI;
            SQLHENV env;

            this(string defaultURI_) {
                defaultURI = defaultURI_;
                writeln("dummy");
                check(
                        "SQLAllocHandle", 
                        SQLAllocHandle(
                            SQL_HANDLE_ENV, 
                            SQL_NULL_HANDLE,
                            &env));
                SQLSetEnvAttr(env, SQL_ATTR_ODBC_VERSION, cast(void *) SQL_OV_ODBC3, 0);
            }

            ~this() {
                writeln("odbc: closing database");
                if (!env) return;
                check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_ENV, env));
                env = null;
            }

            this(this) { assert(false); }
            void opAssign(Database.Payload rhs) { assert(false); }
        }

        private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
        private Data data_;

        static void check(string msg, SQLRETURN ret) {
            writeln(msg, ":", ret);
            if (ret == SQL_SUCCESS) return;
            throw new DatabaseException("odbc error: " ~ msg);
        }

        static void check(string msg, SQLHANDLE handle, SQLRETURN ret) {
            writeln(msg, ":", ret);
            if (ret == SQL_SUCCESS) return;
            extract_error(handle, SQL_HANDLE_ENV);
            throw new DatabaseException("odbc error: " ~ msg);
        }

        static void extract_error(SQLHANDLE handle, SQLSMALLINT type) {
            SQLSMALLINT i = 0;
            SQLINTEGER native;
            SQLCHAR state[ 7 ];
            SQLCHAR text[256];
            SQLSMALLINT len;
            SQLRETURN ret;

            do {
                ret = SQLGetDiagRec(
                        type,
                        handle,
                        ++i,
                        cast(char*) state,
                        &native,
                        cast(char*)text,
                        text.length,
                        &len);

                if (SQL_SUCCEEDED(ret)) {
                    writefln("%s:%ld:%ld:%s\n", state, i, native, text);
                }
            } while( ret == SQL_SUCCESS );
        }

}


