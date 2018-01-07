module flow.core.tick;
public import flow.core.log: LL;
public import flow.core.pack: leaking, packNoThrow, unpackNoThrow;
private import flow.core.proc: Job;
private import std.uuid: UUID;

private shared TypeInfo[string] __ticks;
private shared nothrow Job function(UUID, Object[string], UUID, ubyte[])[string] __tickGetter;

public template __hasRunFunc(T) {
    private import std.traits : hasMember, ReturnType, Parameters, arity;
    enum __hasRunFunc =
        hasMember!(T, "run") &&
        is(ReturnType!(T.run) == void) && 
        arity!(T.run) == 0;
}

public template __hasErrorFunc(T) {
    private import std.traits : hasMember, ReturnType, Parameters, arity, hasFunctionAttributes;
    enum __hasErrorFunc =
        !hasMember!(T, "error") || (
            hasMember!(T, "error") &&
            is(ReturnType!(T.error) == void) &&
            (arity!(T.error) == 1 && is(Parameters!(T.error)[0] : Throwable)) &&
            hasFunctionAttributes!(T.error, "nothrow")
        );
}

public template __hasAllowFunc(T) {
    private import std.traits : hasMember, ReturnType, Parameters, arity, hasFunctionAttributes;
    enum __hasErrorFunc =
        !hasMember!(T, "allow") || (
            hasMember!(T, "allow") &&
            is(ReturnType!(T.allow) == bool) &&
            arity!(T.run) == 0 &&
            hasFunctionAttributes!(T.allow, "nothrow")
        );
}

public template isTick(T) {
    private import flow.core.meta;

    enum isTick =
        __hasTypeField!T &&
        __isTypeType!T &&
        __checkTypeAttributes!T &&
        __hasRunFunc!T;
}

private nothrow T getTick(T)(UUID entity, Object[string] aspects, UUID branch, ubyte[] pkg)
if(isTick!T) {
    import std.uuid: UUID, randomUUID;

    auto t = T(a);
    t.entity = entity;
    t.aspects = aspects;
    
    // if there was no branch given, start one
    t.branch = branch != UUID.init ? branch : randomUUID;
    static if(!is(D==void))
        t.data = pkg.unpackNoThrow!D;
    return t.getJob;
}

public nothrow Job getJob(T)(T t)
if(isTick!T) {
    return t.allowed ? Job(&t.run, &t.error, t.stdTime) : Job.init;
}

public nothrow Job getJob(string tick, UUID entity, Object[string] aspects, UUID branch, ubyte[] pkg) {
    return __tickGetter[tick](entity, branch, aspects, pkg);
}

public nothrow void registerTick(T, D)()
if(isTick!T) {
    import flow.core.traits: fqn, as;
    import std.uuid : UUID;

    synchronized {
        __ticks[fqn!T] = typeid(T).as!(shared(TypeInfo));
        __tickGetter[fqn!T] = &getTick!T;
    }
}

public mixin template tick(D=void)
if(is(D==void) || __traits(compiles, pack!D)) {
    private import flow.core.aspect : isAspect;
    private import flow.core.log : Log;
    private import flow.core.meta : typed;
    private import flow.core.pack : packable;
    private import flow.core.traits : fqn;
    private import std.traits : Unqual, hasMember;
    private import std.uuid : UUID;

    alias T = typeof(this);

    static if(!hasMember!(T, "error")) {
        nothrow void error(Throwable thr) {
            log(LL.Warning, thr);
        }
    }

    static if(!hasMember!(T, "allow")) {
        nothrow bool allow() {
            return true;
        }
    }

    static assert(is(Unqual!T == struct), "tick ["~fqn!T~"] has to be a struct");
    static assert(__hasRunFunc!T, "tick ["~fqn!T~"] has no qualified run function
        a tick's run handler has to be parameterless
    ");
    static assert(__hasErrorFunc!T, "tick ["~fqn!T~"] has no qualified error handler
        required:
            nothrow void error(Throwable thr) {}
        or when nothing is given, it emits:
            nothrow void error(Throwable thr) {
                log(LL.Warning, thr);
            }
    ");

    mixin typed;
    mixin packable;

    UUID entity;
    Object[string] aspects;
    nothrow @property T aspect(T)() if(isAspect!T) {
        if(fqn!T in this.aspects) {
            return this.aspects[fqn!T].as!T;
        } else return null;
    }

    UUID branch;
    static if(!is(D==void))
        D data;
    long stdTime;

    private nothrow void log(LL level, Throwable thr = null) {
        Log.msg(LL.Warning, "tick(\""~fqn!T~"\")", thr);
    }

    private nothrow void log(LL level, string msg, Throwable thr = null) {
        Log.msg(LL.Warning, "tick(\""~fqn!T~"\")"~(msg != string.init ? " " : ": ")~msg, thr);
    }

    shared static this() {
        registerTick!(T, D);
    }
}

unittest {
    //static assert(__traits(compiles, {class B{mixin tick;}}), "????");
}

version(unittest) {
    struct A {
        mixin tick;

        long x;

        void run() {}
    }

    struct B {
        mixin tick;
        import core.sync.mutex : Mutex;

        private @leaking Mutex lock;

        void run(){}

        nothrow void error(Throwable thr){}
    }
}

unittest {
    import flow.core.pack: pack, unpack;
    A a;
    a.x = 5;
    
    A an;

    assert(a.pack.unpack!A.x == 5, "pack/unpack of tick failed");
}