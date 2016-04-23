module std.database.resolver;

import std.database.exception;
import std.database.uri;
import std.database.source;

import std.process;
import std.file;
import std.path;
import std.json;
import std.conv;
import std.stdio;
import std.string;


Source resolve(string name) {
    if (name.length == 0) throw new DatabaseException("resolver: name empty");

    Source source;

    // first, hacky url check
    if (name.indexOf('/') != -1) {
        URI uri = toURI(name);
        source.type = uri.protocol; 
        if (uri.port != 0) {
            source.host = uri.host;
            source.port = uri.port;
        } else {
            source.server = uri.host;
        }
        source.path = uri.path.startsWith('/') ? uri.path[1..$] : uri.path;
        source.database = source.path; 
        source.username = uri["username"];
        source.password = uri["password"];
        return source;
    }

    auto home = environment["HOME"];

    string file = home ~ "/db.json";
    auto bytes = read(file);
    auto str = to!string(bytes);
    auto doc = parseJSON(str);

    JSONValue[] databases = doc["databases"].array;
    foreach(e; databases) {
        if (e["name"].str != name) continue;
        source.type = e["type"].str;
        source.server = e["server"].str;
        //source.path = e["path"].str; // fix
        source.database = e["database"].str;
        source.username = e["username"].str;
        source.password = e["password"].str;
        return source;
    }

    throw new DatabaseException("couldn't find source name: " ~ name);
}

