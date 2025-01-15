/**
    Save/Restore floating-point control words, so that
    rounding-mode doesn't change wildly in a shared library.

    Copyright: Guillaume Piolat 2015-2016.
    License:   http://www.boost.org/LICENSE_1_0.txt
*/
module dplug.core.fpcontrol;

version(X86)
    version = isX86;
version(X86_64)
    version = isX86;

import inteli.xmmintrin;

nothrow @nogc:

/**
    This struct ensures that floating point is save/restored
    and set consistently in plugin callbacks.
*/
struct FPControl
{
nothrow @nogc:
    void initialize()
    {
        // Save and set control word. This works because
        // intel-intrinsics emulate that control word for
        // ARM.
        {
            // Get current SSE control word
            storedMXCSR = _mm_getcsr();

            // Set current SSE control word:
            // - Flush denormals to zero
            // - Denormals Are Zeros
            // - all exception masked
            _mm_setcsr(0x9fff);
        }

        // There is a x86 specific path-here because x86 has
        // a FPU control word in addition to the SSE control
        // word.
        version(isX86)
        {
            // store FPU control word
            fpuState = getFPUControlState();

            // masks all floating-point exceptions,
            // sets rounding to nearest,
            // and sets the x87 FPU precision to 64 bits
            ushort control = 0x037f;

            // Very rarely useful debug options below:

            // 1. Looking for problems? Unmask all errors.
            //control = 0x0340;

            // 2. Looking for denormals only? This unmasks
            // denormal creation and denormal use
            // exceptions.
            //control = 0x036d;

            setFPUControlState(control);
        }
    }

    ~this()
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
    }
    uint storedMXCSR;
}


version(isX86)
{
    version(D_InlineAsm_X86)
        version = InlineX86Asm;
    else version(D_InlineAsm_X86_64)
        version = InlineX86Asm;

    ushort getFPUControlState()
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
            static assert(0);
    }

    void setFPUControlState(ushort newState)
    {
        version (InlineX86Asm)
        {
            asm nothrow @nogc
            {
                fclex;
                fldcw newState;
            }
        }
        else
            static assert(0);
    }
}

