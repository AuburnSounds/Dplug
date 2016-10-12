/**
*
* @nogc random numbers and UUID generation.
*
* Authors:
*    Guillaume Piolat
*    Johannes Pfau
*    Andrei Alexandrescu
*
* Copyright:
*   Copyright (c) 2016, Auburn Sounds.
*   Copyright (c) 2011, Johannes Pfau (std.uuid).
*   Copyright (c) 2008-2009, Andrei Alexandrescu (std.random)
*
* License:
*   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
*/
module dplug.core.random;

import std.random: Xorshift32, uniform;
import std.uuid;

import dplug.core.nogc;

// Work-around std.random not being @nogc
// - unpredictableSeed uses TLS
// - MonoTime.currTime.ticks sometimes fails on Mac
// => that leaves us only with the RDTSC instruction.
uint nogc_unpredictableSeed() @nogc nothrow
{
    import core.cpuid;
    if (hasRdtsc())
    {
        uint result;
        version(D_InlineAsm_X86)
        {
            asm nothrow @nogc
            {
                rdtsc;
                mov result, EAX;
            }

        }
        else version(D_InlineAsm_X86_64)
        {
            asm nothrow @nogc
            {
                rdtsc;
                mov result, EAX;
            }
        }
        else
            static assert(false, "Unsupported");
        return result;
    }
    else
        return 0;
}

auto nogc_uniform_int(int min, int max, ref Xorshift32 rng) @nogc nothrow
{
    return assumeNothrowNoGC( (int min, int max, ref Xorshift32 rng)
                              {
                                  return uniform(min, max, rng);
                              } )(min, max, rng);
}

auto nogc_uniform_float(float min, float max, ref Xorshift32 rng) @nogc nothrow
{
    return assumeNothrowNoGC( (float min, float max, ref Xorshift32 rng)
                              {
                                  return uniform(min, max, rng);
                              } )(min, max, rng);
}

// The problem with the original rndGen is that it uses TLS, but without runtime TLS 
// is disallowed.
ref Xorshift32 defaultGlobalRNG() nothrow @nogc
{
    __gshared static Xorshift32 globalRNG;
    __gshared static bool initialized;
    if (!initialized) // TODO: this is not thread-safe, use atomic CAS here
    {
        globalRNG = Xorshift32(nogc_unpredictableSeed());
        initialized = true;
    }
    return globalRNG;
}

static UUID generate(ref Xorshift32 randomGen) nothrow @nogc
{
    UUID u;
    uint* arr = cast(uint*)(u.data.ptr);
    foreach(i; 0..4)
    {
        arr[i] = randomGen.front;
        randomGen.popFront();
    }

    //set variant
    //must be 0b10xxxxxx
    u.data[8] &= 0b10111111;
    u.data[8] |= 0b10000000;

    //set version
    //must be 0b0100xxxx
    u.data[6] &= 0b01001111;
    u.data[6] |= 0b01000000;

    return u;
}

// UUID generation
UUID generateRandomUUID() nothrow @nogc
{
    UUID u = generate(defaultGlobalRNG());
    return u;
}