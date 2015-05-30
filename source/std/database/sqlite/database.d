module std.database.sqlite.database;

pragma(lib, "sqlite3");

import std.string;
import std.c.stdlib;
import std.typecons;

import std.database.exception;
import std.database.sqlite.bindings;
public import std.database.sqlite.connection;

import std.stdio;

struct Database {
    alias Connection = .Connection;

    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

    Connection connection() {
        if (!data_.defaultURI.length) throw new DatabaseException("no default URI");
        return Connection(this, data_.defaultURI);
    } 

    Connection connection(string url) {
        return Connection(this, url);
    } 

    string defaultURI() {return data_.defaultURI;}

    private:

    struct Payload {
        string defaultURI;

        this(string defaultURI_) {
            defaultURI = defaultURI_;
        }
        this(this) { assert(false); }
        void opAssign(Database.Payload rhs) { assert(false); }
    }

    alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    Data data_;
}


