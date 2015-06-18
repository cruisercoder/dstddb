module std.database.mysql.test;
import std.database.util;
import std.stdio;

unittest {
    import std.database.mysql;
    auto db = Database.create("mysql");
    auto con = db.connection("mysql");
    //auto stmt = con.statement("select * from global_status where VARIABLE_NAME='UPTIME'");
    auto stmt = con.statement("select * from global_status where VARIABLE_NAME = ?", "UPTIME");
    writeln("columns: ", stmt.columns());
    writeln("binds: ", stmt.binds());
    auto res = Result(stmt);
    auto range = res.range();
    foreach(Result.Range.Row row; range) {
        writeln("row: ", row[0].chars());
    }
    
}

unittest {
    import std.database.poly;
    Database.register!(std.database.mysql.database.Database)();
    auto db = Database.create("uri");
}




