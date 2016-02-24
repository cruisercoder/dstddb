module std.database.pool;
import std.container.array;

struct Pool(T) {
    alias Resource = T;

    struct Elem {
        Resource resource;
    }

    Array!Elem pool;
}

