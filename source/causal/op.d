module causal.op;
private import causal.aspect;
private import causal.tick;
private import causal.meta;
private import causal.pack;
private import causal.proc;

final class Operator {
    private import causal.data: TickCtx;
    private import core.sync.rwmutex: ReadWriteMutex;

    mixin aspect;

    // since processor start is not threadsafe
    private @leaking ReadWriteMutex __lock;
    private @leaking Processor __proc;

    ulong pipes = 1;

    @packing void onPacking() {
        synchronized(this.__lock.writer) {
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

    void assign(TickCtx c) {
        synchronized(this.__lock.reader) {
            if(c.branch.data.loaded) {
                auto tick = Ticks.get(c, &c.branch.data.notify);
                c.branch.data.checkout();
                this.__proc.invoke(tick);
            }
        }
    }
}