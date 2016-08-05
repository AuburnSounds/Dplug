/**
 * Copyright: Copyright Auburn Sounds 2015-2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.runtime;

import std.typecons;
import dplug.core.fpcontrol;

// Helpers to deal with the D runtime, and dynamic libraries entry points.

__gshared void* gModuleHandle = null;


version(Windows)
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = q{
            import std.c.windows.windows;
            import core.sys.windows.dll;

            extern (Windows)
                BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
            {
                switch (ulReason)
                {
                    case DLL_PROCESS_ATTACH:
                        gModuleHandle = cast(void*)hInstance;
                        dll_process_attach(hInstance, false);
                        break;

                    case DLL_PROCESS_DETACH:
                        dll_process_detach(hInstance, true);
                        break;

                    case DLL_THREAD_ATTACH:
                        // TODO: see if we can avoid to do anything here
                        dll_thread_attach(false, true);
                        break;

                    case DLL_THREAD_DETACH:
                        // TODO: see if we can avoid to do anything here
                        dll_thread_attach(true, true); 
                        break;

                    default:
                        break;
                }
                return true;
            }
        };
    }

    void* currentThreadId() nothrow @nogc
    {
        import std.c.windows.windows;
        return cast(void*)GetCurrentThreadId();
    }
}
else version(linux)
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = `
            import core.runtime;
            shared static this()
            {
                Runtime.initialize();
            }

            shared static ~this()
            {
                Runtime.terminate();
            }
        `;
    }
}
else version(OSX)
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = ``;
/*
        extern (C) {
            pragma(LDC_global_crt_ctor, 0)
            void initRuntime()
            {
                import core.runtime;
                Runtime.initialize();
            }

            pragma(LDC_global_crt_dtor, 0)
            void deinitRuntime()
            {
                import core.runtime;
                Runtime.terminate();
            }
        }`;*/
    }


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
    void attachToRuntimeIfNeeded()
    {
        import core.thread;
        runtimeInitWorkaround15060();
        thread_attachThis();
    }

    void* currentThreadId() nothrow @nogc
    {
        import core.sys.posix.pthread;
        return pthread_self;
    }
}
else
    static assert(false, "OS unsupported");

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

    /// Thread that shouldn't be attached are eg. the audio threads.
    void enter(Flag!"thisThreadNeedAttachment" thisThreadNeedAttachment)
    {
        debug _entered = true;

        static if (saveRestoreFPU == Yes.saveRestoreFPU)
            fpControl.initialize();

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
            import core.thread;
            thread_attachThis();
            _threadWasAttached = true;
        }
    }

    ~this()
    {
        // TODO: eventually detach threads here

        // Ensure enter() was called.
        debug assert(_entered);
    }

    @disable this(this);

private:
    bool _threadWasAttached = false;
             
    static if (saveRestoreFPU == Yes.saveRestoreFPU)
        FPControl fpControl;

    debug bool _entered = false;
}