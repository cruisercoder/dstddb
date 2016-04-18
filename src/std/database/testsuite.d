module std.database.testsuite;
import std.database.common;
import std.database.util;
import std.stdio;
import std.experimental.logger;
import std.datetime;

void testAll(Database) (string source) {

    databaseCreation!Database(source);

    auto db = Database(source);

    simpleInsertSelect(db);    
    //create_score_table(db, "score");

    classicSelect(db); 

    fieldAccess(db);

    bindTest0(db);
    bindTest1(db);
    bindTest2(db);
    bindInsertTest(db);    
    dateBindTest(db);

    cascadeTest(db);    
    connectionWithSourceTest(db);

    polyTest!Database(source);    
}

void databaseCreation(Database) (string source) {
    auto db1 = Database();
    auto db2 = Database(source);
}

void simpleInsertSelect(D) (D db) {
    info("simpleInsertSelect");
    //create_score_table(db, "score");

    db.query("insert into score values('Person',123)");

    //writeResult(db.connection().statement("select * from score")); // maybe should work too?
    writeResult(db.connection().statement("select * from score").query());
}

void classicSelect(Database) (Database db) {
    // classic non-fluent style with inline iteration
    string table = "t1";
    create_score_table(db, table);
    auto con = db.connection();
    auto result = con.query("select * from " ~ table);
    auto range = result[];
    foreach (r; range) {
        for(int c = 0; c != r.columns; ++c) {
            if (c) write(",");
            write("", r[c].chars()); // why fail when not .chars()?
        }
        writeln();
    }
}

void fieldAccess(Database)(Database db) {
    auto rowSet = db.connection().query("select name,score from score");
    foreach (r; rowSet) {
        writeln(r[0].as!string,",",r[1].as!int);
    }
}

void bindTest0(Database) (Database db) {
    if (!db.bindable()) {
        writeln("skip bindTest");
        return;
    }

    create_score_table(db, "t1");

    QueryVariable!(Database.queryVariableType) v;
    auto res = db.connection().query("select name,score from t1 where score >= " ~ v.next(), 50);
    //auto res = db.connection().query("select name,score from t1");
    assert(res.columns() == 2);
    writeResult(res[]);
}


void bindTest1(Database) (Database db) {
    if (!db.bindable()) {
        writeln("skip bindTest");
        return;
    }

    create_score_table(db, "t1");

    QueryVariable!(Database.queryVariableType) v;
    auto stmt = db.connection().statement("select name,score from t1 where score >= " ~ v.next());
    //assert(stmt.binds() == 1); // prepare problem
    auto res = stmt.query(50);
    assert(res.columns() == 2);
    writeResult(res[]);
}

void bindTest2(Database) (Database db) {
    if (!db.bindable()) {
        writeln("skip bindTest");
        return;
    }

    create_score_table(db, "t1");

    // clean up / clarify

    QueryVariable!(Database.queryVariableType) v;
    auto stmt = db.connection()
        .statement(
                "select name,score from t1 where score >= " ~ v.next() ~
                " and score < " ~ v.next());
    // assert(stmt.binds() == 2); // fix
    auto res = stmt.query(50, 80);
    assert(res.columns() == 2);
    writeResult(res[]);
}

void bindInsertTest(Database) (Database db) {
    if (!db.bindable()) {
        writeln("skip bindInsertTest");
        return;
    }

    // bind insert test
    create_score_table(db, "score", false);
    auto con = db.connection();
    QueryVariable!(Database.queryVariableType) v;
    auto stmt = con.statement(
            "insert into score values(" ~ v.next() ~
            "," ~ v.next() ~ ")");
    stmt.query("a",1);
    stmt.query("b",2);
    stmt.query("c",3);
    con.query("select * from score").writeResult();
}

void dateBindTest(Database) (Database db) {
    // test date input and output binding
    import std.datetime;
    if (!db.dateBinding()) {
        writeln("skip dateInputBindTest");
        return;
    }

    auto d = Date(2016,2,3);
    auto con = db.connection();
    db.drop_table("d1");
    con.query("create table d1(a date)");

    QueryVariable!(Database.queryVariableType) v;
    con.query("insert into d1 values(" ~ v.next() ~ ")", d);

    auto rs = con.query("select * from d1");
    //assert(rs[].front()[0].as!Date == d);
    writeResult(rs[]);
}

void cascadeTest(Database) (Database db) {
    writeln();
    writeln("cascade write_result test");
    db
        .connection()
        .query("select * from t1")
        .writeResult();
    writeln();
} 

void connectionWithSourceTest(Database) (Database db) {
    //auto con = db.connection(db.defaultSource());
} 


void polyTest(DB) (string source) {
    // careful to distinguiush DB from imported Database type
    import std.database.poly;
    Database.register!(DB)();
    auto db = Database(source);
}

// utility stuff


void drop_table(D) (D db, string table) {
    //db.query("drop table if exists " ~ table ~ ";");
    try {
        info("drop table:  ", table);
        db.query("drop table " ~ table);
    } catch (Exception e) {
        info("drop table error (ignored): ", e.msg);
    }
}

void create_simple_table(DB) (DB db, string table) {
    import std.conv;
    Db.Connection con = db.connection();
    con.query("create table " ~ table ~ "(a integer, b integer)");
    for(int i = 0; i != 10; ++i) {
        con.query("insert into " ~ table ~ " values(1," ~ to!string(i) ~ ")");
    }
}

void create_score_table(DB) (DB db, string table, bool data = true) {
    import std.conv;
    auto con = db.connection();
    auto names = ["Knuth", "Hopper", "Dijkstra"];
    auto scores = [62, 48, 84];

    db.drop_table(table);
    con.query("create table " ~ table ~ "(name varchar(10), score integer)");

    if (!data) return;
    for(int i = 0; i != names.length; ++i) {
        con.query(
                "insert into " ~ table ~ " values(" ~
                "'" ~ names[i] ~ "'" ~ "," ~ to!string(scores[i]) ~ ")");
    }
}


// unused stuff
//auto stmt = con.statement("select * from global_status where VARIABLE_NAME = ?", "UPTIME");

//db.showDrivers(); // odbc

