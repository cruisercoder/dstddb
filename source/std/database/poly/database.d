module std.database.poly.database;

import std.string;
import std.c.stdlib;

public import std.database.exception;

import std.stdio;
import std.typecons;

struct Database {

    private alias void* function() Create;

    private struct Info {
        string name;
        Create create;
    }

    private Info[] databases;

    private template CreateGen(Database) {
        static void* create() {
            return new Database("");
        }
    }


    this(string arg) {
    }

    void register(Database) (string name = "") {
        name = "name"; // synth name
        writeln(
                "poly register: ",
                "name: ", name, ", "
                "type: ", typeid(Database),
                "index: ", databases.length);
        databases ~= Info(name, &CreateGen!Database.create);
    }

}

