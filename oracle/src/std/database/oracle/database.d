module std.database.oracle.database;
pragma(lib, "occi");
pragma(lib, "clintsh");

import std.string;
import std.c.stdlib;

public import std.database.oracle.bindings;
public import std.database.exception;
import std.container.array;
import std.experimental.logger;

import std.stdio;
import std.typecons;

void check(string msg, sword status) {
    log(msg, ":", status);
    if (status == OCI_SUCCESS) return;
    throw new DatabaseException("OCI error: " ~ msg);
}

struct Database {

    static Database create(string defaultURI) {
        return Database(defaultURI);
    }

    private struct Payload {
        string defaultURI;
        OCIEnv* env;
        OCIError *error;

        this(string defaultURI_) {
            defaultURI = defaultURI_;
            writeln("oracle: opening database");
            ub4 mode = OCI_THREADED | OCI_OBJECT;

            check("OCIEnvCreate", OCIEnvCreate(
                        &env,
                        mode,
                        null,
                        null,
                        null,
                        null,
                        0,
                        null));

            check("OCIHandleAlloc", OCIHandleAlloc(
                        env, 
                        cast(void**) &error,
                        OCI_HTYPE_ERROR,
                        0,
                        null));
        }

        ~this() {
            writeln("oracle: closing database");
            if (env) {
                sword status = OCIHandleFree(env, OCI_HTYPE_ENV);
                env = null;
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

