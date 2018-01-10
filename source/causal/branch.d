module causal.branch;

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