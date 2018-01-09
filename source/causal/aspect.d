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
        registerAspect!(typeof(this));
    }

    static if(!is(M==void))
        @leaking M lock;

    this() {
        static if(!is(M==void))
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

public template isVersatile(T) {
    private import causal.pack: leaking;
    private import std.traits;

    // there could be more but it only affects a wrong template
    enum isVersatile =
        isFinalClass!T &&
        hasMember!(T, "aspects") &&
        !hasUDA!(T.aspects, leaking);
}

// note there could be a versatile with permissions get implemented

public mixin template versatile() {
    private import core.sync.rwmutex: ReadWriteMutex;
    private import causal.pack;

    Object[][string] aspects;

    @leaking ReadWriteMutex aspectsLock;

    @leaking nothrow @property size_t length(T)() {
        synchronized(this.aspectsLock.reader)
            return this.aspects[fqn!T].length;
    }

    this() {
        this.aspectsLock = new ReadWriteMutex;
    }

    nothrow void put(T)(T[] a) {
        synchronized(this.aspectsLock.writer)
            this.aspects[fqn!T] = a;
    }

    nothrow T[] get(T)() {
        synchronized(this.aspectsLock.writer)
            return this.aspects[fqn!T];
    }
}