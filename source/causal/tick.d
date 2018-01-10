module causal.tick;
private import causal.data;

package static class Ticks {
    private import core.sync.rwmutex: ReadWriteMutex;
    private import std.uuid: UUID;

    private __gshared ReadWriteMutex lock;
    private __gshared static Tick* delegate(TickCtx) [string] getter;

    shared static this() {
        lock = new ReadWriteMutex;
    }

    static void put(string name, void function(Branch) run, void function(Branch, Throwable) nothrow error) {
        synchronized(this.lock.writer) {
            getter[name] = (TickCtx c) {
                return new Tick(run, error, c);
            };
        }
    }

    static Tick* get(TickCtx c, void delegate(TickCtx) nothrow n) {
        synchronized(this.lock.reader) {
            Tick* t = getter[c.tick](c);
            t.notify = n;
            return t;
        }
    }
}

public mixin template tick(string name, void function(Branch) run, void function(Branch, Throwable) nothrow error) {
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

    package void function(Branch s) run;
    package void function(Branch s, Throwable thr) nothrow error;
    package void delegate(TickCtx t) nothrow notify;

    private this(
        void function(Branch d) run,
        // error handler
        void function(Branch d, Throwable thr) nothrow error,
        // ticks context
        TickCtx ctx
    ) {
        import std.uuid: UUID, randomUUID;

        this.run = run;
        this.error = error;

        // if branch is not set yet, create one for it
        if(ctx.branch.id == UUID.init)
            ctx.branch.id = randomUUID;
        this.ctx = ctx;
    }
}

version(unittest) {
    mixin tick!("foo", (d){}, (d, t) nothrow {});
    mixin tick!("bar", (d){}, (d, t) nothrow {});
}

unittest {
    nothrow void notify(TickCtx tc) {}
    assert(Ticks.get(TickCtx("foo"), &notify) !is null, "tick could not be created");
    assert(Ticks.get(TickCtx("bar"), &notify) !is null, "tick could not be created");
}