module std.database.mysql.database;

version(Windows) {
    pragma(lib, "libmysql");
}
else {
    pragma(lib, "mysqlclient");
}

import std.string;
import std.c.stdlib;

import std.database.mysql.bindings;
public import std.database.exception;
public import std.database.mysql.connection;

import std.stdio;
import std.typecons;

struct Database {

    private struct Payload {}

    this(string arg = "") {
    }

    Connection connection(string url) {
        return Connection(this, url);
    } 

}

