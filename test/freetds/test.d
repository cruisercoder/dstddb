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

    //simpleTest();
    //backTest();
}
void simpleTest() {
    auto db = createDatabase("freetds://server/test?username=sa&password=admin");
    string sql = "12 SELEC 1,2,3"; // error check
    //string sql = "SELECT  * FROM master.dbo.spt_monitor";
    writeResult(db.query(sql));
}

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


