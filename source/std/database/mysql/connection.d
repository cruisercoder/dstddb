module std.database.mysql.connection;

import std.string;
import std.typecons;
import std.c.stdlib;
public import std.database.exception;
public import std.database.mysql.bindings;
import std.database.mysql.database;

import std.stdio;

struct Connection {

    private struct Payload {
        string url_;
        MYSQL *mysql_;

        this(Database db, string filename) {
            mysql_ = mysql_init(null);
            if (!mysql_) {
                throw new DatabaseException("couldn't init mysql");
            }
        }

        ~this() {
            writeln("mysql closing ", url_);
            if (mysql_) {
                mysql_close(mysql_);
                mysql_ = null;
            }
        }

        this(this) { assert(false); }
        void opAssign(Connection.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    package this(Database db, string url) {
        data_ = Data(db,url);
        open(url);
    }

    void open(string url) {
        data_.url_ = url;
        writeln("mysql opening ", data_.url_);

        string host = data_.url_;
        string un="un";
        string pw="pw";
        string db="db";
        if (!mysql_real_connect(
                    data_.mysql_,
                    cast(cstring) toStringz(host),
                    cast(cstring) toStringz(un),
                    cast(cstring) toStringz(pw),
                    cast(cstring) toStringz(db),
                    0,
                    null,
                    0)) {
            throw new ConnectionException("couldn't connect");
        }
    }


    void execute(string sql) {
    }
}

