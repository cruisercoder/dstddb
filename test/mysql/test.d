module std.database.mysql.test;
import std.database.util;
import std.database.mysql;
import std.stdio;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("mysql");
}

unittest {
    auto db = createDatabase("mysql://127.0.0.1/test");
    auto con = db.connection();
    //con.statement("select * from score").query[].writeResult();
    con.query("select * from score").writeResult();
}


