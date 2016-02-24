module std.database.mysql.test;

unittest {
    import std.database.testsuite;
    import std.database.mysql;
    alias DB = Database!DefaultPolicy;
    testAll!DB("mysql");
}

