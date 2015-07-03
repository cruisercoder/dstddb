module std.database.oracle.test;
import std.database.oracle;
import std.database.util;
import std.stdio;

unittest {
    import std.database.oracle;
    auto db = Database.create("oracle");
    auto con = Connection(db,"oracle");
    auto stmt = Statement(con, "select * from t");
    auto res = Result(stmt);
    auto range = res.range();
    foreach(Result.Range.Row row; range) {
        writeln("row: ", row[0].chars());
    }
}

