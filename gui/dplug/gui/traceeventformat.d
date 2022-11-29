/**
Trace Event Format profiling.

Copyright: Guillaume Piolat 2022.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.traceeventformat;

import core.stdc.stdio;

import dplug.core.math;
import dplug.core.sync;
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
    void addInstantEvent(const(char)[] nameZ, const(char)[] categoryZ)
    {
        long us = getTickUs();
        addEvent(nameZ, categoryZ, "i", us);
    }

    /// Add an event to the trace. This is thread-safe and can be called from multiple threads.
    void addBeginEvent(const(char)[] nameZ, const(char)[] categoryZ)
    {
        long us = getTickUs();
        addEvent(nameZ, categoryZ, "B", us);
    }

    /// Add an event to the trace. This is thread-safe and can be called from multiple threads.
    void addEndEvent(const(char)[] nameZ, const(char)[] categoryZ)
    {
        long us = getTickUs();
        addEvent(nameZ, categoryZ, "E", us);
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
            /*       static if (preciseMeasurements)
            {
            // About -precise measurement:
            // We use the undocumented fact that QueryThreadCycleTime
            // seem to return a counter in QPC units.
            // That may not be the case everywhere, so -precise is not reliable and should
            // never be the default.
            // Warning: -precise and normal measurements not in the same unit.
            //          You shouldn't trust preciseMeasurements to give actual milliseconds values.
            import core.sys.windows.windows;
            ulong cycles;
            BOOL res = QueryThreadCycleTime(hThread, &cycles);
            assert(res != 0);
            real us = 1000.0 * cast(real)(cycles) / cast(real)(qpcFrequency);
            return cast(long)(0.5 + us);
            }
            else */
            {
                import core.sys.windows.windows;
                LARGE_INTEGER lint;
                QueryPerformanceCounter(&lint);
                double seconds = lint.QuadPart / cast(double)(_qpcFrequency.QuadPart);
                long us = cast(long)(seconds * 1_000_000);
                return us;
            }
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

    void addEvent(const(char)[] nameZ, const(char)[] categoryZ, const(char)[] typeZ, long us)
    {
        _mutex.lock();
        if (!_firstEvent)
        {
            _buf ~= ",\n";
        }
        _firstEvent = false;
        char[256] buf;
        snprintf(buf.ptr, 256, `{ "name": "%s", "cat": "%s", "ph": "%s", "pid": 0, "tid": 0, "ts": %lld }`,
                 nameZ.ptr, categoryZ.ptr, typeZ.ptr, us);        
        _buf.appendZeroTerminatedString(buf.ptr);
        _mutex.unlock();
    }

    version(Windows)
    {
        LARGE_INTEGER _qpcFrequency;
    }

    UncheckedMutex _mutex;
}