/**
* Save/Restore floating-point FPU/SSE state for every plug-in callback.
* 
* Copyright: Copyright Auburn Sounds 2015-2016
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.core.fpcontrol;

version(X86)
    version = isX86;
version(X86_64)
    version = isX86;

/// This struct ensures that floating point is save/restored and set consistently in plugin callbacks.
struct FPControl
{
    void initialize() nothrow @nogc
    {
        version(isX86)
        {
            // store SSE control word
            sseState = getSSEControlState();
            setSSEControlState(0x9fff); // Flush denormals to zero + Denormals Are Zeros + all exception masked

            // store FPU control word
            fpuState = getFPUControlState();


            // masks all floating-point exceptions, sets rounding to nearest, and sets the x87 FPU precision to 64 bits
            ushort control = 0x037f;

            // Looking for problems? Unmask all errors.
            //control = 0x0340;

            // Looking for denormals only? This unmasks denormal creation and denormal use exceptions.
            //control = 0x036d;

            setFPUControlState(control);
        }
    }

    ~this() nothrow @nogc
    {
        version(isX86)
        {
            // restore SSE2 LDMXCSR and STMXCSR load and write the MXCSR
            setSSEControlState(sseState);

            // restore FPU control word
            setFPUControlState(fpuState);
        }
    }

    version(isX86)
    {
        ushort fpuState;
        uint sseState;
    }
}


version(isX86)
{
    version(D_InlineAsm_X86)
        version = InlineX86Asm;
    else version(D_InlineAsm_X86_64)
        version = InlineX86Asm;

    /// Gets FPU control register
    ushort getFPUControlState() nothrow @nogc
    {
        version (InlineX86Asm)
        {
            short cont;
            asm nothrow @nogc
            {
                xor EAX, EAX;
                fstcw cont;
            }
            return cont;
        }
        else
            static assert(0, "Unsupported");
    }

    /// Sets FPU control register
    void setFPUControlState(ushort newState) nothrow @nogc
    {
        // MAYDO: report that the naked version in Phobos is buggy on OSX
        // it fills the control word with a random word which can create
        // FP exceptions.
        version (InlineX86Asm)
        {
            asm nothrow @nogc
            {
                fclex;
                fldcw newState;
            }
        }
        else
            static assert(0, "Unsupported");
    }

    /// Get SSE control register
    uint getSSEControlState() @trusted nothrow @nogc
    {
        version (InlineX86Asm)
        {
            uint controlWord;
            asm nothrow @nogc 
            {
                stmxcsr controlWord; 
            }
            return controlWord;
        }
        else
            static assert(0, "Not yet supported");
    }

    /// Sets SSE control register
    void setSSEControlState(uint controlWord) @trusted nothrow @nogc
    {
        version (InlineX86Asm)
        {
            asm nothrow @nogc 
            { 
                ldmxcsr controlWord; 
            }
        }
        else
            static assert(0, "Not yet supported");
    }
}

unittest
{

    FPControl control;
    control.initialize();


}