/**
 * Copyright: Copyright Auburn Sounds 2015-2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.runtime;

public import std.typecons;

import dplug.core.fpcontrol;

// Helpers to deal with the D runtime.

version(Windows)
{
    /// Returns: current thread id in a nothrow @nogc way.
    void* currentThreadId() nothrow @nogc
    {
        import std.c.windows.windows;
        return cast(void*)GetCurrentThreadId();
    }
}
else version(Posix)
{
    /// Returns: current thread id in a nothrow @nogc way.
    void* currentThreadId() nothrow @nogc
    {
        import core.sys.posix.pthread;
        return pthread_self;
    }    
}
else
    static assert(false, "OS unsupported");

version(OSX)
{
    // Workaround Issue #15060
    // https://issues.dlang.org/show_bug.cgi?id=15060
    // Found by Martin Nowak and bitwise
    // Trade-off a crash for a leak :|

    extern(C) int sysctlbyname(const char *, void *, size_t *, void *, size_t);

    alias dyld_image_states = int;
    enum : dyld_image_states
    {
        dyld_image_state_initialized = 50,
    }

    __gshared bool didInitRuntime = false;

    extern(C) nothrow
    {
        alias dyld_image_state_change_handler = const(char)* function(dyld_image_states state, uint infoCount, void* dyld_image_info);
    }

    extern(C) const(char)* ignoreImageLoad(dyld_image_states state, uint infoCount, void* dyld_image_info) nothrow
    {
        return null;
    }

    extern(C) void dyld_register_image_state_change_handler(dyld_image_states state, bool batch, dyld_image_state_change_handler handler);


    // Initializes the runtime if not already initialized
    void runtimeInitWorkaround15060()
    {
        import core.runtime;

        if(!didInitRuntime) // There is a race here, could it possibly be a problem? Until now, no.
        {
            Runtime.initialize();

            enum bool needWorkaround15060 = true;
            static if (needWorkaround15060)
                dyld_register_image_state_change_handler(dyld_image_state_initialized, false, &ignoreImageLoad);

            didInitRuntime = true;
        }
    }

    // Initializes the runtime if not already initialized
    // and attach the running thread if necessary
    deprecated void attachToRuntimeIfNeeded()
    {
        import core.thread;
        runtimeInitWorkaround15060();
        thread_attachThis();
    }    
}

/// RAII struct to cover every use case for callbacks!
/// This deals with runtime inialization and thread attachment in a very explicit way.
struct ScopedForeignCallback(Flag!"thisThreadNeedRuntimeInitialized" thisThreadNeedRuntimeInitialized,
                             Flag!"assumeRuntimeIsAlreadyInitialized" assumeRuntimeIsAlreadyInitialized,
                             Flag!"assumeThisThreadIsAlreadyAttached" assumeThisThreadIsAlreadyAttached,
                             Flag!"saveRestoreFPU" saveRestoreFPU)
{
public:
    enum bool doInitializeRuntime = (thisThreadNeedRuntimeInitialized == Yes.thisThreadNeedRuntimeInitialized)
                                && !(assumeRuntimeIsAlreadyInitialized == Yes.assumeRuntimeIsAlreadyInitialized);


    enum bool detachThreadsAfterCallback = false;

    /// Thread that shouldn't be attached are eg. the audio threads.
    void enter(Flag!"thisThreadNeedAttachment" thisThreadNeedAttachment)
    {
        debug _entered = true;

        static if (saveRestoreFPU == Yes.saveRestoreFPU)
            _fpControl.initialize();

        // Runtime initialization if needed.
        static if (doInitializeRuntime)
        {
            version(OSX)
                runtimeInitWorkaround15060();
            else
            {
                import core.runtime;
                Runtime.initialiaze();
            }
        }

        // Thread attachment if needed.
        bool doThreadAttach = (thisThreadNeedAttachment == Yes.thisThreadNeedAttachment)
                               && !(assumeThisThreadIsAlreadyAttached == Yes.assumeThisThreadIsAlreadyAttached);
        
        if (doThreadAttach)
        {
            import core.thread: thread_attachThis;
            thread_attachThis();
            _threadWasAttached = true;
        }
    }

    ~this()
    {
        static if (detachThreadsAfterCallback)
            if (_threadWasAttached)
            {
                import core.thread: thread_detachThis;
                thread_detachThis();
            }

        // Ensure enter() was called.
        debug assert(_entered);
    }

    @disable this(this);

private:
    bool _threadWasAttached = false;
             
    static if (saveRestoreFPU == Yes.saveRestoreFPU)
        FPControl _fpControl;

    debug bool _entered = false;
}