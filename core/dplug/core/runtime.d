/**
This file provides `ScopedForeignCallback` to be used in every callback, and use to provide runtime initialization (now unused).

Copyright: Guillaume Piolat 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.core.runtime;

import core.runtime;
import core.atomic;
import core.stdc.stdlib;

import std.traits;
import std.functional: toDelegate;

import dplug.core.fpcontrol;
import dplug.core.nogc;
import dplug.core.cpuid;


/// RAII struct to cover extern callbacks.
/// This only deals with CPU identification and FPU control words save/restore.
struct ScopedForeignCallback(bool dummyDeprecated, bool saveRestoreFPU)
{
public:
nothrow:
@nogc:

    /// Thread that shouldn't be attached are eg. the audio threads.
    void enter()
    {
        debug _entered = true;

        static if (saveRestoreFPU)
            _fpControl.initialize();

        // Just detect the CPU in case it's the first ever callback
        initializeCpuid();
    }

    ~this()
    {
        // Ensure enter() was called.
        debug assert(_entered);
    }

    @disable this(this);

private:

    static if (saveRestoreFPU)
        FPControl _fpControl;

    debug bool _entered = false;
}

/// "RUNTIME SECTION"
/// A function or method that can _use_ the runtime thanks to thread attachment.
///
/// Runtime initialization must be dealt with externally with a `ScopedRuntime` struct
/// (typically long-lived since there can be only one).
///
/// Warning: every GC object is reclaimed at the end of the runtime section.
///          By using GC.addRoot you can make GC object survive the collection.
///
/// Returns: a callback Voldement inside which you can use the runtime, but you can't escape GC memory.
auto runtimeSection(F)(F functionOrDelegateThatCanBeGC) nothrow @nogc if (isCallable!(F))
{
    // turn that into a delegate for simplicity purposes
    auto myGCDelegate = toDelegate(functionOrDelegateThatCanBeGC);
    alias T = typeof(myGCDelegate);

    static ReturnType!T internalFunc(T fun, Parameters!T params) nothrow
    {
        import core.stdc.stdio;
        ScopedRuntimeSection section;
        section.enter();

        // Important: we only support `nothrow` runtime section.
        // Supporting exception was creating spurious bugs, probably the excpeption being collected.
        return fun(params);
    }

    // We return this callable Voldemort type

    static struct ManualDelegate
    {
        typeof(myGCDelegate.ptr) ptr;
        typeof(myGCDelegate.funcptr) funcptr;

        ReturnType!T opCall(Parameters!T params) nothrow @nogc
        {
            T dg;
            dg.funcptr = funcptr;
            dg.ptr = ptr;
            return assumeNoGC(&internalFunc)(dg, params);
        }

        @disable this(this);
    }

    ManualDelegate fakeDg;
    fakeDg.funcptr = myGCDelegate.funcptr;
    fakeDg.ptr = myGCDelegate.ptr;
    return fakeDg;
}

/// RAII struct for runtime initialization, to be used once by the plug-in client.
/// Without underlying `ScopedRuntime`, there can be no `runtimeSection`.
struct ScopedRuntime
{
public:
nothrow:
@nogc:

    void initialize()
    {
        try
        {
            bool initOK = assumeNoGC(&Runtime.initialize)();

            if (!initOK)
                assert(false, "Runtime initialization shouldn't fail");
        }
        catch(Exception e)
        {
            assert(false, "Runtime initialization shouldn't fail");
        }

        version(OSX)
        {
            atomicStore(_initialized, true);
        }
        else
        {
            _initialized = true;
        }
    }

    ~this()
    {
        version(OSX){}
        else
        {
            if (_initialized)
            {
                bool terminated;
                try
                {
                    terminated = assumeNoGC(&Runtime.terminate)();
                }
                catch(Exception e)
                {
                    terminated = false;
                }
                assert(terminated);
                _initialized = false;
            }
        }
    }

    @disable this(this);

private:

    version(OSX)
    {
        // Note: this is shared across plug-in instantiation
        // TODO: use zero-init mutex once it exist
        static shared(bool) _initialized = false;
    }
    else
    {
        bool _initialized = false;
    }
}

private:

version(OSX)
{
    // We need that new feature because on OSX shared libraries share their runtime and globals
    // This is called at termination of the host program
    extern(C) pragma(crt_destructor) void deactivateDRuntime()
    {
        import core.stdc.stdio;

        bool initialized = atomicLoad(ScopedRuntime._initialized);

        if (initialized)
        {
            try
            {
                bool terminated = assumeNoGC(&Runtime.terminate)();
            }
            catch(Exception e)
            {
            }
            atomicStore(ScopedRuntime._initialized, false); // TODO: this atomic is racey
        }
    }
}



/// RAII struct to ensure thread attacment is initialized and usable
/// => that allow to use GC, TLS etc in a single function.
/// This isn't meant to be used directly, and it should certainly only be used in a scoped
/// manner without letting a registered thread exit.
struct ScopedRuntimeSection
{
    import core.thread: thread_attachThis, thread_detachThis;

public:
nothrow:
    /// Thread that shouldn't be attached are eg. the audio threads.
    void enter()
    {
        // shoud allow reentrant threads
        bool alreadyAttached = isThisThreadAttached();
        if (!alreadyAttached)
        {
            try
            {
                thread_attachThis();
            }
            catch(Exception e)
            {
                assert(false, "thread_attachThis is not supposed to fail");
            }
            _threadWasAttached = true;
        }
    }

    ~this()
    {
        // Detach current thread if it was attached by this runtime section
        if (_threadWasAttached)
        {
            try
            {
                thread_detachThis();
            }
            catch(Exception e)
            {
                assert(false, "thread_detachThis is not supposed to fail");
            }
            _threadWasAttached = false;
        }

        // By collecting here we avoid correctness by coincidence for someone
        // that would rely on things remaining valid out of the ScopedRuntimeSection
        debug
        {
            import core.memory;
            GC.collect();
        }
    }

    @disable this(this);

private:

    bool _threadWasAttached = false;

    static bool isThisThreadAttached() nothrow
    {
        import core.memory;
        import core.thread;
        GC.disable(); scope(exit) GC.enable();
        if (auto t = Thread.getThis())
            return true;
        else
            return false;
    }
}



