module std.database.util;

import std.stdio;
import std.traits;

// experimental, what for?
//D database(D) (string defaultURI) {
//return D.create(defaultURI);
//}

// experimental: avoiding member factory functions, but polluting names
// good or bad?
// save these

/*
   auto statement(C) (C con, string sql) {
   return C.Statement(con, sql);
   }

   auto statement(C, T...) (C con, string sql, T args) {
   return C.Statement(con, sql, args);
   }
 */

// expand out for different cases
// execute: T: Connection,Database

/*
   void execute(T) (T t, string sql) {
// check for bind vars with extra parameter? (possible ambiguity)
static if (hasMember!(T, "Connection")) { // improve 
// t is Database
//t.connection().statement(sql);
auto stmt = T.Statement(t.connection(), sql);
} else {
// t is Connection
auto stmt = t.statement(sql);
}
}

void execute(T, V...) (T t, string sql, V v) {
// check for bind vars with extra parameter? (possible ambiguity)
static if (hasMember!(T, "Connection")) { // improve 
// t is Database
auto stmt = T.Statement(t.connection(), sql, v);
} else {
// t is Connection
auto stmt = T.Statement(t, sql, v);
}
}
 */

// ref Range range doesn't work with fluent?

void writeResult(R) (R result) {
    writeResultRange(result.range());
}

void writeResultRange(R) (R range) {
    static char[100] s = '-';
    int w = 80;
    writeln(s[0..w-1]);
    //foreach (R.Row r; range)
    for (auto r = range.front(); !range.empty(); range.popFront()) {
        for(size_t c = 0; c != r.columns; ++c) {
            if (c) write(", ");
            write("", r[c].chars()); // why fail when not .chars()?
        }
        writeln();
    }
    writeln(s[0..w-1]);
}

