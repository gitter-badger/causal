module flow.core.tick;
public import flow.core.pack : leaking, pack, unpack;
public import flow.core.log : LL;

private shared TypeInfo[string] __ticks;

public template __hasRunFunc(T) {
    private import std.traits : hasMember, ReturnType, Parameters, arity;
    enum __hasRunFunc =
        hasMember!(T, "run") &&
        is(ReturnType!(T.run) == void) && (
            arity!(T.run) == 0 || (
                arity!(T.run) == 1 &&
                __traits(compiles, (pack!(Parameters!(T.run)[0])))
            )
        );
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

public template isTick(T) {
    private import flow.core.meta;

    enum isTick =
        __hasTypeField!T &&
        __isTypeType!T &&
        __checkTypeAttributes!T &&
        __hasRunFunc!T;
}

public void registerTick(T)()
if(isTick!T) {
    import flow.core.traits: fqn, as;
    import std.traits;

    synchronized __ticks[fqn!T] = typeid(T).as!(shared(TypeInfo));
}

public mixin template tick() {
    private import flow.core.log : Log;
    private import flow.core.meta : typed;
    private import flow.core.pack : packable;
    private import flow.core.traits : fqn;
    private import std.traits : Unqual, hasMember;

    alias T = typeof(this);

    static if(!hasMember!(T, "error")) {
        nothrow void error(Throwable thr) {
            log(LL.Warning, thr);
        }
    }

    static assert(is(Unqual!T == struct), "tick ["~fqn!T~"] has to be a struct");
    static assert(__hasRunFunc!T, "tick ["~fqn!T~"] has no qualified run function
        a tick's run handler can have 0 or 1 packable parameters and needs to return void
        examples:
            void run() {}
            void run(long x) {}
            void run(X x) // where X is packable
        negative examples:
            int run() {}
            void run(X x, Y y) {}
            void run(Mutex m) {}
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

    private nothrow void log(LL level, Throwable thr = null) {
        Log.msg(LL.Warning, "tick(\""~fqn!T~"\")", thr);
    }

    private nothrow void log(LL level, string msg, Throwable thr = null) {
        Log.msg(LL.Warning, "tick(\""~fqn!T~"\")"~(msg != string.init ? " " : ": ")~msg, thr);
    }

    shared static this() {
        registerTick!T;
    }
}

unittest {
    //static assert(__traits(compiles, {class B{mixin tick;}}), "????");
}

version(unittest) {
    struct A {
        mixin tick;

        long x;

        void run(long x) {
            this.x = x;
        }
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
    A a;
    a.x = 5;
    
    A an;

    assert(a.pack.unpack!A.x == 5, "pack/unpack of tick failed");
}