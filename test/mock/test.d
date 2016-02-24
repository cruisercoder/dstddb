module std.database.mock.test;
import std.database.mock;
import std.database.util;
import std.stdio;
import std.experimental.logger;

unittest {
    import std.database.mock;
    import std.database.util;

    auto db = database();
    auto db1 = database!int();
    auto db2 = database("defaultUrl");

    auto con = Connection!int(db,"mock");
    auto con2 = db.connection("source");
    auto con3 = connection(db,"source");

    con.execute("drop table t");

    auto stmt = statement(con, "select * from t");
    auto res = result(stmt);
    auto res2 = stmt.result();

    auto range = res.range();

    writeResult(res);
    writeResultRange(range);

    // cant easily name row type
    //foreach(Range.Row row; range) {
        //writeln("row: ", row[0].chars());
    //}

}

