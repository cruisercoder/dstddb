module std.database.option;

struct Option(T) {
    private T _value;
    private bool _isNull = true;

    this(inout T value) inout {
        _value = value;
        _isNull = false;
    }

    template toString() {
        import std.format : FormatSpec, formatValue;
        // Needs to be a template because of DMD @@BUG@@ 13737.
        void toString()(scope void delegate(const(char)[]) sink, FormatSpec!char fmt) {
            if (isNull)
            {
                sink.formatValue("Nullable.null", fmt);
            }
            else
            {
                sink.formatValue(_value, fmt);
            }
        }

        // Issue 14940
        void toString()(scope void delegate(const(char)[]) @safe sink, FormatSpec!char fmt) {
            if (isNull)
            {
                sink.formatValue("Nullable.null", fmt);
            }
            else
            {
                sink.formatValue(_value, fmt);
            }
        }
    }

    @property bool isNull() const @safe pure nothrow {
        return _isNull;
    }

    void nullify()() {
        .destroy(_value);
        _isNull = true;
    }

    void opAssign()(T value) {
        _value = value;
        _isNull = false;
    }

    @property ref inout(T) get() inout @safe pure nothrow {
        enum message = "Called `get' on null Nullable!" ~ T.stringof ~ ".";
        assert(!isNull, message);
        return _value;
    }

    @property ref inout(T) front() inout @safe pure nothrow {return get;}
    @property bool empty() const @safe pure nothrow {return isNull;}
    @property void popFront() @safe pure nothrow {nullify;}

    //Implicitly converts to T: must not be in the null state.
    alias get this;


}

