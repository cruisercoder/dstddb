module std.database.test;
import std.stdio;
import std.database.uri;
import std.experimental.logger;

unittest {
    URI uri = toURI("protocol://host");
    assert(uri.protocol == "protocol");
    assert(uri.host == "host");
    log(uri.path);
    assert(uri.path == "");
}

unittest {
    URI uri = toURI("protocol://host:1234/");
    assert(uri.protocol == "protocol");
    assert(uri.host == "host");
    assert(uri.port == 1234);
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

