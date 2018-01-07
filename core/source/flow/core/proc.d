module flow.core.proc;

private import core.thread;
private import flow.core.atomic;
private import flow.core.traits;
private static import std.parallelism;

alias totalCPUs = std.parallelism.totalCPUs;

private enum JobState : ubyte
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

struct Job {
    private Job* prev;
    private Job* next;

    void delegate() exec;
    nothrow void delegate(Throwable thr) error;
    long time;

    nothrow this(void delegate() exec, void delegate(Throwable thr) error, long time = long.init) {
        this.exec = exec;
        this.error = error;
        this.time = time;
    }
    
    private ubyte taskStatus = JobState.NotStarted;
}

final class Processor {
    private import core.sync.condition: Condition;
    private import core.sync.mutex: Mutex;

    private Pipe[] pipes;

    private Job* head;
    private Job* tail;
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

    public nothrow bool invoke(Job* j) {
        if(atomicReadUbyte(this.status) == PoolState.running) {
            try {this.put(j);}
            catch(Throwable thr) {return false;}
            return true;
        } else return false;
    }

    public void stop() {
        {
            import flow.core.atomic: atomicCasUbyte;

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
        import flow.core.atomic: atomicReadUbyte, atomicSetUbyte;

        while (atomicReadUbyte(this.status) != PoolState.stopNow) {
            Job* task = pop();
            if (task is null) {
                if (atomicReadUbyte(this.status) == PoolState.finishing) {
                    atomicSetUbyte(this.status, PoolState.stopNow);
                    return;
                }
            } else {
                this.doJob(task);
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
    private Job* pop()
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

    private Job* popNoSync()
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
        Job* ret = this.head;
        if(ret !is null) {
            // skips ticks not to execute yet
            while(ret !is null && ret.time > stdTime) {
                if(ret.time < this.nextTime)
                    this.nextTime = ret.time;
                ret = ret.next;
            }
        }

        if (ret !is null)
        {
            this.head = ret.next;
            ret.prev = null;
            ret.next = null;
            ret.taskStatus = JobState.InProgress;
        }

        if (this.head !is null)
        {
            this.head.prev = null;
        }

        return ret;
    }

    private void doJob(Job* job) {
        import flow.core.atomic: atomicSetUbyte;

        assert(job.taskStatus == JobState.InProgress);
        assert(job.next is null);
        assert(job.prev is null);

        scope(exit) {
            this.waiterLock();
            scope(exit) this.waiterUnlock();
            this.notifyWaiters();
        }

        try {
            job.exec();
        } catch (Throwable thr) {
            job.error(thr);
        }

        atomicSetUbyte(job.taskStatus, JobState.Done);
    }
    
    /// Push a task onto the queue.
    private void put(Job* task)
    {
        queueLock();
        scope(exit) queueUnlock();
        putNoSync(task);
    }

    private void putNoSync(Job* task)
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
