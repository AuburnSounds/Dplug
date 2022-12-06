/**
Trace Event Format profiling.

Copyright: Guillaume Piolat 2022.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.profiler;


// TODO: clock should be monotonic per-thread

import core.stdc.stdio;

import dplug.core.math;
import dplug.core.sync;
import dplug.core.thread;
import dplug.core.string;
import dplug.core.nogc;
import dplug.core.vec;

version(Windows)
{
    import core.sys.windows.windows;
}

nothrow @nogc:

/// Allows to generate a Trace Event Format profile JSON.
interface IProfiler
{
nothrow @nogc:
    /// All functions for this interface can be called from many threads at once.
    /// However, from the same thread, there is an ordering.
    /// - `begin/end` pairs must be balanced, per-thread
    /// - `begin/end` pairs can be nested, per-thread
    /// - `category` must come outside of a `begin`/`end` pair

    /// Set current category for pending begin and instant events, for the current thread.
    /// categoryZ must be a zero-terminated slice (zero not counted in length).
    /// This is thread-safe and can be called from multiple threads.
    /// Returns: itself.
    IProfiler category(const(char)[] categoryZ);

    /// Add an instant event to the trace.
    /// This is thread-safe and can be called from multiple threads.
    /// Returns: itself.
    IProfiler instant(const(char)[] categoryZ);

    /// This Begin/End Event will be added to the queue.
    /// Events can be added from whatever thread. But within the same threads, the begin/end events
    /// are nested and must be balanced.
    /// nameZ must be be a zero-terminated slice (zero not counted in length).
    /// Returns: itself.
    IProfiler begin(const(char)[] nameZ);
    ///ditto
    IProfiler end();

    /// Return a borrowed array of bytes for saving. 
    /// Lifetime is tied to lifetime of the interface object.
    /// After `toBytes` is called, no recording function above can be called.
    const(ubyte)[] toBytes();
}

/// Create an `IProfiler`.
IProfiler createProfiler()
{
    version(Dplug_ProfileUI)
    {
        return mallocNew!TraceProfiler();
    }
    else
    {
        return mallocNew!NullProfiler();
    }
}

/// Destroy an `IProfiler` created with `createTraceProfiler`.
void destroyProfiler(IProfiler profiler)
{
    destroyFree(profiler);
}


class NullProfiler : IProfiler
{
    override IProfiler category(const(char)[] categoryZ)
    {
        return this;
    }

    override IProfiler instant(const(char)[] categoryZ)
    {
        return this;
    }

    override IProfiler begin(const(char)[] nameZ)
    {
        return this;
    }

    override IProfiler end()
    {
        return this;
    }

    override const(ubyte)[] toBytes()
    {
        return [];
    }
}


version(Dplug_ProfileUI):


/// Allows to generate a Trace Event Format profile JSON.
class TraceProfiler : IProfiler
{
public:
nothrow:
@nogc:    

    this()
    {
        _clock.initialize();
        _mutex = makeMutex;
    }

    override IProfiler category(const(char)[] categoryZ) 
    {
        ensureThreadContext();
        threadInfo.lastCategoryZ = categoryZ;
        return this;
    }

    override IProfiler instant(const(char)[] nameZ)
    {
        ensureThreadContext();
        long us = _clock.getTickUs();
        addEvent(nameZ, threadInfo.lastCategoryZ, "i", us);
        return this;
    }
   
    override IProfiler begin(const(char)[] nameZ)
    {
        ensureThreadContext();
        long us = _clock.getTickUs();
        addEvent(nameZ, threadInfo.lastCategoryZ, "B", us);
        return this;
    }

    override IProfiler end()
    {
        // no ensureThreadContext, since by API can't begin with .end
        long us = _clock.getTickUs();
        addEventNoname("E", us);
        return this;
    }
    
    override const(ubyte)[] toBytes()
    {
        finalize();
        return cast(const(ubyte)[])_concatenated.asSlice();
    }   

private:
    
    bool _finalized = false;
    Clock _clock;
    static ThreadContext threadInfo; // this is TLS

    Vec!(String*) _allBuffers; // list of all thread-local buffers, this access is checked

    String _concatenated;

    UncheckedMutex _mutex;     // in below mutex.

    void finalize()
    {
        if (_finalized)
            return;

        _concatenated.makeEmpty();
        _concatenated ~= "[";
        _mutex.lock();

        foreach(ref bufptr; _allBuffers[])
            _concatenated ~= *bufptr;

        _mutex.unlock();

        _concatenated ~= "]";
        _finalized = true;
    }

    void addEvent(const(char)[] nameZ, 
                  const(char)[] categoryZ, 
                  const(char)[] typeZ, 
                  long us)
    {
        if (!threadInfo.firstEventForThisThread)
        {
            threadInfo.buffer ~= ",\n";
        }
        threadInfo.firstEventForThisThread = false;

        char[256] buf;
        size_t tid = getCurrentThreadId();
        snprintf(buf.ptr, 256, `{ "name": "%s", "cat": "%s", "ph": "%s", "pid": 0, "tid": %zu, "ts": %lld }`,
                 nameZ.ptr, categoryZ.ptr, typeZ.ptr, tid, us);        
        threadInfo.buffer.appendZeroTerminatedString(buf.ptr);
    }

    void addEventNoname(const(char)[] typeZ, long us)
    {
        if (!threadInfo.firstEventForThisThread)
        {
            threadInfo.buffer ~= ",\n";
        }
        threadInfo.firstEventForThisThread = false;
        char[256] buf;
        size_t tid = getCurrentThreadId();
        snprintf(buf.ptr, 256, `{ "ph": "%s", "pid": 0, "tid": %zu, "ts": %lld }`,
                 typeZ.ptr, tid, us);
        threadInfo.buffer.appendZeroTerminatedString(buf.ptr);
    }

    // All thread-local requirements for the profiling to be thread-local.
    static struct ThreadContext
    {
        bool threadWasSeenAlready = false;
        Vec!long timeStack; // stack of "begin" time values
        String buffer; // thread-local buffer
        const(char)[] lastCategoryZ;
        bool firstEventForThisThread = true;
    }
    
    void ensureThreadContext()
    {
        // have we seen this thread yet? If not, initialize thread locals
        if (!threadInfo.threadWasSeenAlready)
        {
            threadInfo.threadWasSeenAlready = true;
            threadInfo.lastCategoryZ = "none";
            threadInfo.buffer.makeEmpty;
            threadInfo.firstEventForThisThread = true;

            // register buffer
            _mutex.lock();
            _allBuffers.pushBack(&threadInfo.buffer);
            _mutex.unlock();
        }
    }
}


private:

struct Clock
{
nothrow @nogc:

    void initialize()
    {
        version(Windows)
        {
            QueryPerformanceFrequency(&_qpcFrequency);
        }
    }

    /// Get us timestamp.
    /// Must be thread-safe.
    // It doesn't handle wrap-around superbly.
    long getTickUs() nothrow @nogc
    {
        version(Windows)
        {
            import core.sys.windows.windows;
            LARGE_INTEGER lint;
            QueryPerformanceCounter(&lint);
            double seconds = lint.QuadPart / cast(double)(_qpcFrequency.QuadPart);
            long us = cast(long)(seconds * 1_000_000);
            return us;
        }
        else
        {
            import core.time;
            return convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000_000);
        }
    }

private:
    version(Windows)
    {
        LARGE_INTEGER _qpcFrequency;
    }
}

version(Dplug_profileUI)
{
    pragma(msg, "You probably meant Dplug_ProfileUI, not Dplug_profileUI. Correct your dub.json");
}