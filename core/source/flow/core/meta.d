module flow.core.meta;

public template __hasTypeField(T) {
    private import std.traits : hasMember;
    enum __hasTypeField = hasMember!(T, "__type");
}

public template __isTypeType(T) {
    enum __isTypeType = is(typeof(T.__type) == string);
}

public template __checkTypeAttributes(T) {
    private import flow.core.pack: leaking;
    private import std.traits: hasFunctionAttributes, hasUDA;
    enum __checkTypeAttributes = 
        hasFunctionAttributes!(T.__type, "pure", "nothrow", "@nogc", "@property") &&
        hasUDA!(T.__type, leaking);
}

public mixin template typed() {
    private import flow.core.pack;
    private import flow.core.meta;
    private import flow.core.traits;
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
    import flow.core.traits: fqn;
    
    struct A {
        mixin typed;
    }

    A a;

    assert(a.__type == fqn!A, "__type of typed struct doesn't match expectation");
}

unittest {
    import flow.core.traits: fqn;

    class A {
        mixin typed;
    }

    auto a = new A;

    assert(a.__type == fqn!A, "__type of typed class doesn't match expectation");
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
    private import flow.core.pack: leaking;
    private import std.traits: hasUDA;
    enum __checkIdAttributes = !hasUDA!(T.__id, leaking);
}

public mixin template identified() {
    private import std.traits;
    private import std.uuid;
    private import flow.core.meta;
    private import flow.core.traits;

    alias T = typeof(this);
    static if(is(Unqual!(typeof(this)) == class)) {
        alias S = typeof(super);

        static if(!__hasIdField!S)
            UUID  __id;
        else
            static assert(__isIdType!S && __hasIdAttributes!S, "super type ["~fqn!S~"] already has an incompatible field >__id<");

        this() {this.__id = randomUUID;}
    } else static if(is(Unqual!(typeof(this)) == struct))
        static assert(false, "struct ["~fqn!T~"] cannot be identified since structs cannot initialize an id");
    else
        static assert(false, "["~fqn!T~"] cannot be an identified type");
}

unittest {
    import std.uuid: UUID;

    class A {
        mixin identified;
    }

    auto a = new A;

    assert(a.__id != UUID.init, "__id of identified struct is not initialized");
}