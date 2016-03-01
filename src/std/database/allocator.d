module std.database.allocator;
import std.experimental.allocator.common;

struct MyMallocator {
    enum uint alignment = platformAlignment;

    @trusted @nogc nothrow
    void[] allocate(size_t bytes) {
        import core.stdc.stdlib : malloc;
        if (!bytes) return null;
        auto p = malloc(bytes);
        return p ? p[0 .. bytes] : null;
    }

    /// Ditto
    @system @nogc nothrow
    bool deallocate(void[] b) {
        import core.stdc.stdlib : free;
        free(b.ptr);
        return true;
    }

}

