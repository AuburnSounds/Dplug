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

/// When this version is defined, the runtime won't be initialized.
version = doNotUseRuntime;

/// RAII struct to cover callbacks that need attachment and runtime initialized.
/// This deals with runtime inialization and thread attachment in a very explicit way.
struct ScopedForeignCallback(bool assumeRuntimeIsAlreadyInitialized,
                             bool saveRestoreFPU)
{
public:


    // On Windows, we can assume that the runtime is initialized already by virtue of DLL_PROCESS_ATTACH
    version(Windows)
        enum bool doInitializeRuntime = false;
    else
        enum bool doInitializeRuntime = !assumeRuntimeIsAlreadyInitialized;

    // Detaching threads when going out of callbacks.
    // This avoid the GC pausing threads that are doing their things or have died since.
    // This fixed #110 (Cubase + OS X), at a runtime cost.
    enum bool detachThreadsAfterCallback = true;

    /// Thread that shouldn't be attached are eg. the audio threads.
    void enter()
    {
        debug _entered = true;

        static if (saveRestoreFPU)
            _fpControl.initialize();

        version(doNotUseRuntime)
        {
            // Just detect the CPU
            initializeCpuid();
        }
        else
        {
            // Runtime initialization if needed.
            static if (doInitializeRuntime)
            {
                import core.runtime;
                Runtime.initialize();

                // CPUID detection
                initializeCpuid();
            }

            import core.thread: thread_attachThis;

            static if (detachThreadsAfterCallback)
            {
                bool alreadyAttached = isThisThreadAttached();
                if (!alreadyAttached)
                {
                    thread_attachThis();
                    _threadWasAttached = true;
                }
            }
            else
            {
                thread_attachThis();
            }
        }
    }

    ~this()
    {
        version(doNotUseRuntime)
        {
            // Nothing to do, since thread was never attached
        }
        else
        {
            static if (detachThreadsAfterCallback)
                if (_threadWasAttached)
                {
                    import core.thread: thread_detachThis;
                    thread_detachThis();
                }
        }

        // Ensure enter() was called.
        debug assert(_entered);
    }

    @disable this(this);

private:

    version(doNotUseRuntime)
    {
    }
    else
    {
        static if (detachThreadsAfterCallback)
            bool _threadWasAttached = false;
    }

    static if (saveRestoreFPU)
        FPControl _fpControl;

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