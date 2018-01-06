module flow.core.entity;
private import flow.core.proc: Processor, Job;

public final class Entity {
    private import core.atomic: atomicOp, atomicLoad, atomicStore;
    private import core.sync.mutex: Mutex;
    private import core.thread: Thread, Duration, msecs;
    private import flow.core.meta: identified;
    private import flow.core.pack: leaking, canpack, prepack, postpack;

    @leaking public static Duration joinInterval = 5.msecs;

    @leaking private Mutex __lock;

    @leaking private shared bool __ticking = false;
    @leaking private shared size_t __count = 0; // counting async operations

    @leaking nothrow @property count() {return atomicLoad(this.__count);}
    @leaking @canpack nothrow @property empty() {
        import flow.core.traits: as;
        return atomicOp!"=="(this.__count, 0.as!size_t);
    }

    @leaking nothrow @property ticking() {
        return atomicOp!"=="(this.__count, true);
    }

    @leaking @canpack nothrow @property frozen() {
        return atomicOp!"=="(this.__count, false);
    }

    mixin identified;

    Object[string] aspects;
    Throwable error;

    public nothrow this() {
        this.__lock = new Mutex;
    }

    public nothrow void checkout() {
        import flow.core.traits: as;
        atomicOp!"+="(this.__count, 1.as!size_t);
    }

    public nothrow void checkin() {
        import flow.core.traits: as;
        atomicOp!"-="(this.__count, 1.as!size_t);
    }

    public nothrow void invoke(Processor proc, void delegate() f, long time = long.init) {
        this.invoke(proc, f, (Throwable thr){}, time);
    }

    public nothrow void invoke(Processor proc, void delegate() f, void delegate(Throwable) e, long time = long.init) {
        import std.stdio: writeln;
        import std.parallelism: taskPool, task;
        
        this.checkout();
        auto job = new Job({
            f();
            this.checkin();
        }, (Throwable thr){
            scope(exit)
                this.checkin();
            e(thr);
        }, time);
        proc.invoke(job);
    }

    public nothrow void join(Duration interval = Entity.joinInterval) {
        import flow.core.traits: as;
        while(atomicOp!"!="(this.__count, 0.as!size_t))
            Thread.sleep(interval);
    }

    public nothrow void damage(Throwable thr) {
        this.freeze();
        this.__damage(thr);
    }

    private nothrow void __damage(Throwable thr) {
        this.join();
        atomicStore(this.__ticking, false);
        this.damage(thr);
    }

    public nothrow bool tick() {

        try {
            synchronized(this.__lock) {
                if(!this.frozen)
                    this.join();
                
                atomicStore(this.__ticking, true);
            }
            return true;
        } catch(Throwable thr) {
            this.__damage(thr);
            return false;
        }
    }

    public nothrow void freeze() {
        try {
            synchronized(this.__lock) {
                if(!this.frozen)
                    this.join();
                
                atomicStore(this.__ticking, false);
            }
        } catch(Throwable thr) {
            this.__damage(thr);
        }
    }
}