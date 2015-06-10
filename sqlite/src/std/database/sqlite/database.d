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
    alias Statement = .Statement;

    static Database create() {
        return Database("");
    }

    static Database create(A...)(auto ref A args) {
        return Database(args);
    }

    Connection connection() {
        version (assert) if (!data_.refCountedStore.isInitialized) throw new DatabaseException("uninitialized");
        if (!data_.defaultURI.length) throw new DatabaseException("no default URI");
        return Connection(this, data_.defaultURI);
    } 

    Connection connection(string url) {
        version (assert) if (!data_.refCountedStore.isInitialized) throw new DatabaseException("uninitialized");
        return Connection(this, url);
    } 

    string defaultURI() {
        version (assert) if (!data_.refCountedStore.isInitialized) throw new DatabaseException("uninitialized");
        return data_.defaultURI;
    }

    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

    // properties?
    string defaultURI() {return data_.defaultURI;}
    void defaultURI(string defaultURI) {data_.defaultURI = defaultURI;}

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


