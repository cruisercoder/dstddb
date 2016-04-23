module std.database.sqlite.test;
import std.database.sqlite;
import std.database.util;
import std.stdio;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("sqlite");
}

unittest {
    auto db = createDatabase("path:///testdb");
    //auto rowSet = db.connection().statement("select name,score from score").query;
    auto rowSet = db.connection().query("select name,score from score");
    foreach (r; rowSet) {
        writeln(r[0].as!string,",",r[1].as!int);
        //writeln(r[0],", ",r[1]);
    }
}


