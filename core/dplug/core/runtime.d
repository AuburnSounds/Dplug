/**
 * This file provides `ScopedForeignCallback` to be used in every callback, and use to provide runtime initialization (now unused).
 *
 * Copyright: Copyright Auburn Sounds 2015-2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.runtime;

import core.stdc.stdlib;
import std.traits;

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

template RuntimeSectionReturnType(T)
{
    alias RuntimeSectionReturnType = SetFunctionAttributes!(T, functionLinkage!T, functionAttributes!T | FunctionAttribute.nogc);
}

/// This encloses the runtime initialization and finalization.
/// Returns: a delegate which enables the runtime and call the enclosed delegate.
RuntimeSectionReturnType!T runtimeSection(T)(T functionOrDelegateThatCanBeGC) nothrow @nogc
{
    static if (isDelegate!T)
    {
        enum attrs = functionAttributes!T | FunctionAttribute.nogc;        

        static ReturnType!T internalFunc(T fun, Parameters!T params) nothrow
        {
            try
            {
                ScopedRuntimeSection section;
                section.enter();
            }
            catch(Exception e)
            {
                // runtime initialization failed
                // this should never happen
                assert(false);
            }

            return fun(params);            

            // Leaving runtime here
            // all GC objects will get collected, no reference may escape safely
        }      

        static ReturnType!T internalDg(SuperContext* thisPointer, Parameters!T params) nothrow @nogc
        {
            T dg;
            dg.funcptr = cast(typeof(dg.funcptr)) (thisPointer.funPointer);
            dg.ptr = thisPointer.outerContext;
            return assumeNoGC(&internalFunc)(dg, params);
        }

        ManualDelegate fakeDg;
        fakeDg.ptr = cast(SuperContext*) malloc( SuperContext.sizeof );
        fakeDg.ptr.funPointer = functionOrDelegateThatCanBeGC.funcptr;
        fakeDg.ptr.outerContext = functionOrDelegateThatCanBeGC.ptr;
        fakeDg.funcPtr = &internalDg; // static function so no closures

        RuntimeSectionReturnType!T* result = cast(RuntimeSectionReturnType!T*)(&fakeDg);
        return *result;
    }
    else
        static assert(false, "must be a delegate");
}

void finalizeRuntimeSection(T)(T x)
{
    static if (isDelegate!T)
    {
        // free the context allocated in `runtimeSection`
        free(x.ptr);
    }
    else
        static assert(false, "must be a delegate");
}

private:

static struct SuperContext
{
    void* outerContext;
    void* funPointer;            
}

static struct ManualDelegate
{
    SuperContext* ptr;
    void* funcPtr;
}


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
            // TODO find something that works
       //     bool terminated = Runtime.terminate();
       //     assert(terminated);
       //     _runtimeWasInitialized = false;
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