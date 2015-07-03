module std.database.odbc.test;
import std.database.util;
import std.stdio;

unittest {
    import std.database.odbc;
    auto db = Database.create("uri");
    db.showDrivers();

    auto con = Connection(db,"odbc");
    //auto stmt = Statement(con, "select name,score from score");
    auto stmt = Statement(
            con,
            "select name,score from score where score>? and name=?",
            1,"c");

    writeln("binds: ", stmt.binds());
    auto res = Result(stmt);
    writeln("columns: ", res.columns());
    auto range = res.range();
    foreach(Result.Range.Row row; range) {
        writeln("row: ", row[0].chars(), ", ", row[1].toInt());
    }
}

