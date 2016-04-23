module std.database.odbc.test;
import std.database.util;
import std.stdio;

unittest {
    import std.database.testsuite;
    import std.database.odbc;
    alias DB = Database!DefaultPolicy;
    testAll!DB("odbc");

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


