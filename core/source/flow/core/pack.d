module flow.core.pack;
private static import msgpack;

alias leaking = msgpack.nonPacked;
public enum canpack;
public enum prepack;
public enum postpack;

private bool checkCanPack(T)(T arg) {
    bool canPack = true;
    import std.traits: hasMember, hasFunctionAttributes, hasUDA, arity, Unqual, ReturnType;
    static if(is(Unqual!T == class) || is(Unqual!T == struct))
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

private void execPackFuncs(UDA, T)(T arg) if(is(UDA == prepack) || is(UDA == postpack)) {
    import std.traits: hasMember, hasFunctionAttributes, hasUDA, arity, Unqual;
    static if(is(Unqual!T == class) || is(Unqual!T == struct))
        foreach(m; __traits(allMembers, T)) {
            static if(__traits(compiles, mixin("T."~m))) {
                mixin("alias mSym = T."~m~";");
                static if(hasUDA!(mSym, UDA)) {
                    static assert(
                        hasFunctionAttributes!(mSym, "nothrow"),
                        "the pre/post pack function ["~T.stringof~"."~m~"] has to be nothrow"
                    );

                    static assert(
                        arity!(mSym) == 0,
                        "the pre/post pack function ["~T.stringof~"."~m~"] has to be parameterless"
                    );

                    mixin("arg."~m~"();");
                }
            }
        }
}

public ubyte[] pack(T)(T arg) {  
    if(checkCanPack(arg)) {  
        execPackFuncs!prepack(arg);
        auto r = msgpack.pack(arg);
        execPackFuncs!postpack(arg); // TODO post should get a bool indicating if packing was successful
        return r;
    } return null;
}

public nothrow ubyte[] packNoThrow(T)(T arg) {
    try{return arg.pack;}
    catch(Throwable thr) {return null;}
}

public T unpack(T)(in ubyte[] buffer) {
    return msgpack.unpack!T(buffer);
}

public nothrow T unpackNoThrow(T)(in ubyte[] buffer) {
    try{return buffer.unpack!T;}
    catch(Throwable thr) {return T.init;}
}

public void registerClass(T)() {
    msgpack.registerClass!T;
}

public mixin template packable() {
    alias T = typeof(this);

    static if(is(Unqual!T == class)) {
        shared static this() {
            import flow.core.pack: registerClass;
            registerClass!T;
        }
    }
}

unittest {
    long x = 5;
    assert(x.pack.unpack!long == 5, "pack/unpack scalar failed");

    class A {
        int x;

        @prepack nothrow void pre() {
            x = 5;
        }

        @postpack nothrow void post() {
            x = 3;
        }
    }
    auto a = new A;
    assert(a.pack.unpack!A.x == 5, "@prepack failed");
    assert(a.x == 3, "@postpack failed");

    class B {
        @canpack nothrow bool can() {
            return false;
        }
    }
    auto b = new B;
    assert(b.pack is null, "@canpack failed");

    class C {
        @canpack @property nothrow bool can() {
            return true;
        }
    }
    auto c = new C;
    assert(c.pack !is null, "@canpack failed");
}