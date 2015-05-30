module std.database.util;

import std.stdio;
import std.traits;

// expand out for different cases
// execute: T: Connection,Database
void execute(T) (T t, string sql) {
    // check for bind vars with extra parameter? (possible ambiguity)
    static if (hasMember!(T, "Connection")) { // improve 
        t.connection().statement(sql);
    } else {
        auto stmt = T.Statement(t,sql);
    }
}

void create_simple_table(Db) (Db db, string table) {
    import std.conv;
    Db.Connection con = db.connection();
    con.execute("create table " ~ table ~ "(a integer, b integer);");
    for(int i = 0; i != 10; ++i) {
        con.execute("insert into " ~ table ~ " values(1," ~ to!string(i) ~ ");");
    }
}

void create_score_table(Db) (Db db, string table, bool data = true) {
    import std.conv;
    Db.Connection con = db.connection();
    auto names = ["Knuth", "Hopper", "Dijkstra"];
    auto scores = [62, 48, 84];
    con.execute("drop table if exists " ~ table ~ ";");
    con.execute("create table " ~ table ~ "(name char(10), score integer);");
    if (!data) return;
    for(int i = 0; i != names.length; ++i) {
        con.execute(
                "insert into " ~ table ~ " values(" ~
                "\"" ~ names[i] ~ "\"" ~ "," ~ to!string(scores[i]) ~ ");");
    }
}

// ref Range range doesn't work with fluent?
void write_result(Range) (Range range) {
    static char s[100] = '-';
    int w = 80;
    writeln(s[0..w-1]);
    foreach (Range.Row r; range) {
        for(size_t c = 0; c != r.columns; ++c) {
            if (c) write(", ");
            write("", r[c]);
        }
        writeln();
    }
    writeln(s[0..w-1]);
}

