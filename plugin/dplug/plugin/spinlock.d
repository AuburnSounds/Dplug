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
                // No wait at all! 
                // It will consume all CPU until unlocked.
                // So hurry.
            }
        }

        void unlock() nothrow
        {
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
