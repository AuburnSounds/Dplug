/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.spinlock;

import core.atomic;

import gfm.core.memory;

/// Intended to small delays only.
/// Allows very fast synchronization between eg. a high priority
/// audio thread and an UI thread.
/// Not re-entrant.
/// Because of Adjacent Cache-line Prefetching 128 bytes are allocated.
deprecated("Are you sure you want a Spinlock over an UncheckedMutex?") struct Spinlock
{
    public
    {
        shared(int)* _state = null;

        enum : int
        {
             UNLOCKED = 0,
             LOCKED = 1
        }

        enum int sizeOfCacheline = 64;

        void initialize() nothrow @nogc
        {
            if (_state == null)
            {
                // Allocates two full cache-lines.
                // Purely speculative optimization, it is suppposed to reduce false-sharing.
                _state = cast(shared(int)*) alignedMalloc(2 * sizeOfCacheline, sizeOfCacheline);
                assert(_state != null);
                *_state = UNLOCKED;
            }
        }

        @disable this(this);

        ~this() nothrow @nogc
        {
            close();
        }

        void close() nothrow @nogc
        {
            if (_state != null)
            {
                alignedFree(cast(void*)_state);
                _state = null;
            }
        }

        void lock() nothrow @nogc
        {
            while(!cas(_state, UNLOCKED, LOCKED))
            {
                cpuRelax();
            }
        }

        /// Returns: true if the spin-lock was locked.
        bool tryLock() nothrow @nogc
        {
            return cas(_state, UNLOCKED, LOCKED);
        }

        void unlock() nothrow @nogc
        {
            atomicStore(*_state, UNLOCKED);
        }
    }
}

version( D_InlineAsm_X86 )
{
    version = AsmX86;
}
else version( D_InlineAsm_X86_64 )
{
    version = AsmX86;
}

private
{
    void cpuRelax() nothrow @nogc
    {
        // PAUSE instruction, recommended by Intel in busy spin loops

        version( AsmX86 )
        {
            static if( __VERSION__ >= 2067 )
                mixin("asm nothrow @nogc { rep; nop; }");
            else
                mixin("asm { rep; nop; }");
        }
        else version(GNU)
        {
            import gcc.builtins;
             __builtin_ia32_pause();
        }
        else
        {
            static assert(false, "no cpuRelax for this compiler");
        }
    }
}
