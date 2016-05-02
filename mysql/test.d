module std.database.mysql.test;
import std.database.util;
import std.database.mysql;
import std.experimental.logger;
import std.stdio;

import std.database.rowset;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("mysql");

    //negativeNotExecuteTest();
}


void negativeNotExecuteTest() {
    auto db = createDatabase("mysql://127.0.0.1/test");
    auto con = db.connection();
    //con.statement("select * from score").writeRows;
    con.statement("select * from score").writeRows;
}

unittest {
    //perf1();
    //con.query("select * from tuple").writeRows;
}

//auto db = createDatabase("mysql://127.0.0.1/test");

/*
void perf1() {
    import std.datetime;
    import std.conv;

    auto db = createDatabase("mysql://127.0.0.1/test");
    auto con = db.connection();

    if (0) {
        db.query("drop table if exists tuple");
        con.query("create table tuple (a int, b int, c int)");
        QueryVariable!(Database!DefaultPolicy.queryVariableType) v;
        auto stmt = con.statement(
                "insert into tuple values(" ~ v.next() ~ "," ~ v.next() ~ "," ~ v.next() ~ ")");

        for(int i = 0; i != 1000; ++i) {
            if ((i % 10000) ==0) warning(i);
            stmt.query(i, i+1, i+2);
        }
    }

    auto result = con.query("select * from tuple");

    StopWatch sw;
    sw.start();
    auto rs = RowSet(result);
    writeln("rowSec ctor time: ", to!Duration(sw.peek));

    StopWatch sw2;
    sw2.start();

    int sum;

    uint n = 1;
    foreach(i; 0..n) {
        foreach (r; rs[]) sum = r[0].as!int + r[1].as!int + r[2].as!int;
    }

    writeln("sum: ", sum);
    writeln("time: ", to!Duration(sw2.peek));
}
*/
