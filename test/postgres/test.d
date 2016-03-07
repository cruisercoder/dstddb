module std.database.postgres.test;
import std.database.util;
import std.database.common;
import std.database.postgres;
import std.stdio;

import std.experimental.logger;

unittest {
    import std.database.testsuite;
    alias DB = Database!DefaultPolicy;
    testAll!DB("postgres");
}

unittest {
    /*
    auto db = createDatabase("postgres://127.0.0.1/test");
    //auto con = db.connection();

    //auto res = db.connection().execute("select * from score");
    auto res = db.connection().execute("select name,score from score where score > $1",50);
    //auto res = db.connection().execute("select name,score from score where name = $1","Knuth");
    //assert(res.columns() == 2);
    info("columns: ", res.columns());

    writeResult(res[]);

    //auto result = con.execute("select * from t");
    */
}

