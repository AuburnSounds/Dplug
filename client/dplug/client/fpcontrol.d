/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.fpcontrol;

import core.cpuid;
import std.math;

version(X86)
    version = isX86;
version(X86_64)
    version = isX86;

/// This struct ensures that floating point is save/restored and set consistently in plugin callbacks.
struct FPControl
{
    void initialize() @nogc
    {
        // disable FP exceptions
        if(FloatingPointControl.hasExceptionTraps)
        {
            fpctrl.disableExceptions(FloatingPointControl.allExceptions);
            
            // Throw an exception for denormal generation
            debug fpctrl.enableExceptions(FloatingPointControl.subnormalException);
        }

        // force round to nearest
        fpctrl.rounding(FloatingPointControl.roundToNearest);

        version(isX86)
        {
            sseState = getSSEControlState();
            setSSEControlState(0x9fff); // Flush denormals to zero + Denormals Are Zeros + all exception masked
        }
    }

    ~this() @nogc
    {
        version(isX86)
        {
            // restore SSE2 LDMXCSR and STMXCSR load and write the MXCSR
            setSSEControlState(sseState);
        }
    }

    FloatingPointControl fpctrl; // handles save/restore

    version(isX86)
    {
        uint sseState;
    }
}


version(isX86)
{
    version(D_InlineAsm_X86)
        version = InlineX86Asm;
    else version(D_InlineAsm_X86_64)
        version = InlineX86Asm;


    /// Get SSE control register
    uint getSSEControlState() @trusted nothrow @nogc
    {
        version (InlineX86Asm)
        {
            uint controlWord;
            static if( __VERSION__ >= 2067 )
                mixin("asm nothrow @nogc { stmxcsr controlWord; }");
            else
                mixin("asm { stmxcsr controlWord; }");

            return controlWord;
        }
        else
            assert(0, "Not yet supported");
    }

    /// Sets SSE control register
    void setSSEControlState(uint controlWord) @trusted nothrow @nogc
    {
        version (InlineX86Asm)
        {
            static if( __VERSION__ >= 2067 )
                mixin("asm nothrow @nogc { ldmxcsr controlWord; }");
            else
                mixin("asm { ldmxcsr controlWord; }");
        }
        else
            assert(0, "Not yet supported");
    }
}
