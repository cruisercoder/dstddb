module std.database.pool;
import std.container.array;
import std.experimental.logger;

// not really a pool yet

struct Pool(D,R) {
    alias Database = D;
    alias Resource = R;
    private Database db_;
    private Array!Elem data;

    this(Database db) {
        db_ = db;
    }

    struct Elem {
        Resource resource;
        this(Resource r) {resource = r;}
    }

    auto get(string source = "") {
        if (!pool.empty()) {
            log("pool: return back");
            return pool.back();
        }
        log("pool: create");
        Resource r = db.connection(source);
        data ~= Elem(r);
        return r;
    }

}

