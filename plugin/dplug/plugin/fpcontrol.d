module dplug.plugin.fpcontrol;

import std.math;

/// This struct ensures that floating point is save/restored and set consistently in plugin callbacks.
struct FPControl
{
    void initialize() @nogc
    {
        // disable FP exceptions
        if(FloatingPointControl.hasExceptionTraps)
            fpctrl.disableExceptions(FloatingPointControl.allExceptions);

        // force round to nearest
        fpctrl.rounding(FloatingPointControl.roundToNearest);
    }

    FloatingPointControl fpctrl; // handles save/restore
}
