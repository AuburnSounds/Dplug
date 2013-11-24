// See licenses/WDL_license.txt
module dplug.plugin.spinlock;

/// Intended to small delays only.
/// Allows very fast synchronization between eg. a high priority 
/// audio thread and an UI thread.
/// Not re-entrant.

import core.atomic;

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
