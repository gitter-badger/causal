module causal.data;

public struct Branch {
    private import causal.data: Data;
    private import std.uuid: UUID;

    UUID id;

    // data whichs modification this tick describes
    Data data;
}

public struct TickCtx {
    // ticks name
    string tick;
    // causal strain tick act in
    Branch branch;
    // standard time this tick is scheduled for
    long stdTime = long.init;
}

package final pure class Data {
    private import causal.aspect: isAspect;
    private import causal.meta: identified, counting;
    private import causal.pack: leaking, packing, unpacked;
    private import core.sync.rwmutex: ReadWriteMutex;
    private import std.uuid: UUID;
    
    @leaking private static __gshared ReadWriteMutex __lock;
    @leaking private static shared bool[UUID] __loaded;
    @leaking private static shared Object[][string][UUID] __aspects;
    
    TickCtx[] ticks;

    ubyte[][string] aspects;
    string damage;

    Data operator;
    ulong idx;

    shared static this() {
        __lock = new ReadWriteMutex;
    }

    mixin counting;
    mixin identified;

    @leaking @property bool loaded() {
        synchronized(this.__lock.reader)
            return this.__loaded[this.__id];
    }

    @leaking @property size_t length(T)() {
        synchronized(this.__lock.reader)
            return this.__aspects[this.__id][fqn!T].length;
    }

    this(UUID id = UUID.init) {
        import std.uuid: randomUUID;
        this.__id = id == UUID.init ? randomUUID : id;
    }

    void put(T)(T[] a) {
        synchronized(this.__lock.writer)
            this.__aspects[this.__id][fqn!T] = a;
    }

    T[] get(T)() {
        import causal.traits: fqn, as;

        synchronized(this.__lock.reader)
            return this.__aspects[this.__id][fqn!T].as!(T[]);
    }

    @packing void unload() {
        import std.ascii : newline;
        import std.conv: to;

        try {
            synchronized(this.__lock.writer) {
                if(this.__loaded[this.__id]) {
                    this.__loaded[this.__id] = false;
                    this.join();

                    // add all pending ticks to operators ticks if there is any
                    if(this.operator !is null && this.operator.__id != this.__id) {
                        this.ticks = null;
                        foreach(t; this.ticks)
                            this.operator.ticks ~= t;
                    }
                    
                    // TODO pack aspects

                    this.__aspects[this.__id] = null;
                }
            }
        } catch(Throwable thr) {
            auto line = thr.line.to!string;
            this.damage = thr.file~"("~line~"):\t"~thr.msg~newline~thr.info.to!string;
            throw thr;
        }
    }

    @unpacked void load() {
        import causal.traits: fqn;
        import std.uuid: randomUUID;

        synchronized(this.__lock.writer) {
            if(!this.__loaded[this.__id]) {
                if(this.__id == UUID.init)
                    this.__id = randomUUID;

                this.__loaded[this.__id] = true;

                // TODO unpack aspects

                /* this might be an operator, whoever unpacked it has no to make it ticking
                by doing:
                    foreach(t; data.ticks)
                        data.get!Operator[0].assign(t);
                */
            }
        }
    }

    package nothrow void notify(TickCtx tc) {
        this.checkin();
    }
}