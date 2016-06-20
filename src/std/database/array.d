module std.database.array;
import std.traits;

// not usable yet

struct S {
    int a, b;
}

auto toStaticArray(alias array)()
{
    struct S { int a, b; }

    immutable tab = {
        static enum S[] s = array;
        return cast(typeof(s[0])[s.length])s;
    }();
    return tab;
}

//enum a = toStaticArray!([{1,2},{3,4}]);


