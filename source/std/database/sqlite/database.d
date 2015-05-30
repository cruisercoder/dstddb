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

    static Database create(string defaultURI) {
        return Database(defaultURI);
    }

    Connection connection() {
        version (assert) if (!data_.refCountedStore.isInitialized) throw new RangeError();
        if (!data_.defaultURI.length) throw new DatabaseException("no default URI");
        return Connection(this, data_.defaultURI);
    } 

    Connection connection(string url) {
        version (assert) if (!data_.refCountedStore.isInitialized) throw new RangeError();
        return Connection(this, url);
    } 

    string defaultURI() {
        version (assert) if (!data_.refCountedStore.isInitialized) throw new RangeError();
        return data_.defaultURI;
    }

    // package
    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

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


