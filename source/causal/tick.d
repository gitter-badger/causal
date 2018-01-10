module causal.tick;
private import causal.data;

public struct TickCtx {
    // ticks name
    string tick;
    // causal strain tick act in
    Strain strain;
    // standard time this tick is scheduled for
    long stdTime = long.init;
}

public struct Strain {
    private import std.uuid: UUID;

    // the branch this strain belongs to
    UUID branch;

    // data whichs modification this tick describes
    Data data;
}

package static class Ticks {
    private import core.sync.rwmutex: ReadWriteMutex;
    private import std.uuid: UUID;

    private __gshared ReadWriteMutex lock;
    private __gshared static Tick* delegate(TickCtx) [string] getter;

    shared static this() {
        lock = new ReadWriteMutex;
    }

    static void put(string name, void function(Strain) run, void function(Strain, Throwable) nothrow error) {
        synchronized(this.lock.writer) {
            getter[name] = (TickCtx c) {
                return new Tick(run, error, c);
            };
        }
    }

    static Tick* get(TickCtx c) {
        synchronized(this.lock.reader)
            return getter[c.tick](c);
    }
}

public mixin template tick(string name, void function(Strain) run, void function(Strain, Throwable) nothrow error) {
    private import causal.proc;

    shared static this() {
        Ticks.put(name, run, error);
    }
}

public enum TickState : ubyte
{
    NotStarted = 0,
    InProgress,
    Done
}

public struct Tick {
    private import std.uuid: UUID;

    package Tick* prev;
    package Tick* next;
    
    package TickCtx ctx;
    package shared TickState state;

    package void function(Strain s) run;
    package void function(Strain s, Throwable thr) nothrow error;
    package void delegate(TickCtx t) nothrow notify;

    private this(
        void function(Strain d) run,
        // error handler
        void function(Strain d, Throwable thr) nothrow error,
        // ticks context
        TickCtx ctx
    ) {
        import std.uuid: UUID, randomUUID;

        this.run = run;
        this.error = error;

        // if strain is not part of a branch yet, create one for it
        if(ctx.strain.branch == UUID.init)
            ctx.strain.branch = randomUUID;
        this.ctx = ctx;
    }
}

version(unittest) {
    mixin tick!("foo", (d){}, (d, t) nothrow {});
    mixin tick!("bar", (d){}, (d, t) nothrow {});
}

unittest {
    assert(Ticks.get(TickCtx("foo")) !is null, "tick could not be created");
    assert(Ticks.get(TickCtx("bar")) !is null, "tick could not be created");
}