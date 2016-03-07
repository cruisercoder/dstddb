module std.database.util;

import std.database.common;
import std.stdio;
import std.traits;
import std.string;

void writeResult(T) (T t) {
    static if (hasMember!(T, "opSlice")) { // improve
        writeResultRange(t[]);
    } else {
        writeResultRange(t);
    }
}

private void writeResultRange(T) (T range) {
    static char[100] s = '-';
    int w = 80;
    writeln(s[0..w-1]);
    foreach (r; range) {
        for(int c = 0; c != r.columns; ++c) {
            if (c) write(", ");
            write("", r[c].chars()); // why fail when not .chars()?
        }
        writeln();
    }
    writeln(s[0..w-1]);
}

struct QueryVariable(QueryVariableType t : QueryVariableType.Dollar) {
    private int n = 1;
    auto front() {return "$" ~ std.conv.to!string(n);}
    auto popFront() {++n;}
    auto next() {auto v = front(); popFront(); return v;}
}

struct QueryVariable(QueryVariableType t : QueryVariableType.QuestionMark) {
    auto front() {return "?";}
    auto next() {return front();}
}

