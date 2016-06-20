import std.database.util;
import std.stdio;
import std.database.oracle;
import std.experimental.logger;
import std.datetime;
import std.variant;

struct Resource(T) {}
struct Policy {}

auto create(alias T)() {
    T!Policy r;
    return r;
}

auto r = create!Resource;

struct TestOutputRange {
    void put(int i) {
        log("I: ", i);
    }
    void put(string s) {
        log("S: ", s);
    }
}


unittest {
    import std.database.testsuite;
    //alias DB = Database!DefaultPolicy;
    //testAll!DB("oracle");

    // these are all heading to test suite

    if (true) { //opDispatch
        auto db = createDatabase("oracle");
        auto con = db.connection;
        auto rows = db.query("select * from t").rows;

        foreach (row; rows) {
            for(int c = 0; c != row.width; ++c) {
                //log("NAME: ", row[c].name);
                writeln("a:", row.A);
                writeln("b:", row.B);
            }
            writeln;
        }

    }

    if (false) {
        auto db = createDatabase;
        auto con1 = db.connection("oracle").autoCommit(false);
        auto con2 = db.connection("oracle").autoCommit(false);

        scope(failure) con1.rollback;
        scope(failure) con2.rollback;

        //con1.begin.query("insert into account(id,amount) values(1,100)");
        //con2.begin.query("insert into account(id,amount) values(2,-100)");

        con1.commit;
        con2.commit;
    }

    if (false) {
        auto db = createDatabase("oracle");
        auto con = db.connection;
        auto stmt = con.statement("select * from score");
        auto row = stmt.query.rows.front();
        //stmt.query.rows.writeRows;

        TestOutputRange r; 
        row.into(r);
    }

    if (false) {
        auto db = createDatabase("oracle");
        auto con = db.connection;
        auto stmt = con.statement("select * from score");
        auto rows = stmt.query.rows;
        //stmt.query.rows.writeRows;

        foreach (row; rows) {
            string name;
            int score;
            row.into(name,score);
            writeln("name: ", name, ", score: ", score);
        }
    }

    if (false) { // classic example 2
        auto db = createDatabase("oracle");
        auto con = db.connection;
        auto stmt = con.statement("select * from t");
        auto rows = stmt.query.rows;

        foreach (row; rows) {
            foreach (column; rows.columns) {
                auto field = row[column];
                writeln("name: ", column.name, ", value: ", field);
            }
            writeln;
        }
    }

    if (false) { // classic example
        auto db = createDatabase("oracle");
        auto con = db.connection;
        auto stmt = con.statement("select * from t");
        auto rows = stmt.query.rows;

        foreach (row; rows) {
            for(int c = 0; c != row.width; ++c) {
                auto field = row[c];
                write(field," ");
            }
            writeln;
        }
    }


    if (false) {
        auto db = createDatabase;
        //auto db =  Database.create();
        //auto db =  DB.create;

        auto con = db.connection("oracle");
        con.query("drop table t");
        con.query("create table t (a varchar(10), b integer, c integer, d date)");
        con.query("insert into t values('one', 2, 3, TO_DATE('2015/02/03', 'yyyy/mm/dd'))");
        auto row = con.query("select * from t").rows.front;
        assert(row[0].option!string == "one");
        assert(row[1].option!int == 2);
    }

    if (false) {
        auto db = createDatabase;
        auto con = db.connection("oracle");
        con.query("drop table t");
        con.query("create table t (a varchar(10), b integer, c integer, d date)");
        con.query("insert into t values('one', 2, 3, TO_DATE('2015/02/03', 'yyyy/mm/dd'))");
        auto row = con.query("select * from t").rows.front;
        assert(row[0].get!string == "one");
        assert(row[1].get!int == 2);
    }

    if (false) {
        // into
        auto db = createDatabase;
        auto con = db.connection("oracle");
        con.query("drop table t");
        con.query("create table t (a varchar(10), b integer, c integer, d date)");
        con.query("insert into t values('one', 2, 3, TO_DATE('2015/02/03', 'yyyy/mm/dd'))");
        string a;
        int b;
        Variant c;
        Date d;
        con.query("select * from t").into(a,b,c,d);
        assert(a == "one");
        assert(b == 2);

        auto v = Variant(234);
        assert(v == 234);

        assert(c == "3"); // fix variant to support string
        assert(d == Date(2015,2,3));
    }

    if (false) {
        alias DB = Database!DefaultPolicy;
        polyTest!DB("oracle");

        if (false) {
            auto db = createDatabase;
            auto con = db.connection("oracle");
            con.query("select * from score").writeRows;
        }

    }
}

void polyTest(DB) (string source) {
    import std.database.poly;
    import std.experimental.logger;
    import std.database.front: Feature;

    registerDatabase!DB("oracle");
    auto polyDB = createDatabase;

    auto db = polyDB.database("oracle");

    log("ConnectionPool: ", db.hasFeature(Feature.ConnectionPool));
    log("OutputArrayBinding: ", db.hasFeature(Feature.OutputArrayBinding));

    auto con = db.connection("oracle");
    auto stmt = con.statement("select * from score");

    stmt.query("joe",20);
    stmt.query();

}

