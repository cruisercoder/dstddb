module std.database.pool;
import std.container.array;
import std.experimental.logger;
import std.database.allocator;
import core.thread;

// not really a pool yet

struct Pool(T) {
    alias Allocator = MyMallocator;
    alias Res = T;

    struct Factory(T) {
        Allocator allocator;

        this(Allocator allocator_ ) {
            allocator = allocator_;
        }

        auto acquire(A...)(auto ref A args) {
            import std.conv : emplace;
            import core.memory : GC;
            void[] data = allocator.allocate(T.sizeof);
            GC.addRange(data.ptr, T.sizeof);
            auto ptr = cast(T*) data.ptr;
            emplace(ptr, args);
            return ptr;
        }

        void release(T* ptr) {
            import core.memory : GC;
            .destroy(*ptr);
            GC.removeRange(ptr);
            allocator.deallocate(ptr[0..T.sizeof]);
        }
    }

    private Array!Resource data;
    private Factory!Res factory_;
    private bool enable_;
    private int nextId_;

    this(bool enable) {
        factory_ = Factory!Res(Allocator());
        enable_ = enable;
    }

    ~this() {
        if (!data.empty()) {
            factory_.release(data.back.resource);
        }
    }

    struct Resource {
        int id;
        ThreadID tid;
        Res* resource;
        this(int id_, ThreadID tid_, Res* resource_) {
            id = id_;
            tid = tid_;
            resource = resource_;
        }
    }

    auto acquire(A...)(auto ref A args) {
        ThreadID tid = Thread.getThis.id;
        if (!enable_) return Resource(0, tid, factory_.acquire(args));
        if (!data.empty()) {
            //log("======= pool: return back");
            return Resource(0, tid, data.back.resource);
        }
        //log("========== pool: create: ",tid);
        data ~= Resource(0, tid, factory_.acquire(args));
        return data.back();
    }

    void release(ref Resource resource) {
        //log("========== pool: release");
        if (!enable_) factory_.release(resource.resource);
        // return to pool
    }

}

/*
   Scoped resource
   Useful for RefCounted
 */

struct ScopedResource(T) {
    alias Pool = T;
    alias Resource = Pool.Resource;

    Pool* pool;
    Resource resource;
    this(ref Pool pool_, Resource resource_) {
        pool = &pool_;
        resource = resource_;
    }
    ~this() {
        pool.release(resource);
    }
}

