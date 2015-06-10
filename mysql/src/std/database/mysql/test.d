module std.database.mysql.test;
import std.database.util;
import std.stdio;

unittest {
    import std.database.mysql;
    auto db = Database.create("uri");
    try {
        Connection con = db.connection("");
    } catch (ConnectionException e) {
        writeln("ignoring can't connect");
    }
}

unittest {
    import std.database.poly;
    Database.register!(std.database.mysql.database.Database)();
    auto db = Database.create("uri");
}




