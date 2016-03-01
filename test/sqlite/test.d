module std.database.mysql.test;
import std.database.sqlite;
import std.database.util;
import std.stdio;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("sqlite");

    //auto db = database("sqlite");
    //auto con = db.connection();
    //con.execute("create table score(name varchar(10), score integer)");
}

unittest {
    //auto db = createDatabase("path:///testdb");
    //auto con = db.connection();
    //con.statement("select * from score").writeResult();
}


