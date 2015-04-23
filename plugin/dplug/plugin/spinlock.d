// See licenses/UNLICENSE.txt
module dplug.plugin.spinlock;

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
        enum : int
        {
             UNLOCKED = 0,
             LOCKED = 1
        }

        shared int _state; // initialized to 0 => unlocked

        void lock() nothrow @nogc
        {
            while(!cas(&_state, UNLOCKED, LOCKED))
            {
                cpuRelax();
            }
        }

        /// Returns: true if the spin-lock was locked.
        bool tryLock() nothrow @nogc
        {
            return cas(&_state, UNLOCKED, LOCKED);
        }

        void unlock() nothrow @nogc
        {
            atomicStore(_state, UNLOCKED);
        }
    }
}

/// Similar to $(D Spinlock) but allows for multiple simultaneous readers.
struct RWSpinLock
{
    public
    {
    enum : int
    {
        UNLOCKED = 0,
        WRITER = 1,
        READER = 2
    }

        shared int _state; // initialized to 0 => unlocked

        /// Acquires lock as a reader/writer.
        void lockWriter() nothrow @nogc
        {
            int count = 0;
            while (!tryLockWriter())
            {
                cpuRelax();
            }
        }

        /// Returns: true if the spin-lock was locked for reads and writes.
        bool tryLockWriter() nothrow @nogc
        {
            return cas(&_state, UNLOCKED, WRITER);
        }

        /// Unlocks the spinlock after a writer lock.
        void unlockWriter() nothrow @nogc
        {
            atomicOp!"&="(_state, ~(WRITER));
        }


        /// Acquires lock as a reader.
        void lockReader() nothrow @nogc
        {
            int count = 0;
            while (!tryLockReader())
            {
                cpuRelax();
            }
        }

        /// Returns: true if the spin-lock was locked for reads.
        bool tryLockReader() nothrow @nogc
        {
            int sum = atomicOp!"+="(_state, READER);
            if ((sum & WRITER) != 0)
            {
                atomicOp!"-="(_state, READER);
                return false;
            }
            else
                return true;
        }

        /// Unlocks the spinlock after a reader lock.
        void unlockReader() nothrow @nogc
        {
            atomicOp!"-="(_state, READER);
        }
    }
}


/// A value protected by a spin-lock.
/// Ensure concurrency but no order.
struct Spinlocked(T)
{
    Spinlock spinlock;
    T value;

    void set(T newValue) nothrow @nogc
    {
        spinlock.lock();
        scope(exit) spinlock.unlock();
        value = newValue;
    }

    T get() nothrow @nogc
    {
        T current;
        {
            spinlock.lock();
            scope(exit) spinlock.unlock();
            current = value;
        }
        return current;
    }
}


/// Queue with spinlocks for inter-thread communication.
/// Support multiple writers, multiple readers.
/// Should work way better with low contention.
///
/// Important: Will crash if the queue is overloaded!
///            ie. if the producer produced faster than the producer consumes.
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
            _lock = Spinlock();
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


private
{
    void cpuRelax() nothrow @nogc
    {
        // PAUSE instruction, recommended by Intel in busy spin loops

        static if( __VERSION__ >= 2067 )
            mixin("asm nothrow @nogc { rep; nop; }");
        else
            mixin("asm { rep; nop; }");
    }
}
