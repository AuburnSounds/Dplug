/**
Save/Restore floating-point FPU/SSE state for every plug-in callback.
 
Copyright: Guillaume Piolat 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.core.fpcontrol;

version(X86)
    version = isX86;
version(X86_64)
    version = isX86;

import inteli.xmmintrin;

/// This struct ensures that floating point is save/restored and set consistently in plugin callbacks.
struct FPControl
{
    void initialize() nothrow @nogc
    {
        // Get current SSE control word (emulated on ARM)
        storedMXCSR = _mm_getcsr();

        // Set current SSE control word (emulated on ARM)
        _mm_setcsr(0x9fff); // Flush denormals to zero + Denormals Are Zeros + all exception masked

        version(isX86)
        {
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
        _mm_setcsr(storedMXCSR);

        version(isX86)
        {        
            // restore FPU control word
            setFPUControlState(fpuState);
        }
    }

    version(isX86)
    {
        ushort fpuState;
        uint storedMXCSR;
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
}

unittest
{
    // TEST FOR DENORMAL FLUSH TO ZERO

    FPControl control;
    control.initialize();
   
   // Doesn't work since constant folder may use "real" precision.
   /*

    // Trying to see if FTZ is working, 1e-37 is a very small normalized number
    float denormal = 1e-37f * 0.1f;

    version(DigitalMars)
    {
        version(X86)
        {
            // DMD x86 32-bit may use FPU operations, hence not suppressing denormals         
        }
        else
            assert(denormal == 0);
    }
    else
        assert(denormal == 0);

    */
}
