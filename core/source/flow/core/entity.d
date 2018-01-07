module flow.core.entity;
private import flow.core.proc: Processor, Job;

public class Entity {
    private import core.atomic: atomicOp, atomicLoad, atomicStore;
    private import core.sync.rwmutex: ReadWriteMutex;
    private import core.thread: Thread, Duration, msecs;
    private import flow.core.meta: identified;
    private import flow.core.pack: leaking, canpack, prepack, postpack;
    private import std.uuid: UUID;

    @leaking public static Duration joinInterval = 5.msecs;

    @leaking private ReadWriteMutex __lock;

    @leaking private shared bool __ticking = false;
    @leaking private shared size_t __count = 0; // counting async operations

    @leaking final nothrow @property count() {return atomicLoad(this.__count);}
    @leaking @canpack final nothrow @property empty() {
        import flow.core.traits: as;
        return atomicOp!"=="(this.__count, 0.as!size_t);
    }

    @leaking final nothrow @property ticking() {
        return atomicOp!"=="(this.__count, true);
    }

    @leaking @canpack final nothrow @property frozen() {
        return atomicOp!"=="(this.__count, false);
    }

    @leaking private Object[string] __aspects;

    mixin identified;

    ubyte[][string] aspects;
    Throwable error;

    public this() {
        this.__lock = new ReadWriteMutex;
    }

    public final nothrow void checkout() {
        import flow.core.traits: as;
        atomicOp!"+="(this.__count, 1.as!size_t);
    }

    public final nothrow void checkin() {
        import flow.core.traits: as;
        atomicOp!"-="(this.__count, 1.as!size_t);
    }

    /* invokes an instructed tick into given processor
    Arguments:
    *   processor
    *   tick to process
        *   this overload takes the actual tick
        *   types are not directly communicable
    *   at which standard time should the tick get executed
        use it cyclic or it will lock up your processors
    *   this tick is part of a causal branch or starts a new one
        to debug what happens, this is the key,
        it is passed from tick to tick so you could track it
        and intentionally pass an unused randomUUID for separating causal branches */
    public nothrow bool invoke(T)(Processor proc, T tick, long stdTime = 0, UUID branch = UUID.init, ubyte[] data = null)
    if(isTick!T) {
        import flow.core.tick: getJob;

        tick.entity = this.id;
        tick.aspects = this.__aspects;

        if(t.allowed) {
            this.checkout();
            auto job = tick.getJob;
            this.invoke(job);
            return true;
        } else return false;
    }

    /// invokes an instructed tick into given processor
    public nothrow bool invoke(Processor proc, string tick, long stdTime = 0, UUID branch = UUID.init, ubyte[] data = null) {
        import flow.core.tick: getJob;

        try {
            synchronized(this.__lock.reader) {
                if(this.ticking) {
                    this.checkout();
                    auto j = tick.getJob(this.id, this.__aspects, branch, data);
                    if(j != Job.init) {
                        this.invoke(job);
                        return true;
                    } else return false;
                } return false;
            }
        } catch(Throwable thr) {
            this.damage(thr);
            return false;
        }
    }

    private nothrow void invoke(ref Job job) {
        try {
            synchronized(this.__lock.reader) {
                if(this.ticking) {
                    auto exec = job.exec;
                    auto error = job.error;

                    job.exec = () {
                        exec();
                        this.checkin();
                    };

                    job.error = (Throwable thr) {
                        error(thr);
                        this.checkin();
                    };
                    
                    proc.invoke(job);
                } return false;
            }
        } catch(Throwable thr) {
            this.damage(thr);
            return false;
        }
    }

    public nothrow void join(Duration interval = Entity.joinInterval) {
        import flow.core.traits: as;
        while(atomicOp!"!="(this.__count, 0.as!size_t))
            Thread.sleep(interval);
    }

    public final nothrow void damage(Throwable thr) {
        this.freeze();
        this.error = thr;
    }

    private final nothrow void __damage(Throwable thr) {
        this.join();
        atomicStore(this.__ticking, false);
        this.error = thr;
    }

    public nothrow bool tick() {
        try {
            synchronized(this.__lock.writer) {  
                if(this.ticking) return true;              
                else {
                    this.load();
                    atomicStore(this.__ticking, true);
                }
            }
            return true;
        } catch(Throwable thr) {
            this.__damage(thr);
            return false;
        }
    }

    private nothrow void load() {
        foreach(a, pkg; this.aspects)
            this.__aspects[a] = getAspect(a, pkg);
    }

    public nothrow void freeze() {
        try {
            synchronized(this.__lock.writer) {
                if(this.frozen) return true;
                else {
                    atomicStore(this.__ticking, false);
                    this.join();
                    this.unload();
                }
            }
        } catch(Throwable thr) {
            this.__damage(thr);
        }
    }

    private nothrow void unload() {

    }
}