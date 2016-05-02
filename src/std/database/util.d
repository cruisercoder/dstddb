module std.database.util;

import std.database.common;
import std.stdio;
import std.traits;
import std.string;

/*
   // trying to overload write/print
void writeRows(T) (T t)
    if (hasMember!(T, "rows") || hasMember!(T, "rowSetTag")) {write(t);}
*/

// should return object being written to

void writeRows(T) (T t) 
    if (hasMember!(T, "rows")) {
        t.rows.writeRows;
    }

void writeRows(T) (T t) 
    if (hasMember!(T, "rowSetTag")) {
        static char[100] s = '-';
        int w = 80;
        writeln(s[0..w-1]);
        foreach (r; t) {
            for(int c = 0; c != r.width; ++c) {
                if (c) write(", ");
                write("", r[c].chars); //chars sitll a problem
            }
            writeln();
        }
        writeln(s[0..w-1]);
    }


struct QueryVariable(QueryVariableType t : QueryVariableType.Dollar) {
    import std.conv;
    private int n = 1;
    auto front() {return "$" ~ to!string(n);}
    auto popFront() {++n;}
    auto next() {auto v = front(); popFront(); return v;}
}

struct QueryVariable(QueryVariableType t : QueryVariableType.QuestionMark) {
    auto front() {return "?";}
    auto next() {return front();}
}

