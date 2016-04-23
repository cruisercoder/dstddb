module std.database.freetds.test;
import std.database.util;
import std.database.freetds;
import std.experimental.logger;
import std.stdio;

import std.database.testsuite;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("freetds");

    //example();
    //backTest();
}

void example() {
    import std.database.freetds;
    //auto db = createDatabase("freetds://server/test?username=sa&password=admin");
    auto db = createDatabase("freetds://10.211.55.3:1433/test?username=sa&password=admin");
    auto result = db.query("SELECT 1,2,'abc'");
    foreach (r; result) {
        for(int c = 0; c != r.columns; ++c) writeln("column: ",c,", value: ",r[c].as!string);
    }
}

/*
void backTest() {
    //string sql = "SELECT  * FROM dbo.spt_monitor";
    string sql = "SELECT 1,2,3";

    auto db = Impl.Database!DefaultPolicy();
    auto con = Impl.Connection!DefaultPolicy(&db,"freetds");
    auto stmt = Impl.Statement!DefaultPolicy(&con,sql);
    stmt.prepare();
    stmt.query();
    auto result = Impl.Result!DefaultPolicy(&stmt);
    do {
        writeln("first: ", result.get!string(&result.bind[0]));
        writeln("second: ", result.get!string(&result.bind[1]));
    } while (result.next());
}
*/


