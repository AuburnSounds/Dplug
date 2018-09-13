/**
 * This file provides `ScopedForeignCallback` to be used in every callback, and use to provide runtime initialization (now unused).
 *
 * Copyright: Copyright Auburn Sounds 2015-2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.runtime;

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

/// Call a function that is not @nogc.
/// This is enclosed with runtime initialization and finalization.
void callRuntimeSection(void delegate() functionThatCanBeGC) @nogc
{
    void internalFunc(void delegate() f)
    {
        ScopedRuntimeSection section;
        section.enter();
        f();

        // Leaving runtime here
        // all GC objects will get collected!
    }

    assumeNoGC( (void delegate() fun) 
                { 
                    internalFunc(fun); 
                } )(functionThatCanBeGC);
}

private:

/// RAII struct to ensure Runtime is initialized and usable
/// => that allow to use GC, TLS etc in a single function.
/// This isn't meant to be used directly, and it should certainly only be used in a scoped 
/// manner without letting a registered thread exit.
struct ScopedRuntimeSection
{
    import core.runtime;
    import core.thread: thread_attachThis, thread_detachThis;

public:

    /// Thread that shouldn't be attached are eg. the audio threads.
    void enter()
    {
        debug _entered = true;
       
        // Runtime initialization        
        _runtimeWasInitialized = Runtime.initialize();

        bool alreadyAttached = isThisThreadAttached();
        if (!alreadyAttached)
        {
            thread_attachThis();
            _threadWasAttached = true;
        }
    }

    ~this()
    {
        // Detach current thread if it was attached by this runtime section
        if (_threadWasAttached)
        {
            thread_detachThis();
            _threadWasAttached = false;
        }

        // Finalize Runtime if it was initiliazed by this runtime section
        if (_runtimeWasInitialized)
        {
            bool terminated = Runtime.terminate();
            assert(terminated);
            _runtimeWasInitialized = false;
        }
    
        // Ensure enter() was called before.
        debug assert(_entered);
    }

    @disable this(this);

private:

    bool _runtimeWasInitialized = false;
    bool _threadWasAttached = false;

    debug bool _entered = false;

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