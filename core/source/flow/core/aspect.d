module flow.core.aspect;
public import flow.core.pack : leaking, pack, unpack;

private shared TypeInfo[string] __aspects;

public template isAspect(T) {
    private import flow.core.meta;

    enum isAspect =
        __hasTypeField!T &&
        __isTypeType!T &&
        __checkTypeAttributes!T;
}

public void registerAspect(T)()
if(isAspect!T) {
    import flow.core.traits: fqn, as;

    synchronized __aspects[fqn!T] = typeid(T).as!(shared(TypeInfo));
}

public mixin template aspect() {
    private import flow.core.meta;
    private import flow.core.pack;
    private import flow.core.traits;
    private import std.traits;

    alias T = typeof(this);
    static assert(isFinalClass!T, "aspect "~fqn!T~" has to be a final class");
    static assert(is(typeof(super) == Object), "aspect "~fqn!T~" has to derrive from class Object");

    mixin typed;
    mixin packable;

    shared static this() {
        registerAspect!T;
    }
}

unittest {
    //static assert(__traits(compiles, {class B{mixin aspect;}}), "????");
}

version(unittest) {
    struct X {
        int y;
    }

    final class A {
        import core.sync.mutex;
        mixin aspect;

        private @leaking Mutex lock;

        X x;        
    }
}

unittest {
    auto a = new A;
    a.x.y = 5;

    assert(a.pack.unpack!A.x.y == 5, "pack/unpack of aspect failed");
}
