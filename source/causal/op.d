module causal.op;
private import causal.aspect;
private import causal.meta;
private import causal.pack;
private import causal.proc;
private import causal.tick;

final class Operator {
    private import core.sync.rwmutex: ReadWriteMutex;

    mixin aspect;

    // since processor start is not threadsafe
    private @leaking ReadWriteMutex __lock;
    private @leaking Processor __proc;

    ulong pipes = 1;

    @packing void onPacking() {
        synchronized(this.__lock.writer) {
            this.join();
            if(this.__proc !is null)
                this.__proc.stop();
        }
    }

    @unpacked void onUnpacked() {
        synchronized(this.__lock.writer) {
            if(this.__proc is null)
                this.__proc = new Processor(this.pipes);
        }
    }
}