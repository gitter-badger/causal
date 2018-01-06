module flow.core.atomic;

/** Atomics code.  These forward to core.atomic, but are written like this
   for two reasons:
   1.  They used to actually contain ASM code and I don' want to have to change
       to directly calling core.atomic in a zillion different places.
   2.  core.atomic has some misc. issues that make my use cases difficult
       without wrapping it.  If I didn't wrap it, casts would be required
       basically everywhere.
*/
public void atomicSetUbyte(T)(ref T stuff, T newVal)
if (__traits(isIntegral, T) && is(T : ubyte)) {
    import core.atomic : atomicStore;

    atomicStore(*(cast(shared) &stuff), newVal);
}

/** This gets rid of the need for a lot of annoying casts in other parts of the
code, when enums are involved. */
public ubyte atomicReadUbyte(T)(ref T val)
if (__traits(isIntegral, T) && is(T : ubyte)) {
    import core.atomic : atomicLoad;

    return atomicLoad(*(cast(shared) &val));
}

/** This gets rid of the need for a lot of annoying casts in other parts of the
code, when enums are involved. */
public bool atomicCasUbyte(T)(ref T stuff, T testVal, T newVal)
if (__traits(isIntegral, T) && is(T : ubyte)) {
    import core.atomic : cas;

    return cas(cast(shared) &stuff, testVal, newVal);
}