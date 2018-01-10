module causal.data;

package final pure class Data {
    private import causal.aspect: isAspect;
    private import causal.meta: identified, counting;
    private import causal.pack: leaking, packing, unpacked;
    private import causal.tick: TickCtx;
    private import core.sync.rwmutex: ReadWriteMutex;
    private import std.uuid: UUID;
    
    @leaking private static __gshared ReadWriteMutex __lock;
    @leaking private static shared bool[UUID] __loaded;
    @leaking private static shared Object[][string][UUID] __aspects;

    ubyte[][string] aspects;
    TickCtx[] ticks;
    string damage;

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

    nothrow void put(T)(T[] a) {
        synchronized(this.__lock.writer)
            this.__aspects[this.__id][fqn!T] = a;
    }

    nothrow T[] get(T)() {
        synchronized(this.__lock.reader)
            return this.__aspects[this.__id][fqn!T];
    }

    @packing void onPacking() {
        import std.ascii : newline;
        import std.conv: to;

        try {
            synchronized(this.__lock.writer) {
                if(this.__loaded[this.__id]) {
                    this.__loaded[this.__id] = false;
                    this.join();
                    // TODO pack aspects
                }
            }
        } catch(Throwable thr) {
            auto line = thr.line.to!string;
            this.damage = thr.file~"("~line~"):\t"~thr.msg~newline~thr.info.to!string;
            throw thr;
        }
    }

    @unpacked void onUnpacked() {
        import causal.op: Operator;
        import causal.traits: fqn;
        import std.uuid: randomUUID;

        synchronized(this.__lock.writer) {
            if(!this.__loaded[this.__id]) {
                if(this.__id == UUID.init)
                    this.__id = randomUUID;

                this.__loaded[this.__id] = true;

                // TODO unpack aspects

                // if it has exactly one operator aspect it is self driven
                // self dirven data/tick sets are the kickstarters of the system
                if(fqn!Operator in this.__aspects[this.__id] &&
                    this.__aspects[this.__id][fqn!Operator].length == 1
                ) { // then it can make itself ticking
                    auto op = this.__aspects[this.__id][fqn!Operator][0];
                    foreach(t; this.ticks)
                        op.as!Operator.assign(t, &this.notify);
                }
            }
        }
    }

    void assign(TickCtx c, Processor p) {
        synchronized(this.__lock.reader) {
            if(this.loaded) {
                auto tick = Ticks.get(c);
                this.checkout();
                tick.notify = &this.notify;
                p.invoke(tick);
            } else ticks ~= c;
        }
    }

    private nothrow void notify(TickCtx tc) {
        this.checkin();
    }
}