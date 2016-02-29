module std.database.uri;

import std.stdio;
import std.traits;
import std.string;

struct URI {
    string protocol,host,path,qs;
    string[][string] query;

    string opIndex(string name) const {
        auto x = name in query;
        return (x is null ? "" : (*x)[$-1]);
    }
}

URI toURI(string str) {
    // example: protocol://host/path?a=1&b=2

    void error(string msg) {throw new Exception(msg ~ ", URI: " ~ str);}

    URI uri;
    auto s = str[0..$];
    auto i = s.indexOf(':');
    uri.protocol = s[0 .. i];
    ++i;
    if (!(i+2 <= s.length && s[i] == '/' && s[i+1] == '/')) error("missing //");
    i += 2;
    s = s[i .. $];

    auto q = s.indexOf('?');
    i = s.indexOf('/');
    uri.host = s[0 .. (i==-1 ? s.length : i)];
    if (i != -1) uri.path = s[i .. (q==-1 ? s.length : q)];

    if (q == -1) return uri;
    uri.qs = s[q+1..$];

    foreach (e; split(uri.qs, "&")) {
        auto j = e.indexOf('=');
        if (j==-1) error("missing =");
        auto n = e[0..j], v = e[j+1..$];
        uri.query[n] ~= v; //needs url decoding
    }

    return uri;
}


