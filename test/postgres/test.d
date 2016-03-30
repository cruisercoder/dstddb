module std.database.postgres.test;
import std.database.util;
import std.database.common;
import std.database.postgres;
import std.stdio;

import std.experimental.logger;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("postgres");

    dateTest();
}

void dateTest() {
    import std.datetime;
    auto db = createDatabase("postgres");
    auto con = db.connection();
    con.query("drop table d1");
    con.query("create table d1(a date)");
    con.query("insert into d1 values('2015-04-05')");
    //con.query("drop table test1");
    //con.query("create table test1(b int)");
    //con.query("insert into test1 values(123)");
    auto rs = con.query("select * from d1");
    //assert(rs[].front()[0].as!Date == Date(2015,4,5));
    writeln(rs[].front()[0].as!Date);
}

unittest {
    /*
    auto db = createDatabase("postgres://127.0.0.1/test");
    //auto con = db.connection();

    //auto res = db.connection().query("select * from score");
    auto res = db.connection().query("select name,score from score where score > $1",50);
    //auto res = db.connection().query("select name,score from score where name = $1","Knuth");
    //assert(res.columns() == 2);
    info("columns: ", res.columns());

    writeResult(res[]);

    //auto result = con.query("select * from t");
    */
}

