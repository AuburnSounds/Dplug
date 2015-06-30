/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.core.spinlock;

import core.atomic;

import gfm.core;


/// Intended to small delays only.
/// Allows very fast synchronization between eg. a high priority
/// audio thread and an UI thread.
/// Not re-entrant.
struct Spinlock
{
    public
    {
        shared(int)* _state = null;

        enum : int
        {
             UNLOCKED = 0,
             LOCKED = 1
        }

        void initialize() nothrow @nogc
        {
            if (_state == null)
            {
                _state = cast(shared(int)*) alignedMalloc(int.sizeof, 4);
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



/// Queue with spinlocks for inter-thread communication.
/// Support multiple writers, multiple readers.
/// Should work way better with low contention.
///
/// Important: Will crash if the queue is overloaded!
///            ie. if the producer produced faster than the consumer consumes.
///            In the lack of a lock-free allocator there is not much more we can do.
final class SpinlockedQueue(T)
{
    private
    {
        FixedSizeQueue!T _queue;
        Spinlock _lock;
    }

    public
    {
        /// Creates a new spin-locked queue with fixed capacity.
        this(size_t capacity)
        {
            _queue = new FixedSizeQueue!T(capacity);
            _lock.initialize();
        }

        ~this()
        {
            close();
        }

        void close()
        {
            _lock.close();
        }

        /// Pushes an item to the back, crash if queue is full!
        /// Thus, never blocks.
        void pushBack(T x) nothrow @nogc
        {
            _lock.lock();
            scope(exit) _lock.unlock();

            _queue.pushBack(x);
        }

        /// Pops an item from the front, block if queue is empty.
        /// Never blocks.
        bool popFront(out T result) nothrow @nogc
        {
            _lock.lock();
            scope(exit) _lock.unlock();

            if (_queue.length() != 0)
            {
                result = _queue.popFront();
                return true;
            }
            else
                return false;
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
