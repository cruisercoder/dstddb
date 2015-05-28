module demo;
import std.database.util;
import std.stdio;

void main() {
    import std.database.sqlite;

    writeln("--------db demo begin-------");

    auto db = Database();
    auto con = db.connection("demo.sqlite");
    create_score_table(con, "t1");

    writeln();
    Database()
        .connection("demo.sqlite")
        .statement("select * from t1")
        .range()
        .write_result();
    writeln();

    writeln("--------db demo end---------");
}

