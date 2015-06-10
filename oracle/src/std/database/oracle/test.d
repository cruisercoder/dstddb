module std.database.oracle.test;
import std.database.oracle;
import std.database.util;
import std.stdio;

unittest {
    import std.database.oracle;
    auto db = Database.create("oracle");
    /*
    try {
        Connection con = db.connection("oracle");
    } catch (ConnectionException e) {
        writeln("ignoring can't connect");
    }
    */
}

