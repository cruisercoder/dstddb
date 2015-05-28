module std.database.util;

import std.stdio;

void create_simple_table(Con) (Con con, string table) {
    import std.conv;
    con.execute("create table " ~ table ~ "(a integer, b integer);");
    for(int i = 0; i != 10; ++i) {
        con.execute("insert into " ~ table ~ " values(1," ~ to!string(i) ~ ");");
    }
}

void create_score_table(Con) (Con con, string table) {
    import std.conv;
    auto names = ["Knuth", "Hopper", "Dijkstra"];
    auto scores = [62, 48, 84];
    con.execute("drop table if exists " ~ table ~ ";");
    con.execute("create table " ~ table ~ "(name char(10), score integer);");
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

