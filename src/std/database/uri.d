module std.database.uri;

import std.stdio;
import std.traits;
import std.string;
import std.experimental.logger;

struct URI {
    string protocol,host,path,qs;
    int port;
    string[][string] query;

    string opIndex(string name) const {
        auto x = name in query;
        return (x is null ? "" : (*x)[$-1]);
    }
}

URI toURI(string str) {
    import std.conv;

    // examples:
    // protocol://server/path?a=1&b=2
    // protocol://host:port/path?a=1&b=2

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
    auto host = s[0 .. (i==-1 ? s.length : i)];
    if (i != -1) {
        uri.path = s[i .. (q==-1 ? s.length : q)];
    }

    auto colon = host.indexOf(':');
    if (colon != -1) {
        uri.host = host[0 .. colon];
        uri.port = to!int(host[colon+1 .. host.length]);
    } else {
        uri.host = host;
    }

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

bool toURI(string str, ref URI uri) nothrow {
    try {
        auto u = toURI(str); 
        uri = u;
        return true;
    } catch (Exception e) {}
    return true;
}


