// See licenses/WDL_license.txt
module dplug.plugin.spinlock;

import core.atomic;

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

        shared int _state; // initialized to false => unlocked
        
        void lock() nothrow
        {
            while(!cas(&_state, UNLOCKED, LOCKED))
            {
                //TODO: PAUSE instruction for GDC/LDC (for now it will fail to compile)
                asm
                {
                    rep; nop; // PAUSE instruction, recommended by Intel in busy spin loops
                }

            }
        }

        /// Returns: true if the spin-lock was locked.
        bool tryLock() nothrow
        {
            return cas(&_state, UNLOCKED, LOCKED);
        }

        void unlock() nothrow
        {
            // TODO: on x86, we don't necessarily need an atomic op if 
            // _state is on a DWORD address
            atomicStore(_state, UNLOCKED);
        }
    }
}

/// A value protected by a spin-lock.
/// Ensure concurrency but no order.
struct Spinlocked(T)
{
    Spinlock spinlock;
    T value;

    void set(T newValue) nothrow
    {
        spinlock.lock();
        scope(exit) spinlock.unlock();

        value = newValue;
    }

    T get() nothrow
    {
        spinlock.lock();
        T current = value;
        spinlock.unlock();
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

        /// Pushes an item to the back, block if queue is full.
        void pushBack(T x)
        {
            _lock.lock();
            _queue.pushBack(x);
            _lock.unlock();
        }

        /// Pops an item from the front, block if queue is empty.
        /// Will crash if the queue is overloaded.
        bool popFront(out T result)
        {
            bool hadItem;
            _lock.lock();
            if (_queue.length() != 0)
            {
                result = _queue.popFront();
                hadItem = true;
            }
            else
                hadItem = false;
            _lock.unlock();
            return hadItem;
        }
    }
}

