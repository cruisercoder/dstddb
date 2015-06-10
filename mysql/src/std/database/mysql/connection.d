module std.database.mysql.connection;

import std.string;
import std.typecons;
import std.c.stdlib;
public import std.database.resolver;
public import std.database.exception;
public import std.database.mysql.bindings;
import std.database.mysql.database;

import std.stdio;

struct Connection {

    private struct Payload {
        string url_;
        MYSQL *mysql_;

        this(Database db, string name) {
            writeln("name: ", name);

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
        Source source = resolve(url);

        if (!mysql_real_connect(
                    data_.mysql_,
                    cast(cstring) toStringz(source.server),
                    cast(cstring) toStringz(source.username),
                    cast(cstring) toStringz(source.password),
                    cast(cstring) toStringz(source.database),
                    0,
                    null,
                    0)) {
            throw new ConnectionException("couldn't connect");
        }
    }
}

