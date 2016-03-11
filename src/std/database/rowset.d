module std.database.rowset;
import std.container.array;

// experimental detached rowset

struct RowSet {
    private struct RowData {
        int[3] data;
    }
    private alias Data = Array!RowData;

    struct Row {
        private RowSet* rowSet;
        private RowData* data;
        this(RowSet* rs, RowData *d) {rowSet = rs; data = d;}
        int columns() {return rowSet.columns();}
        auto opIndex(size_t idx) {return Value(&data.data[idx]);}
    }

    struct Value {
        private void* data;
        this(void *d) {data = d;}
        auto as(T:int)() {return *cast(int*) data;}
    }

    struct Range {
        alias Rng = Data.Range;
        private RowSet* rowSet;
        private Rng rng;
        this(ref RowSet rs, Rng r) {rowSet = &rs; rng = r;}
        bool empty() {return rng.empty();}
        Row front() {return Row(rowSet,&rng.front());}
        void popFront() {rng.popFront();}
    }


    this(R) (R result, size_t capacity = 0) {
        data.reserve(capacity);
        foreach (r; result[]) {
            data ~= RowData();
            auto d = &data.back();
            for(int c = 0; c != r.columns; ++c) d.data[c] = r[c].as!int;
        }
    }

    int columns() {return cast(int) data.length;}
    auto opSlice() {return Range(this,data[]);}

    private Array!RowData data;
}



