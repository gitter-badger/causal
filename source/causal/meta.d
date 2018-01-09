module causal.meta;

public template hasId(T) {
    enum hasId = __hasIdField!T && __isIdType!T && __checkIdAttributes!T;
}

public template __hasIdField(T) {
    private import std.traits: hasMember;
    enum __hasIdField = hasMember!(T, "__id");
}

public template __isIdType(T) {
    private import std.uuid: UUID;
    enum __isIdType = is(typeof(T.__id) == UUID);
}

public template __checkIdAttributes(T) {
    private import causal.pack: leaking;
    private import std.traits: hasUDA;
    enum __checkIdAttributes = !hasUDA!(T.__id, leaking);
}

public mixin template identified() {
    private import std.traits;
    private import std.uuid;
    private import causal.meta;
    private import causal.traits;

    alias T = typeof(this);

    static assert(is(Unqual!(typeof(this)) == class), "identified objects can only be class");

    alias S = typeof(super);

    static if(!__hasIdField!S)
        UUID  __id;
    else
        static assert(__isIdType!S && __hasIdAttributes!S, "super type ["~fqn!S~"] already has an incompatible field >__id<");

    this() {this.__id = randomUUID;}
}

unittest {
    import std.uuid: UUID;

    class A {
        mixin identified;
    }

    auto a = new A;

    assert(a.__id != UUID.init, "__id of identified struct is not initialized");
}

/*public template __hasTypeField(T) {
    private import std.traits : hasMember;
    enum __hasTypeField = hasMember!(T, "__type");
}

public template __isTypeType(T) {
    enum __isTypeType = is(typeof(T.__type) == string);
}

public template __checkTypeAttributes(T) {
    private import causal.pack: leaking;
    private import std.traits: hasFunctionAttributes, hasUDA;
    enum __checkTypeAttributes = 
        hasFunctionAttributes!(T.__type, "pure", "nothrow", "@nogc", "@property") &&
        hasUDA!(T.__type, leaking);
}

public mixin template typed() {
    private import causal.pack;
    private import causal.meta;
    private import causal.traits;
    private import std.traits;

    alias T = typeof(this);
    static if(is(Unqual!(typeof(this)) == class)) {
        alias S = typeof(super);

        static if(!__hasTypeField!S)
            @leaking pure nothrow @nogc @property string __type() {return fqn!T;}
        else {
            static assert(__isTypeType!S && __hasTypeAttributes!S, "super type ["~fqn!S~"] already has an incompatible field >__type<");

            @leaking override pure nothrow @nogc @property string __type() {return fqn!T;}
        }
    } else static if(is(Unqual!(typeof(this)) == struct))
        @leaking pure nothrow @nogc @property string __type() {return fqn!T;}
}

unittest {
    import causal.traits: fqn;
    
    struct A {
        mixin typed;
    }

    A a;

    assert(a.__type == fqn!A, "__type of typed struct doesn't match expectation");
}

unittest {
    import causal.traits: fqn;

    class A {
        mixin typed;
    }

    auto a = new A;

    assert(a.__type == fqn!A, "__type of typed class doesn't match expectation");
}*/