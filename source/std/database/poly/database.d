module std.database.poly.database;

import std.string;
import std.c.stdlib;

public import std.database.exception;

import std.stdio;
import std.typecons;

struct Database {

    // public

    static void register(Database) (string name = "") {
        name = "name"; // synth name
        writeln(
                "poly register: ",
                "name: ", name, ", "
                "type: ", typeid(Database),
                "index: ", databases.length);
        databases ~= Info(name, CreateGen!Database.dispatch);
    }

    this(string arg) {
        foreach(ref d; databases) {
            d.data = d.dispatch.create();
        }
    }

    ~this() {
        foreach(ref d; databases) {
            d.dispatch.destroy(d.data);
        }
    }

    // private

    private struct Dispatch {
        void* function() create;
        void function(void*) destroy;
    }

    private struct Info {
        string name;
        Dispatch dispatch;
        void *data;
    }

    private static Info[] databases;

    private template CreateGen(Database) {
        static void* create() {
            return new Database("");
        }

        static void destroy(void *data) {
            //delete cast(Database*) data; // ??
            Database *p = cast(Database*) data;
            delete p;
        }

        static Dispatch dispatch = {
            &create,
            &destroy
        };
    }

}

