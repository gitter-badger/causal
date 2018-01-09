module causal.log;

enum LL {
    Message = 0,
    Fatal = 1,
    Error = 2,
    Warning = 3,
    Info = 4,
    Debug = 5,
    FDebug = 6
}

/// flow system logger
final static class Log {
    private import std.ascii : newline;
    private import std.range : isArray;

    /// chosen log level
    public shared static LL level = LL.Warning;

    // string wrapping columns
    public shared static wrap = 120;

    private static nothrow string get(Throwable thr) {
        import causal.traits: as;
        import std.conv: to;
        
        string str;

        if(thr !is null) {
            string line = "n/a";
            try{line = thr.line.to!string;}
            catch(Throwable thr) {}
            str ~= newline~thr.file~"("~line~"):\t"~thr.msg;

            if(thr.msg != string.init)
                str ~= thr.msg~newline;

            string stackTrace = "n/a";
            try{stackTrace = thr.info.to!string;}
            catch(Throwable thr) {}
            str ~= newline~stackTrace;
        }

        return str;
    }

    /// log a message
    public static nothrow void msg(LL level, string msg, Throwable thr = null) {
        import causal.traits: as;
        import std.traits: isArray;

        if(level <= Log.level)
            Log.print(level, Log.get(thr));
    }

    private static nothrow void print(LL level, string msg) {
        import std.stdio: stdout;
        import std.string: wrap;
        import std.conv: to;

        string levelStr = "Unknown";
        try{levelStr = level.to!string;}
        catch(Throwable thr) {}

        if(level <= level) {
            auto str = "["~levelStr~"] ";
            str ~= msg;

            try{
                synchronized {
                    stdout.write(str.wrap(Log.wrap));
                    flush();
                }
            }
            catch(Throwable thr){}
        }
    }

    public static nothrow void flush() {
        import std.stdio : stdout;
        try{stdout.flush();}
        catch(Throwable thr){}
    }
}