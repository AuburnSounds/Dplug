/**
This file provides `ScopedForeignCallback` to be used in every callback.

Copyright: Guillaume Piolat 2015-2023.
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


/// RAII struct to cover extern callbacks.
/// This only deals with CPU identification and FPU control words save/restore.
/// But when we used an enabled D runtime, this used to manage thread attachment 
/// and disappearance, so calling this on callbacks is still mandated.
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



