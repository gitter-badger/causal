module causal.aspect;
public import causal.pack: leaking, packNoThrow, unpackNoThrow;
private import core.sync.condition: Condition;
private import core.sync.mutex: Mutex;
private import core.sync.rwmutex: ReadWriteMutex;
private import core.sync.semaphore: Semaphore;
private shared TypeInfo[string] __aspects;
private shared nothrow Object function(ubyte[])[string] __aspectGetter;

public template isAspect(T) {
    private import std.traits;

    enum isAspect = isFinalClass!T;
}

public nothrow Object getAspect(string aspect, ubyte[] pkg) {
    return __aspectGetter[aspect](pkg);
}

private nothrow Object getAspect(T)(ubyte[] pkg)
if(isAspect!T) {
        return pkg.unpackNoThrow!T;
}

public nothrow void registerAspect(T)()
if(isAspect!T) {
    import causal.traits: fqn, as;

    synchronized {
        __aspects[fqn!T] = typeid(T).as!(shared(TypeInfo));
        __aspectGetter[fqn!T] = &getAspect!T;
    }
}

public mixin template aspect(M=void)
if(is(M==void) || is(M:Condition) || is(M:ReadWriteMutex) || is(M:Mutex) || is(M:Semaphore)) {
    private import causal.meta;
    private import causal.pack;
    private import causal.traits;
    private import std.traits;

    alias T = typeof(this);
    static assert(isFinalClass!T, "aspect "~fqn!T~" has to be a final class");
    static assert(is(typeof(super) == Object), "aspect "~fqn!T~" has to derrive from class Object");

    shared static this() {
        import causal.aspect : registerAspect;
        registerAspect!T;
    }

    static if(!is(M==void))
        @leaking M lock;

    mixin typed;

    static if(!is(M==void))
        this() {
            this.lock = new M;
        }
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
    import causal.pack: pack, unpack;
    auto a = new A;
    a.x.y = 5;

    assert(a.pack.unpack!A.x.y == 5, "pack/unpack of aspect failed");
}