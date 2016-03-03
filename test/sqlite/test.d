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
    auto db = createDatabase("path:///testdb");
    auto con = db.connection();
    //con.statement("select * from score").writeResult();
    auto range = con.statement("select name,score from score")[];
    foreach (r; range) {
        writeln(r[0].as!string,",",r[1].as!int);
    }
}


