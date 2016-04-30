module std.database.rowset;
import std.database.front;
import std.datetime;
import std.container.array;

// experimental detached rowset

/*
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
        auto opIndex(size_t idx) {return Value(rowSet,Bind(ValueType.Int, &data.data[idx]));}
    }

    struct Bind {
        this(ValueType t, void* d) {type = t; data = d;}
        ValueType type;
        void *data;
    }

    struct Driver {
        alias Result = .RowSet;
        alias Bind = RowSet.Bind;
    }
    struct Policy {}

    alias Converter = .Converter!(Driver,Policy);


    struct TypeInfo(T:int) {static int type() {return ValueType.Int;}}
    struct TypeInfo(T:string) {static int type() {return ValueType.String;}}
    struct TypeInfo(T:Date) {static int type() {return ValueType.Date;}}

    static auto get(X:string)(Bind *b) {return "";}
    static auto get(X:int)(Bind *b) {return *cast(int*) b;}
    static auto get(X:Date)(Bind *b) {return Date(2016,1,1);}

    struct Value {
        RowSet* rowSet;
        Bind bind;
        private void* data;
        this(RowSet *r, Bind b) {
            rowSet = r;
            bind = b;
        }
        //auto as(T:int)() {return *cast(int*) bind.data;}
        auto as(T:int)() {return Converter.convert!T(rowSet,&bind);}
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

*/

