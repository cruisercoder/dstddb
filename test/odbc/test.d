module std.database.odbc.test;
import std.database.util;
import std.stdio;

unittest {
    import std.database.testsuite;
    import std.database.odbc;

    // not ready yet: need connection pool for odbc/sqlite
    alias DB = Database!DefaultPolicy;
    testAll!DB("odbc");

    if (false) {
        auto db = createDatabase("odbc");
        //db.showDrivers(); // odbc

        auto con = db.connection();

        con.query("drop table score");
        con.query("create table score(name varchar(10), score integer)");
    }

    /*
    //auto stmt = Statement(con, "select name,score from score");
    auto stmt = con.statement(
    "select name,score from score where score>? and name=?",
    1,"jo");
    writeln("binds: ", stmt.binds());
    auto res = stmt.result();
    writeln("columns: ", res.columns());
    auto range = res.range();
     */
}


