module std.database.reference.test;
import std.database.reference;
import std.database.util;
import std.stdio;
import std.experimental.logger;

unittest {
    import std.database.reference;
    import std.database.util;

    auto db = createDatabase();
    auto db1 = createDatabase("defaultUrl");
    auto db2 = createDatabase!DefaultPolicy();

    auto con = db.connection("source");

    con.execute("drop table t");

    auto stmt = statement(con, "select * from t");
    auto res = stmt.result();

    auto range = res.range();

    writeResult(res);
    writeResultRange(range);

    // cant easily name row type
    //foreach(Range.Row row; range) {
        //writeln("row: ", row[0].chars());
    //}

}

