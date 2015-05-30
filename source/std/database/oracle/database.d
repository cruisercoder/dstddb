module std.database.oracle.database;
//pragma(lib, "oci");

import std.string;
import std.c.stdlib;

public import std.database.oracle.bindings;
public import std.database.exception;

import std.stdio;
import std.typecons;

struct Database {

    private struct Payload {
        string defaultURI;
        OCIEnv* env_;

        this(string defaultURI_) {
            defaultURI = defaultURI_;
            writeln("oracle: opening database");
            ub4 mode = OCI_THREADED | OCI_OBJECT;
            sword status = OCIEnvCreate(&env_, mode, null, null, null ,null, null);
        }

        ~this() {
            writeln("oracle: closing database");
            if (env_) {
                sword status = OCIHandleFree(env_, OCI_HTYPE_ENV);
                env_ = null;
            } else {
                writeln("nothing");
            }
        }

        this(this) { assert(false); }
        void opAssign(Database.Payload rhs) { assert(false); }
    }

    private alias RefCounted!(Payload, RefCountedAutoInitialize.no) Data;
    private Data data_;

    this(string defaultURI) {
        data_ = Data(defaultURI);
    }

}

