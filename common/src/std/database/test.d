module std.database.test;
import std.database.util;
import std.stdio;

void testAll(Database) (Database db) {
    simpleInsert(db);    
    classicSelect(db);    
    bindTest(db);    
    bindInsertTest(db);    
    cascadeTest(db);    
    connectionWithSourceTest(db);
    polyTest!Database();    
}

void simpleInsert(Database) (Database db) {
    // execute from db
    create_score_table(db, "score");
    db.execute("insert into score values('Person',123)");
    write_result(db.connection().statement("select * from score").range());
}

void classicSelect(Database) (Database db) {
    // classic example
    string table = "t1";
    create_score_table(db, table);
    auto con = db.connection();
    auto stmt = con.statement("select * from " ~ table);
    auto range = stmt.range();
    write_result(range);
}

void bindTest(Database) (Database db) {
    create_score_table(db, "t1");
    auto stmt = db.connection().statement(
            "select * from t1 where score >= ? and score < ?",
            50,
            80);
    write_result(stmt.range());
}

void bindInsertTest(Database) (Database db) {
    // bind insert test
    create_score_table(db, "score", false);
    auto con = db.connection();
    auto stmt = con.statement("insert into score values(?,?)");
    stmt.execute("a",1);
    stmt.execute("b",2);
    stmt.execute("c",3);
    con.statement("select * from score").range().write_result();
}

void cascadeTest(Database) (Database db) {
    writeln();
    writeln("cascade write_result test");
    db
        .connection()
        .statement("select * from t1")
        .range()
        .write_result();
    writeln();
} 

void connectionWithSourceTest(Database) (Database db) {
    auto con = db.connection(db.defaultSource());
} 


void polyTest(DB) () {
    // careful to distinguiush DB from imported Database type
    import std.database.poly;
    Database.register!(DB)();
    auto db = Database.create("uri");
}


