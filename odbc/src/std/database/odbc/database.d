module std.database.odbc.database;
pragma(lib, "odbc");

import std.string;
import std.c.stdlib;
import std.conv;

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


}

struct Connection {
    //alias Statement = .Statement;

    private struct Payload {
        Database db;
        string source;
        SQLHDBC con;
        bool connected;

        this(Database db_, string source_) {
            db = db_;
            source = source_;

            char[1024] outstr;
            SQLSMALLINT outstrlen;
            string DSN = "DSN=testdb";

            writeln("ODBC opening: ", source);

            SQLRETURN ret = SQLAllocHandle(SQL_HANDLE_DBC,db.data_.env,&con);
            if ((ret != SQL_SUCCESS) && (ret != SQL_SUCCESS_WITH_INFO)) {
                throw new DatabaseException("SQLAllocHandle error: " ~ to!string(ret));
            }

            string server = source;
            string un = "";
            string pw = "";

            check("SQLConnect", SQL_HANDLE_DBC, con, SQLConnect(
                        con,
                        cast(SQLCHAR*) toStringz(server),
                        SQL_NTS,
                        cast(SQLCHAR*) toStringz(un),
                        SQL_NTS,
                        cast(SQLCHAR*) toStringz(pw),
                        SQL_NTS));
            connected = true;
        }

        ~this() {
            writeln("ODBC closing ", source);
            if (connected) check("SQLDisconnect", SQLDisconnect(con));
            check("SQLFreeHandle", SQLFreeHandle(SQL_HANDLE_DBC, con));
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    package this(Database db, string source) {
        data_ = Data(db,source);
    }
}


void check(string msg, SQLRETURN ret) {
    writeln(msg, ":", ret);
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) return;
    throw new DatabaseException("odbc error: " ~ msg);
}

void check(string msg, SQLSMALLINT handle_type, SQLHANDLE handle, SQLRETURN ret) {
    writeln(msg, ":", ret);
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) return;
    throw_detail(handle, handle_type, msg);
}

void throw_detail(SQLHANDLE handle, SQLSMALLINT type, string msg) {
    SQLSMALLINT i = 0;
    SQLINTEGER native;
    SQLCHAR state[ 7 ];
    SQLCHAR text[256];
    SQLSMALLINT len;
    SQLRETURN ret;

    string error;
    error ~= msg;
    error ~= ": ";

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
            auto s = text[0..len];
            writeln("error: ", s);
            //error =~ s;
            //writefln("%s:%ld:%ld:%s\n", state, i, native, text);
        }
    } while (ret == SQL_SUCCESS);
    throw new DatabaseException(error);
}

/*
   char[1024] outstr;
   SQLSMALLINT outstrlen;
   string DSN = "DSN=testdb";

   check("SQLDriverConnect", SQLDriverConnect(
   con,
   cast(SQLHWND) null,
   cast(SQLCHAR*) toStringz(DSN),
   SQL_NTS,
   cast(SQLCHAR*) outstr,
   outstr.sizeof,
   &outstrlen,
   SQL_DRIVER_NOPROMPT));
 */

