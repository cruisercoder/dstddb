module std.database.common;

enum QueryVariableType {
    QuestionMark,
    Dollar,
    Named,
}

// this does not work currently
// there is one with arrays in in forum
// but waiting for better options
/* Support empty Args? */
@nogc pure nothrow auto toInputRange(Args...)() {
    struct Range {
        size_t index;

        bool empty() {return index >= Args.length;}
        void popFront() {++index;}

        import std.traits : CommonType;
        alias E = CommonType!Args;

        E front() {
            final switch (index) {
                /* static */ foreach (i, arg; Args) {
                    case i:
                        writeln("FRONT: ", arg, "INDEX: ", i);
                        return arg;
                }
            }
        }
    }

    return Range();
}

/*
unittest {
    import std.traits;
    import std.range;


    static assert(isInputRange!(ReturnType!(toInputRange!(1))));

    static auto foo(Args...)(Args args) {
        import std.container.array;

        import std.traits : CommonType;
        alias E = CommonType!Args;
        writeln("common:", typeid(E));

        return Array!E(toInputRange!(args));
    }
    auto a = foo(1,2,3);
    //assert(a.length == 3 && a[0] == 1 && a[1] == 2 && a[2] == 3);
    //assert(a.length == 3 && a[0] -);


    for(int i = 0; i != a.length; ++i) {
        writeln("===================HERE: ", a[i]);
    }
}
*/
