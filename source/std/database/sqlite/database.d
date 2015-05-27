module std.database.sqlite.database;

pragma(lib, "sqlite3");

import std.string;
import std.c.stdlib;

import std.database.exception;
import std.database.sqlite.bindings;
public import std.database.sqlite.connection;

import std.stdio;

struct Database {
    alias Connection = .Connection;

    private struct Payload {
        this(this) { assert(false); }
        void opAssign(Database.Payload rhs) { assert(false); }
    }

    this(string arg = "") {
    }

    Connection connection(string url) {
        return Connection(this, url);
    } 
}


