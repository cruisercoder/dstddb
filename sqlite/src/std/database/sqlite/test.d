module std.database.sqlite.test;
import std.database.util;
import std.database.test;
import std.stdio;

unittest {
    import std.database.sqlite;
    auto db = Database.create("sqlite");
    testAll(db);
}

