/**
This file provides `ScopedForeignCallback`, a RAII object
to be conventionally in every foreign callback.

Copyright: Guillaume Piolat 2015-2023.
License:   http://www.boost.org/LICENSE_1_0.txt
*/
module dplug.core.runtime;

import dplug.core.fpcontrol;


/**
    RAII struct to cover extern callbacks.
    Nowadays it only deals with FPU/SSE control words
    save/restore.

    When we used a D runtime, this used to manage thread
    attachment and deattachment in each incoming exported
    function.

    Calling this on callbacks is still mandatory, since
    changing floating-point control work can happen and
    create issues.

    Example:

        extern(C) myCallback()
        {
            ScopedForeignCallback!(false, true) cb;
            cb.enter();

            // Rounding mode preserved here...
        }

*/
struct ScopedForeignCallback(bool dummyDeprecated,
                             bool saveRestoreFPU)
{
public:
nothrow:
@nogc:

    /// Call this in each callback.
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



