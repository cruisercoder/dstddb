module demo;
import std.database.util;
import std.stdio;

void main() {
    import std.database.sqlite;

    writeln("--------db demo begin-------");

    /auto db = Database.create("demo.sqlite");
    //auto db = Database.create();
    //db.defaultURI("demo.sqlite");

    create_score_table(db, "t1");

    writeln();
    db
        .connection()
        .statement("select * from t1")
        .range()
        .write_result();
    writeln();

    writeln("--------db demo end---------");
}

