module std.database.test;
import std.stdio;
import std.database.uri;

unittest {
    URI uri = toURI("protocol://host");
    assert(uri.protocol == "protocol");
    assert(uri.host == "host");
    assert(uri.path == "");
}

unittest {
    URI uri = toURI("protocol://host/path");
    assert(uri.protocol == "protocol");
    assert(uri.host == "host");
    assert(uri.path == "/path");
}

unittest {
    URI uri = toURI("protocol://host/path?a=1&b=2");
    assert(uri.protocol == "protocol");
    assert(uri.host == "host");
    assert(uri.path == "/path");
    assert(uri.qs == "a=1&b=2");
    assert(uri["a"] == "1");
    assert(uri["b"] == "2");
}

unittest {
    URI uri = toURI("file:///filename.ext");
    assert(uri.host == "");
    assert(uri.path == "/filename.ext");
}

