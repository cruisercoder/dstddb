import std.database.util;
import std.stdio;

unittest {
    import std.database.testsuite;
    import std.database.oracle;
    alias DB = Database!DefaultPolicy;
    testAll!DB("oracle");

    //auto database1 = Database!()();
    //auto database2 = Database!()("oracle");

    auto database3 = createDatabase();
    auto database4 = std.database.oracle.createDatabase();

    //auto database = Database!DefaultPolicy.create("oracle");
    //auto database = Database.create("oracle");

    //auto database = database("oracle");
    //auto con = database.connection();

    /*
    auto db = database("oracle");
    auto con = db.connection();

    try {
        con.execute("drop table t");
    } catch (Exception e) {
    }

    con.execute("create table t(name varchar(20), age int)");
    con.execute("insert into t values('Bob',12)");
    con.execute("insert into t values('Joe',9)");

    con.statement("select * from t");
    //auto res = result(stmt);
    //writeResult(res);

    //writeResultRange(stmt.range());
    writeResultRange(con.statement("select * from t").range());
    */
}

