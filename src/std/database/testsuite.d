module std.database.testsuite;
import std.database.util;
import std.stdio;
import std.experimental.logger;

void testAll(Database) (string source) {

    databaseCreation!Database(source);

    auto db = Database(source);

    /*
    simpleInsertSelect(db);    
    classicSelect(db);    

    fieldAccess(db);     // hold for now

    bindTest1(db);
    bindTest2(db);
    */

    bindInsertTest(db);    

    /*
    cascadeTest(db);    
    connectionWithSourceTest(db);
    polyTest!Database(source);    
    */
}

void databaseCreation(Database) (string source) {
    auto db1 = Database();
    auto db2 = Database(source);
}

void simpleInsertSelect(D) (D db) {
    info("simpleInsertSelect");
    create_score_table(db, "score");
    db.execute("insert into score values('Person',123)");
    writeResult(db.connection().statement("select * from score"));
}

void classicSelect(Database) (Database db) {
    // classic non-fluent style with inline iteration
    string table = "t1";
    create_score_table(db, table);
    auto con = db.connection();
    auto stmt = con.statement("select * from " ~ table);
    auto range = stmt[];
    foreach (r; range) {
        for(size_t c = 0; c != r.columns; ++c) {
            if (c) write(",");
            write("", r[c].chars()); // why fail when not .chars()?
        }
        writeln();
    }
}

void fieldAccess(Database)(Database db) {
    auto range = db.connection().statement("select name,score from score")[];
    foreach (r; range) {
        writeln(r[0].as!string,",",r[1].as!int);
    }
}

void bindTest1(Database) (Database db) {
    if (!db.bindable()) {
        writeln("skip bindTest");
        return;
    }

    create_score_table(db, "t1");
    auto stmt = db.connection().statement("select name,score from t1 where score >= ?", 50);
    assert(stmt.binds() == 1);
    auto res = stmt.result();
    assert(res.columns() == 2);
    writeResult(res[]);
}

void bindTest2(Database) (Database db) {
    if (!db.bindable()) {
        writeln("skip bindTest");
        return;
    }

    create_score_table(db, "t1");
    auto stmt = db.connection().statement(
            "select name,score from t1 where score >= ? and score < ?",
            50,
            80);
    assert(stmt.binds() == 2);
    auto res = stmt.result();
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
    auto stmt = con.statement("insert into score values(?,?)");
    stmt.execute("a",1);
    stmt.execute("b",2);
    stmt.execute("c",3);
    con.statement("select * from score").writeResult();
}

void cascadeTest(Database) (Database db) {
    writeln();
    writeln("cascade write_result test");
    db
        .connection()
        .statement("select * from t1")
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
    //db.execute("drop table if exists " ~ table ~ ";");
    try {
        info("drop table:  ", table);
        db.execute("drop table " ~ table);
    } catch (Exception e) {
        info("drop table error (ignored): ", e.msg);
    }
}

void create_simple_table(DB) (DB db, string table) {
    import std.conv;
    Db.Connection con = db.connection();
    con.execute("create table " ~ table ~ "(a integer, b integer)");
    for(int i = 0; i != 10; ++i) {
        con.execute("insert into " ~ table ~ " values(1," ~ to!string(i) ~ ")");
    }
}

void create_score_table(DB) (DB db, string table, bool data = true) {
    import std.conv;
    auto con = db.connection();
    auto names = ["Knuth", "Hopper", "Dijkstra"];
    auto scores = [62, 48, 84];

    db.drop_table(table);
    con.execute("create table " ~ table ~ "(name varchar(10), score integer)");

    if (!data) return;
    for(int i = 0; i != names.length; ++i) {
        con.execute(
                "insert into " ~ table ~ " values(" ~
                "'" ~ names[i] ~ "'" ~ "," ~ to!string(scores[i]) ~ ")");
    }
}

// unused stuff
//auto stmt = con.statement("select * from global_status where VARIABLE_NAME = ?", "UPTIME");

//db.showDrivers(); // odbc

