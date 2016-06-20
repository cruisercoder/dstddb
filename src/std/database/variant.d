module std.database.variant;
import std.variant;
import std.meta;
import std.exception;
import std.datetime;

import std.experimental.logger;

class UnpackException : Exception {
    this(Variant v) {
        super("can't convert variant: (value: " ~ v.toString() ~ ", type: " ~ v.type.toString() ~")");
    }
}

static void unpackVariants(alias F, int i=0, A...)(A a) {
    //alias Types = AliasSeq!(byte, ubyte, string, char, dchar, int, uint, long, ulong);
    alias Types = AliasSeq!(int, string, Date);

    static void call(int i, T, A...)(T v, A a) {
        unpackVariants!(F,i+1)(a[0..i], v, a[(i+1)..$]);
    }

    static if (i == a.length) {
        F(a);
    } else {
        //log("type: ", a[i].type);
        foreach(T; Types) {
            //log("--TYPE: ", typeid(T));
            //if (a[i].type == typeid(T))
            if (a[i].convertsTo!T) {
                call!i(a[i].get!T,a);
                return;
            }
        }
        throw new UnpackException(a[i]);
    }
}

unittest {
    import std.array;
    import std.algorithm.iteration;
    import std.conv : text;

    //joiner(["a","b"],",");
    //join([Variant(1), Variant(2)],Variant(","));

    static void F(A...)(A a) {log("unpacked: ", a);}

    unpackVariants!F(Variant(1), Variant(2));
    unpackVariants!F(Variant(1), Variant("abc"));
    unpackVariants!F(Variant(1), Variant("abc"), Variant(Date(2015,1,1)));
}

