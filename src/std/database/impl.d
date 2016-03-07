module std.database.impl;
import std.experimental.logger;
import std.database.exception;
import std.datetime;

// Place for basic DB type templates (need forward bug fixed first)
// and other implementation related stuff

enum ValueType {
    Int,
    String,
    Date,
}

// improve
struct TypeInfo(T:int) {static auto type() {return ValueType.Int;}}
struct TypeInfo(T:string) {static auto type() {return ValueType.String;}}
struct TypeInfo(T:Date) {static auto type() {return ValueType.Date;}}


struct Converter(T) {
    alias Impl = T;
    alias Bind = Impl.Bind;

    static Y convert(Y)(Bind *b) {
        ValueType x = b.type, y = TypeInfo!Y.type;
        if (x == y) return Impl.get!Y(b); // temporary
        auto e = lookup(x,y);
        if (!e) conversionError(x,y);
        Y value;
        e.convert(b,&value);
        return value;
    }

    static Y convertDirect()(Bind *b) {
        assert(b.type == TypeInfo!Y.type);
        return Impl.get!Y(b);
    }

    private:

    struct Elem {
        ValueType from,to;
        void function(void*,void*) convert;
    }

    // only cross converters, todo: all converters
    static Elem[2] converters = [
    {from: ValueType.Int, to: ValueType.String, &generate!(int,string).convert},
    {from: ValueType.String, to: ValueType.Int, &generate!(string,int).convert}
    ];

    static Elem* lookup(ValueType x, ValueType y) {
        // rework into efficient array lookup
        foreach(ref i; converters) {
            if (i.from == x && i.to == y) return &i;
        }
        return null;
    }

    struct generate(X,Y) {
        static void convert(void *x_, void *y_) {
            import std.conv;
            Bind *x = cast(Bind*) x_;
            *cast(Y*) y_ = to!Y(Impl.get!X(x));
        }
    }

    static void conversionError(ValueType x, ValueType y) {
        import std.conv;
        string msg;
        msg ~= "unsupported conversion from: " ~ to!string(x) ~ " to " ~ to!string(y);
        throw new DatabaseException(msg);
    }

}

