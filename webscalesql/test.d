module std.database.webscalesql.test;
import std.database.util;
import std.database.mysql;
import std.experimental.logger;
import std.stdio;

import std.database.testsuite;
import std.database.rowset;

unittest {
    alias DB = Database!DefaultPolicy;
    testAll!DB("mysql");
}

unittest {
    alias DB = AsyncDatabase!DefaultPolicy;
    auto db = DB("mysql://127.0.0.1/test");
    auto con = db.connection();
}


