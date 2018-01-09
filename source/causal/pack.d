module causal.pack;
private static import msgpack;

alias leaking = msgpack.nonPacked;
public enum canpack;
public enum packing;
public enum unpacked;

private bool checkCanPack(T)(T arg) {
    import std.traits: hasMember, hasFunctionAttributes, hasUDA, arity, Unqual, ReturnType;

    bool canPack = true;
    static if(is(Unqual!T == class))
        foreach(m; __traits(allMembers, T)) {
            static if(__traits(compiles, mixin("T."~m))) {
                mixin("alias mSym = T."~m~";");
                static if(hasUDA!(mSym, canpack)) {
                    static assert(
                        hasFunctionAttributes!(mSym, "nothrow"),
                        "the can pack function ["~T.stringof~"."~m~"] has to be nothrow"
                    );

                    static assert(
                        arity!(mSym) == 0,
                        "the can pack function ["~T.stringof~"."~m~"] has to be parameterless"
                    );

                    static assert(
                        is(ReturnType!(mSym) == bool),
                        "the can pack function ["~T.stringof~"."~m~"] has to return bool"
                    );

                    mixin("canPack = arg."~m~"();");
                }
            }

            if(!canPack) break;
        }

    return canPack;
}

private void execFuncs(UDA, T)(T arg) if((is(UDA == packing) || is(UDA == unpacked))) {
    import std.traits: hasMember, hasFunctionAttributes, hasUDA, arity, Unqual;

    static if(is(Unqual!T == class))
        foreach(m; __traits(allMembers, T)) {
            static if(__traits(compiles, mixin("T."~m))) {
                mixin("alias mSym = T."~m~";");
                static if(hasUDA!(mSym, UDA)) {
                    static assert(
                        arity!(mSym) == 0,
                        "the "~UDA.stringof~" function ["~T.stringof~"."~m~"] has to be parameterless"
                    );

                    mixin("arg."~m~"();");
                }
            }
        }
}

private void execFailFuncs(UDA, T)(T arg, Throwable thr) if((is(UDA == packfail))) {
    import std.traits: hasMember, hasFunctionAttributes, hasUDA, arity, Unqual;

    static if(is(Unqual!T == class))
        foreach(m; __traits(allMembers, T)) {
            static if(__traits(compiles, mixin("T."~m))) {
                mixin("alias mSym = T."~m~";");
                static if(hasUDA!(mSym, UDA)) {
                    static assert(
                        hasFunctionAttributes!(mSym, "nothrow"),
                        "the "~UDA.stringof~" function ["~T.stringof~"."~m~"] has to be nothrow"
                    );

                    static assert(
                        arity!(T.error) == 1 && is(Parameters!(T.error)[0] : Throwable),
                        "the "~UDA.stringof~" function ["~T.stringof~"."~m~"] has to take 1 Throwable parameter"
                    );

                    mixin("arg."~m~"();");
                }
            }
        }
}

public ubyte[] pack(T)(ref T arg) {
    import causal.meta: hasId;
    import std.range: empty;
    import std.traits: Unqual;

    if(checkCanPack(arg)) {
        execFuncs!packing(arg);
        auto r = msgpack.pack(arg);
        if(!r.empty) {
            /* packing keeps identity, so if an
            identified piec of data is packed destroy original */
            static if(is(Unqual!T == class)) {
                arg.destroy;
                arg = null;
            }
        }
        return r;
    } return null;
}

public nothrow ubyte[] packNoThrow(T)(ref T arg) {
    try{return arg.pack;}
    catch(Throwable thr) {return null;}
}

public T unpack(T)(in ubyte[] buffer) {
    import std.traits: hasIndirections;

    T r = msgpack.unpack!T(buffer);

    static if(hasIndirections!T)
        auto success = r !is null;
    else
        auto success = r != T.init;

    if(success) // unpack functions are not executed if unpacking failed
        execFuncs!unpacked(r);

    return r;
}

public nothrow T unpackNoThrow(T)(in ubyte[] buffer) {
    try{return buffer.unpack!T;}
    catch(Throwable thr) {return T.init;}
}

unittest {
    long x = 5;
    assert(x.pack.unpack!long == 5, "pack/unpack scalar failed");
}

unittest {
    auto dtor = false;
    class A {
        private import causal.meta: identified;
        mixin identified;

        int x;
        int y;

        @packing nothrow void pre() {
            x = 5;
        }

        @unpacked nothrow void post() {
            y = 8;
        }

        ~this() {
            // only original should do this
            if(this.y == int.init)
                dtor = true;
        }
    }
    auto t = new A;
    auto tb = t;
    auto tn = t.pack.unpack!A;
    assert(t is null, "didn't keep identity");
    assert(dtor, "didn't keep identity");
    assert(tn.x == 5, "@packing failed");
    assert(tn.y == 8, "@unpacked failed");
}

unittest {
    class A {
        @canpack nothrow bool can() {
            return false;
        }
    }
    auto t = new A;
    assert(t.pack is null, "@canpack failed");
}

unittest {
    class A {
        @canpack @property nothrow bool can() {
            return true;
        }
    }
    auto t = new A;
    assert(t.pack !is null, "@canpack failed");
}