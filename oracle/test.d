import std.database.util;
import std.stdio;
import std.database.oracle;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("oracle");

    //testArrayOutputBinding();

    //dateTest();

    //auto database1 = Database!()();
    //auto database2 = Database!()("oracle");

    /*
       auto database3 = createDatabase();
       auto database4 = std.database.oracle.createDatabase();
     */

    //auto database = Database!DefaultPolicy.create("oracle");
    //auto database = Database.create("oracle");

    //auto database = database("oracle");
    //auto con = database.connection();

    /*
       auto db = database("oracle");
       auto con = db.connection();

       try {
       con.query("drop table t");
       } catch (Exception e) {
       }

       con.query("create table t(name varchar(20), age int)");
       con.query("insert into t values('Bob',12)");
       con.query("insert into t values('Joe',9)");

       con.statement("select * from t");
    //auto res = result(stmt);
    //writeResult(res);

    //writeResultRange(stmt.range());
    writeResultRange(con.statement("select * from t").range());
     */

}

void testArrayOutputBinding() {
    // test different combinations
    import std.conv;
    import std.datetime;

    auto db = createDatabase("oracle");
    auto con = db.connection();


    if (false) {
        con.query("drop table t1");
        con.query("create table t1(a integer, b integer)");
        for(int i = 0; i != 1000; ++i) {
            con.query("insert into t1 values(" ~ to!string(i) ~ "," ~ to!string(i+1) ~ ")");
        }
    }

    TickDuration[] durations;

    static const int N = 4;
    real[N] durationsUsecs;

    foreach(i; 0..N) {
        auto rs = con.rowArraySize(100).query("select * from t1");
        StopWatch sw;
        sw.start();

        int s;
        foreach(r;rs) {
            s += r[0].as!int + r[1].as!int;
        }

        durations ~= sw.peek;
        writeln("time: ", to!Duration(sw.peek));
    }

    real sum = 0;

    foreach (TickDuration duration; durations) {
        real usecs = duration.usecs();
        sum += usecs;
    }

    real avg = sum / N;
    writeln("avg time: ", avg);
}

void dateTest() {
    import std.datetime;
    auto db = createDatabase("oracle");
    auto con = db.connection();
    con.query("drop table d1");
    con.query("create table d1(a date, b int)");
    con.query("insert into d1 values(to_date('2015/04/05','yyyy/mm/dd'), 123)");
    auto rs = con.query("select * from d1");
    assert(rs[].front()[0].as!Date == Date(2015,4,5));
}

