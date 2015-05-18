module dplug.plugin.fpcontrol;

import core.cpuid;
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

        version(X86)
        {
            sseState = getSSEControlState();
            setSSEControlState(0x9fff); // Flush denormals to zero + Denormals Are Zeros + all exception masked
        }
    }

    ~this() @nogc
    {
        version(X86)
        {
            // restore SSE2 LDMXCSR and STMXCSR load and write the MXCSR 
            setSSEControlState(sseState);
        }
    }

    FloatingPointControl fpctrl; // handles save/restore

    version(X86)
    {
        uint sseState;
    }
}


version(X86)
{
    /// Get SSE control register
    uint getSSEControlState() @trusted nothrow @nogc
    {
        version (D_InlineAsm_X86)
        {
            uint controlWord;
            asm nothrow @nogc
            {
                stmxcsr controlWord;
            }
            return controlWord;
        }
        else version (D_InlineAsm_X86_64)
        {
            uint controlWord;
            asm nothrow @nogc
            {
                stmxcsr controlWord;
            }
            return controlWord;
        }
        else
            assert(0, "Not yet supported");
    }

    /// Sets SSE control register
    void setSSEControlState(uint controlWord) @trusted nothrow @nogc
    {
        version (D_InlineAsm_X86)
        {
            asm nothrow @nogc
            {
                ldmxcsr controlWord;
            }
        }
        else version (D_InlineAsm_X86_64)
        {
            asm nothrow @nogc
            {
                ldmxcsr controlWord;
            }
        }
        else
            assert(0, "Not yet supported");
    }
}