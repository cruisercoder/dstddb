module std.database.postgres.test;
import std.database.util;
import std.database.common;
import std.database.postgres;
import std.stdio;

import std.experimental.logger;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("postgres");
}

