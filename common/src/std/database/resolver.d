module std.database.resolver;

import std.database.exception;

import std.process;
import std.file;
import std.stream;
import std.path;
import std.json;
import std.conv;
import std.stdio;

struct Source {
    string type;
    string server;
    string database;
    string username;
    string password;
}

Source resolve(string name) {
    Source source;
    auto home = environment["HOME"];
    writeln("HOME: ", home);

    string file = home ~ "/db.json";
    auto bytes = read(file);
    auto str = to!string(bytes);
    auto doc = parseJSON(str);

    JSONValue[] databases = doc["databases"].array;
    foreach(e; databases) {
        if (e["name"].str != name) continue;
        source.type = e["type"].str;
        source.server = e["server"].str;
        source.database = e["database"].str;
        source.username = e["username"].str;
        source.password = e["password"].str;
        return source;
    }

    throw new DatabaseException("couldn't find source name: " ~ name);
}

