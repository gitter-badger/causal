module causal.data;

final pure class Data {
    private import causal.aspect: isAspect, versatile;
    private import causal.meta: identified;

    mixin identified;
    mixin versatile; 
    //mixin ticking; // ticking things have a few redefined ticks like "string onInit;"
}