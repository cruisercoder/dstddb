module std.database.exception;
import std.exception;

struct DatabaseError {
    string message;
}

class DatabaseException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }

    this(ref DatabaseError error, string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg ~ ": " ~ error.message, file, line);
    }
}

class ConnectionException : DatabaseException {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

