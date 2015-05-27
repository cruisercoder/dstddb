module std.database.test;
import std.database.util;
import std.stdio;

unittest {
    import std.database.sqlite.connection;
    auto db = Database();
    auto con = db.connection("test.sqlite");
    //create_simple_table(con);
    string table = "t1";

    create_score_table(con, table);
    auto stmt = con.statement("select * from " ~ table);
    auto range = stmt.range();
    write_result(range);
}

unittest {
    // bind test
    import std.database.sqlite.connection;
    auto db = Database();
    auto con = db.connection("test.sqlite");
    create_score_table(con, "t1");
    auto stmt = con.statement("select * from t1 where score > ?", 50);
    write_result(stmt.range());
}

unittest {
    // cascade interface idea
    import std.database.sqlite.database;

    writeln();
    writeln("cascade write_result test");
    Database()
        .connection("test.sqlite")
        .statement("select * from t1")
        .range()
        .write_result();
    writeln();
} 

unittest {
    import std.database.mysql.database;
    auto db = Database();
    try {
        Connection con = db.connection("");
    } catch (ConnectionException e) {
        writeln("ignoring can't connect");
    }
}

unittest {
    //auto db = Database(); // what happens here when no default arg on ctor?
    import std.database.oracle.database;
    auto db = Database("something");
}

unittest {
    import std.database.odbc.database;
    auto db = Database("something");
}

unittest {
    import std.database.poly.database;

    Database.register!(std.database.sqlite.database.Database)();
    Database.register!(std.database.mysql.database.Database)();

    auto db = Database("");
}



