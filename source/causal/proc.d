module causal.proc;

private import core.thread;
private import causal.atomic;
private import causal.data;
private import causal.traits;
private static import std.parallelism;

alias totalCPUs = std.parallelism.totalCPUs;

private enum TickState : ubyte
{
    NotStarted,
    InProgress,
    Done
}

private final class Pipe : Thread
{
    nothrow this(void delegate() dg)
    {
        super(dg);
    }

    Processor proc;
}

static class Ticks {
    private import core.sync.rwmutex: ReadWriteMutex;
    private import std.uuid: UUID;

    private __gshared ReadWriteMutex lock;
    private __gshared static Tick delegate(Data d, UUID b, ulong p, long t) [string] getter;

    shared static this() {
        lock = new ReadWriteMutex;
    }

    static void put(string name, void function(Data d) run, void function(Data d, Throwable thr) nothrow error) {
        synchronized(this.lock.writer)
            getter[name] = (Data d, UUID b, ulong p, long t) {
                return Tick(d, run, error, b, p, t);
            };
    }

    static Tick get(string name, Data d) {
        synchronized(this.lock.reader)
            return getter[name](d, UUID.init, ulong.max, long.init);
    }

    static Tick get(string name, Data d, UUID b = UUID.init, ulong p = ulong.max, long t = long.init) {
        synchronized(this.lock.reader)
            return getter[name](d, b, p, t);
    }
}

public mixin template tick(string name, void function(Data d) run, void function(Data d, Throwable thr) nothrow error) {
    private import causal.proc;

    shared static this() {
        Ticks.put(name, run, error);
    }
}

version(unittest) {
    mixin tick!("foo", (d){}, (d, t) nothrow {});
    mixin tick!("bar", (d){}, (d, t) nothrow {});
}

unittest {
    assert(Ticks.get("foo", null) != Tick.init, "tick could not be created");
    assert(Ticks.get("bar", null) != Tick.init, "tick could not be created");
}

struct Tick {
    private import std.uuid: UUID;

    private Tick* prev;
    private Tick* next;
    
    private ubyte tickStatus = TickState.NotStarted;

    Data data;
    void function(Data d) run;
    void function(Data d, Throwable thr) nothrow error;
    UUID branch;
    long priority;
    long stdTime;

    this(
        // data whichs modification this tick describes
        Data data,
        // data modifying function
        void function(Data d) run,
        // error handler
        void function(Data d, Throwable thr) nothrow error,
        // if causal branch is not given start a new one
        UUID branch,
        // priority of this tick
        ulong priotity,
        // standard time this tick is scheduled for
        long stdTime
    ) {
        import std.uuid;

        this.data = data;
        this.run = run;
        this.error = error;
        this.branch = branch != UUID.init ? branch : randomUUID;
        this.priority = priority;
        this.stdTime = stdTime;
    }
}

final class Processor {
    private import core.sync.condition: Condition;
    private import core.sync.mutex: Mutex;

    private Pipe[] pipes;

    private Tick* head;
    private Tick* tail;
    private PoolState status = PoolState.running;
    private long nextTime;
    private Condition workerCondition;
    private Condition waiterCondition;
    private Mutex queueMutex;
    private Mutex waiterMutex; // For waiterCondition

    /// The instanceStartIndex of the next instance that will be created.
    private __gshared static size_t nextInstanceIndex = 1;

    /// The index of the current thread.
    private static size_t threadIndex;

    /// The index of the first thread in this instance.
    private immutable size_t instanceStartIndex;
    
    /// The index that the next thread to be initialized in this pool will have.
    private size_t nextThreadIndex;

    private enum PoolState : ubyte {
        running,
        finishing,
        stopNow
    }

    public this(size_t nWorkers = 1) {
        synchronized(typeid(Processor))
        {
            instanceStartIndex = nextInstanceIndex;

            // The first worker thread to be initialized will have this index,
            // and will increment it.  The second worker to be initialized will
            // have this index plus 1.
            nextThreadIndex = instanceStartIndex;
            nextInstanceIndex += nWorkers;
        }

        this.queueMutex = new Mutex(this);
        this.waiterMutex = new Mutex();
        workerCondition = new Condition(queueMutex);
        waiterCondition = new Condition(waiterMutex);
        
        this.pipes = new Pipe[nWorkers];

        this.start();
    }

    private void start() {
        foreach (ref poolThread; this.pipes) {
            poolThread = new Pipe(&startWorkLoop);
            poolThread.proc = this;
            poolThread.start();
        }
    }

    public nothrow bool invoke(Tick* j) {
        if(atomicReadUbyte(this.status) == PoolState.running) {
            try {this.put(j);}
            catch(Throwable thr) {return false;}
            return true;
        } else return false;
    }

    public void stop() {
        {
            import causal.atomic: atomicCasUbyte;

            this.queueLock();
            scope(exit) this.queueUnlock();
            atomicCasUbyte(this.status, PoolState.running, PoolState.finishing);
            this.notifyAll();
        }
        // Use this thread as a worker until everything is finished.
        this.executeWorkLoop();

        this.join();
    }

    public void join() {
        foreach (t; this.pipes)
            t.join();
    }

    /** This function performs initialization for each thread that affects
    thread local storage and therefore must be done from within the
    worker thread.  It then calls executeWorkLoop(). */
    private void startWorkLoop() {
        // Initialize thread index.
        {
            this.queueLock();
            scope(exit) this.queueUnlock();
            this.threadIndex = this.nextThreadIndex;
            this.nextThreadIndex++;
        }

        this.executeWorkLoop();
    }

    /** This is the main work loop that worker threads spend their time in
    until they terminate.  It's also entered by non-worker threads when
    finish() is called with the blocking variable set to true. */
    private void executeWorkLoop() {    
        import causal.atomic: atomicReadUbyte, atomicSetUbyte;

        while (atomicReadUbyte(this.status) != PoolState.stopNow) {
            Tick* task = pop();
            if (task is null) {
                if (atomicReadUbyte(this.status) == PoolState.finishing) {
                    atomicSetUbyte(this.status, PoolState.stopNow);
                    return;
                }
            } else {
                this.doTick(task);
            }
        }
    }

    private void wait() {
        import std.datetime.systime: Clock;

        auto stdTime = Clock.currStdTime;

        // if there is nothing enqueued wait for notification
        if(this.nextTime == long.max)
            this.workerCondition.wait();
        else if(this.nextTime - stdTime > 0) // otherwise wait for schedule or notification
            this.workerCondition.wait((this.nextTime - stdTime).hnsecs);
    }

    private void notify() {
        this.workerCondition.notify();
    }

    private void notifyAll() {
        this.workerCondition.notifyAll();
    }

    private void notifyWaiters()
    {
        waiterCondition.notifyAll();
    }

    private void queueLock() {
        assert(this.queueMutex);
        this.queueMutex.lock();
    }

    private void queueUnlock() {
        assert(this.queueMutex);
        this.queueMutex.unlock();
    }

    private void waiterLock() {
        this.waiterMutex.lock();
    }

    private void waiterUnlock() {
        this.waiterMutex.unlock();
    }

    /// Pop a task off the queue.
    private Tick* pop()
    {
        this.queueLock();
        scope(exit) this.queueUnlock();
        auto ret = this.popNoSync();
        while (ret is null && this.status == PoolState.running)
        {
            this.wait();
            ret = this.popNoSync();
        }
        return ret;
    }

    private Tick* popNoSync()
    out(ret) {
        /* If task.prev and task.next aren't null, then another thread
         * can try to delete this task from the pool after it's
         * alreadly been deleted/popped.
         */
        if (ret !is null)
        {
            assert(ret.next is null);
            assert(ret.prev is null);
        }
    } body {
        import std.datetime.systime: Clock;

        auto stdTime = Clock.currStdTime;

        this.nextTime = long.max;
        Tick* ret = this.head;
        if(ret !is null) {
            // skips ticks not to execute yet
            while(ret !is null && ret.stdTime > stdTime) {
                if(ret.stdTime < this.nextTime)
                    this.nextTime = ret.stdTime;
                ret = ret.next;
            }
        }

        if (ret !is null)
        {
            this.head = ret.next;
            ret.prev = null;
            ret.next = null;
            ret.tickStatus = TickState.InProgress;
        }

        if (this.head !is null)
        {
            this.head.prev = null;
        }

        return ret;
    }

    private void doTick(Tick* tick) {
        import causal.atomic: atomicSetUbyte;

        assert(tick.tickStatus == TickState.InProgress);
        assert(tick.next is null);
        assert(tick.prev is null);

        scope(exit) {
            this.waiterLock();
            scope(exit) this.waiterUnlock();
            this.notifyWaiters();
        }

        try {
            tick.run(tick.data);
        } catch (Throwable thr) {
            tick.error(tick.data, thr);
        }

        atomicSetUbyte(tick.tickStatus, TickState.Done);
    }
    
    /// Push a task onto the queue.
    private void put(Tick* task)
    {
        queueLock();
        scope(exit) queueUnlock();
        putNoSync(task);
    }

    private void putNoSync(Tick* task)
    in {
        assert(task);
    } out {
        import std.conv: text;

        assert(tail.prev !is tail);
        assert(tail.next is null, text(tail.prev, '\t', tail.next));
        if (tail.prev !is null) {
            assert(tail.prev.next is tail, text(tail.prev, '\t', tail.next));
        }
    } body {
        // Not using enforce() to save on function call overhead since this
        // is a performance critical function.
        if (status != PoolState.running) {
            throw new Error(
                "Cannot submit a new task to a pool after calling " ~
                "finish() or stop()."
            );
        }

        task.next = null;
        if (head is null) {   //Queue is empty.
            head = task;
            tail = task;
            tail.prev = null;
        } else {
            assert(tail);
            task.prev = tail;
            tail.next = task;
            tail = task;
        }
        notify();
    }
}
