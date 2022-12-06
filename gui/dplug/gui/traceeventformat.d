/**
Trace Event Format profiling.

Copyright: Guillaume Piolat 2022.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.profiler;


/// A profiler interface, make to generate traces in Trace Event Format.
/// This is useful, for example to check parallelism in the UI.


// TODO: clock should be monotonic per-thread
// events should be recorded per-thread, one mutex per-thread
// Things should be behind an interface

import core.stdc.stdio;

import dplug.core.math;
import dplug.core.sync;
import dplug.core.thread;
import dplug.core.string;
import dplug.core.file;

version(Windows)
{
    import core.sys.windows.windows;
}

nothrow:
@nogc:


/// Allows to generate a Trace Event Format profile JSON.
/// There is one global TraceProfiler per UIContext, and it can be used to retrieve the draw trace of the UI.
/// FUTURE: in case the mutex is contended, could append events into a different trace buffer.
struct TraceProfiler
{
public:
nothrow:
@nogc:

    void initialize()
    {
        _buf = makeString("");

        _buf ~= "[";
        _firstEvent = true;

        version(Windows)
        {
            QueryPerformanceFrequency(&_qpcFrequency);
        }

        _mutex = makeMutex;
    }

    /// Add an event to the trace. This is thread-safe and can be called from multiple threads.
    void instant(const(char)[] nameZ, const(char)[] categoryZ)
    {
        long us = getTickUs();
        addEvent(nameZ, categoryZ, "i", us);
    }

    /// This Begin Event will be added to the queue.
    /// Events can be added from whatever thread. But within the same threads, the begin/end events
    /// are nested and must come in right order.
    void begin(const(char)[] nameZ, const(char)[] categoryZ)
    {
        long us = getTickUs();
        addEvent(nameZ, categoryZ, "B", us);
    }

    /// This End Event will correspond to the last euqueued Begin event. 
    /// Events can be added from whatever thread. But within the same threads, the begin/end events
    /// are nested and must come in right order.
    void end()
    {
        long us = getTickUs();
        addEventNoname("E", us);
    }

    /// Return a borrowed array of bytes for saving. 
    const(ubyte)[] toJSONBytes()
    {
        finalize();
        return cast(const(ubyte)[])_buf.asSlice();
    }

    /// Save JSON profile to a file, for inspection in Chrome's chrome://tracing/ 
    void saveToFile(const(char)[] pathZ)
    {
        writeFile(pathZ, toJSONBytes());
    }

    /// Get us timestamp.
    /// Must be thread-safe.
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
    String _buf;
    bool _finalized = false;
    bool _firstEvent;

    void finalize()
    {
        if (_finalized)
            return;
        _buf ~= "]";
        _finalized = true;
    }

    void addEvent(const(char)[] nameZ, 
                  const(char)[] categoryZ, 
                  const(char)[] typeZ, 
                  long us)
    {
        _mutex.lock();
        if (!_firstEvent)
        {
            _buf ~= ",\n";
        }
        _firstEvent = false;
        char[256] buf;
        size_t tid = getCurrentThreadId();
        snprintf(buf.ptr, 256, `{ "name": "%s", "cat": "%s", "ph": "%s", "pid": 0, "tid": %zu, "ts": %lld }`,
                 nameZ.ptr, categoryZ.ptr, typeZ.ptr, tid, us);
        _buf.appendZeroTerminatedString(buf.ptr);
        _mutex.unlock();
    }

    void addEventNoname(const(char)[] typeZ, long us)
    {
        _mutex.lock();
        if (!_firstEvent)
        {
            _buf ~= ",\n";
        }
        _firstEvent = false;
        char[256] buf;
        size_t tid = getCurrentThreadId();
        snprintf(buf.ptr, 256, `{ "ph": "%s", "pid": 0, "tid": %zu, "ts": %lld }`,
                 typeZ.ptr, tid, us);
        _buf.appendZeroTerminatedString(buf.ptr);
        _mutex.unlock();
    }

    version(Windows)
    {
        LARGE_INTEGER _qpcFrequency;
    }

    UncheckedMutex _mutex;
}