module dplug.plugin.spinlock;

/// Intended to small delays only.
/// Allows very fast synchronization between eg. a high priority 
/// audio thread and an UI thread.
/// Not re-entrant.

import core.atomic : cas;
import std.cpuid;

nothrow bool cas(T, V1, V2)(shared(T)* here, const shared(V1)* ifThis, shared(V2)* writeThis) if (is(T U : U*) && __traits(compiles, () { *here = writeThis; } )); 

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
        
        void lock()
        {
            while(!cas(&_state, UNLOCKED, LOCKED))
            {
                // No wait at all! 
                // It will consume all CPU until unlocked.
                // So hurry.
            }
        }

        void unlock()
        {
            atomicStore(_state, UNLOCKED);
        }
    }
}
