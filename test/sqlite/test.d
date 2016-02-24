module std.database.mysql.test;

unittest {
    import std.database.testsuite;
    import std.database.sqlite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("sqlite");

    //auto db = database("sqlite");
    //auto con = db.connection();
    //con.execute("create table score(name varchar(10), score integer)");
}

