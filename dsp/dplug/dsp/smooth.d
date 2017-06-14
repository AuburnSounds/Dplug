/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.dsp.smooth;

import std.algorithm.comparison;
import std.math;

import dplug.core.math;
import dplug.dsp.delayline;
import dplug.core.nogc;
import dplug.core.alignedbuffer;

/// Smooth values exponentially with a 1-pole lowpass.
/// This is usually sufficient for most parameter smoothing.
struct ExpSmoother(T) if (is(T == float) || is(T == double))
{
public:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(float samplerate, float timeAttackRelease, T initialValue) nothrow @nogc
    {
        assert(isFinite(initialValue));

        _current = cast(T)(initialValue);
        _sampleRate = samplerate;

        setAttackReleaseTime(timeAttackRelease);
        
        assert(isFinite(_expFactor));
    }

    /// Changes attack and release time (given in seconds).
    void setAttackReleaseTime(float timeAttackRelease) nothrow @nogc
    {
        _expFactor = cast(T)(expDecayFactor(timeAttackRelease, _sampleRate));
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    T nextSample(T target) nothrow @nogc
    {
        T diff = target - _current;
        if (diff != 0)
        {
            if (abs(diff) < 1e-10f) // to avoid subnormal, and excess churn
            {
                _current = target;
            }
            else
            {
                double temp = _current + diff * _expFactor; // Is double-precision really needed here?
                T newCurrent = cast(T)(temp);
                _current = newCurrent;
            }
        }
        return _current;
    }

    bool hasConverged(T target) nothrow @nogc
    {
        return target == _current;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input[i]);
        }
    }

    void nextBuffer(T input, T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input);
        }
    }

private:
    T _current;
    T _expFactor;
    float _sampleRate;
}

unittest
{
    ExpSmoother!float a;
    ExpSmoother!double b;
}

/// Same as ExpSmoother but have different attack and release decay factors.
struct AttackReleaseSmoother(T) if (is(T == float) || is(T == double))
{
public:
    /// time: the time constant of the smoother.
    /// threshold: absolute difference below which we consider current value and target equal
    void initialize(float sampleRate, float timeAttackSecs, float timeReleaseSecs, T initialValue) nothrow @nogc
    {
        assert(isFinite(initialValue));
        _sampleRate = sampleRate;
        _current = cast(T)(initialValue);
        setAttackTime(timeAttackSecs);
        setReleaseTime(timeReleaseSecs);
    }

    /// Changes attack time (given in seconds).
    void setAttackTime(float timeAttackSecs) nothrow @nogc
    {
        _expFactorAttack = cast(T)(expDecayFactor(timeAttackSecs, _sampleRate));
    }

    /// Changes release time (given in seconds).
    void setReleaseTime(float timeReleaseSecs) nothrow @nogc
    {
        _expFactorRelease = cast(T)(expDecayFactor(timeReleaseSecs, _sampleRate));
    }

    /// Advance smoothing and return the next smoothed sample with respect
    /// to tau time and samplerate.
    T nextSample(T target) nothrow @nogc
    {
        T diff = target - _current;
        if (diff != 0)
        {
            if (abs(diff) < 1e-10f) // to avoid subnormal, and excess churn
            {
                _current = target;
            }
            else
            {
                double expFactor = (diff > 0) ? _expFactorAttack : _expFactorRelease;
                double temp = _current + diff * expFactor; // Is double-precision really needed here?
                T newCurrent = cast(T)(temp);
                _current = newCurrent;
            }
        }
        return _current;
    }

    void nextBuffer(const(T)* input, T* output, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input[i]);
        }
    }

    void nextBuffer(T input, T* output, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input);
        }
    }

private:
    T _current;
    T _expFactorAttack;
    T _expFactorRelease;
    float _sampleRate;
}

unittest
{
    AttackReleaseSmoother!float a;
    AttackReleaseSmoother!double b;
}

/// Non-linear smoother using absolute difference.
/// Designed to have a nice phase response.
/// Warning: samplerate-dependent.
struct AbsSmoother(T) if (is(T == float) || is(T == double))
{
public:

    /// Initialize the AbsSmoother.
    /// maxAbsDiff: maximum difference between filtered consecutive samples
    void initialize(T initialValue, T maxAbsDiff) nothrow @nogc
    {
        assert(isFinite(initialValue));
        _maxAbsDiff = maxAbsDiff;
        _current = initialValue;
    }

    T nextSample(T input) nothrow @nogc
    {
       T absDiff = abs(input - _current);
       if (absDiff <= _maxAbsDiff)
           _current = input;
       else
           _current = _current + absDiff * (input > _current ? 1 : -1);
       return _current;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    T _current;
    T _maxAbsDiff;
}

unittest
{
    AbsSmoother!float a;
    AbsSmoother!double b;
}

/// Smooth values over time with a linear slope.
/// This can be useful for some smoothing needs.
/// Intermediate between fast phase and actual smoothing.
struct LinearSmoother(T) if (is(T == float) || is(T == double))
{
public:

    /// Initialize the LinearSmoother.
    void initialize(T initialValue, float periodSecs, float sampleRate) nothrow @nogc
    {
        _period = periodSecs;
        _periodInv = 1 / periodSecs;
        _sampleRateInv = 1 / sampleRate;

        // clear state
        _current = initialValue;
        _phase = 0;
        _firstNextAfterInit = true;
    }

    /// Set the target value and return the next sample.
    T nextSample(T input) nothrow @nogc
    {
        _phase += _sampleRateInv;
        if (_firstNextAfterInit || _phase > _period)
        {
            _phase -= _period;
            _increment = (input - _current) * (_sampleRateInv * _periodInv);
            _firstNextAfterInit = false;
        }
        _current += _increment;
        return _current;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    T _current;
    T _increment;
    float _period;
    float _periodInv;
    float _sampleRateInv;
    float _phase;
    bool _firstNextAfterInit;
}

unittest
{
    LinearSmoother!float a;
    LinearSmoother!double b;
}

/// Can be very useful when filtering values with outliers.
/// For what it's meant to do, excellent phase response.
struct MedianFilter(T) if (is(T == float) || is(T == double))
{
public:

    void initialize(T initialValue, int samples) nothrow @nogc
    {
        assert(samples >= 2, "N must be >= 2");
        assert(samples % 2 == 1, "N must be odd");

        _delay.reallocBuffer(samples - 1);
        _delay[] = initialValue;

        _arr.reallocBuffer(samples);
        _N = samples;
    }

    ~this()
    {
        _delay.reallocBuffer(0);
        _arr.reallocBuffer(0);
    }

    T nextSample(T input) nothrow @nogc
    {
        // dramatically inefficient

        _arr[0] = input;
        for (int i = 0; i < _N - 1; ++i)
            _arr[i + 1] = _delay[i];

        // sort in place
        quicksort!T(_arr[],  
            (a, b) nothrow @nogc 
            {
                if (a > b) return 1;
                else if (a < b) return -1;
                else return 0;
            }
        );

        T median = _arr[_N/2];

        for (int i = _N - 3; i >= 0; --i)
            _delay[i + 1] = _delay[i];
        _delay[0] = input;
        return median;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    T[] _delay;
    T[] _arr;
    int _N;
}

unittest
{
    void test() nothrow @nogc 
    {
        MedianFilter!float a;
        MedianFilter!double b;
        a.initialize(0.0f, 3);
        b.initialize(0.0f, 5);
    }
    test();
}


/// Simple FIR to smooth things cheaply.
/// Introduces (samples - 1) / 2 latency.
/// This one doesn't convert to integers internally so it may 
/// loose precision over time. Meants for finite signals.
struct UnstableMeanFilter(T) if (is(T == float) || is(T == double))
{
public:
    /// Initialize mean filter with given number of samples.
    void initialize(T initialValue, int samples) nothrow @nogc
    {
        _delay.initialize(samples);

        _invNFactor = cast(T)1 / samples;

        foreach(i; 0..samples)
            _delay.feedSample(initialValue);

        _sum = samples * initialValue;
    }

    /// Initialize with with cutoff frequency and samplerate.
    void initialize(T initialValue, double cutoffHz, double samplerate) nothrow @nogc
    {
        int nSamples = cast(int)(0.5 + samplerate / (2 * cutoffHz));

        if (nSamples < 1)
            nSamples = 1;

        initialize(initialValue, nSamples);
    }

    // process next sample
    T nextSample(T x) nothrow @nogc
    {
        _sum = _sum + x;
        _sum = _sum - _delay.nextSample(x);
        return _sum * _invNFactor;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:
    Delayline!T _delay;
    double _sum; // should be approximately the sum of samples in delay
    T _invNFactor;
    T _factor;
}

/// Simple FIR to smooth things cheaply.
/// Introduces (samples - 1) / 2 latency.
/// Converts everything to long for stability purpose.
/// So this may run forever as long as the input is below some threshold.
struct MeanFilter(T) if (is(T == float) || is(T == double))
{
public:
    /// Initialize mean filter with given number of samples.
    void initialize(T initialValue, int samples, T maxExpectedValue) nothrow @nogc
    {
        _delay = RingBufferNoGC!long(samples);

        _factor = cast(T)(2147483648.0 / maxExpectedValue);
        _invNFactor = cast(T)1 / (_factor * samples);

        // clear state
        // round to integer
        long ivInt = toIntDomain(initialValue);

        while(!_delay.isFull())
            _delay.pushBack(ivInt);

        _sum = cast(int)(_delay.length) * ivInt;
    }

    /// Initialize with with cutoff frequency and samplerate.
    void initialize(T initialValue, double cutoffHz, double samplerate, T maxExpectedValue) nothrow @nogc
    {
        int nSamples = cast(int)(0.5 + samplerate / (2 * cutoffHz));

        if (nSamples < 1)
            nSamples = 1;

        initialize(initialValue, nSamples, maxExpectedValue);
    }

    // process next sample
    T nextSample(T x) nothrow @nogc
    {
        // round to integer
        long input = cast(long)(cast(T)0.5 + x * _factor);
        _sum = _sum + input;
        _sum = _sum - _delay.popFront();
        _delay.pushBack(input);
        return cast(T)_sum * _invNFactor;
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = nextSample(input[i]);
    }

private:

    long toIntDomain(T x) pure const nothrow @nogc
    {
        return cast(long)(cast(T)0.5 + x * _factor);
    }

    RingBufferNoGC!long _delay;
    long _sum; // should always be the sum of samples in delay
    T _invNFactor;
    T _factor;
}

unittest
{
    void test() nothrow @nogc 
    {
        MeanFilter!float a;
        MeanFilter!double b;
        a.initialize(44100.0f, 0.001f, 0.001f, 0.0f);
        b.initialize(44100.0f, 0.001f, 0.001f, 0.0f);
    }
    test();
}


/*
* Copyright (c) 2016 Aleksey Vaneev
* 
* Permission is hereby granted, free of charge, to any person obtaining a
* copy of this software and associated documentation files (the "Software"),
* to deal in the Software without restriction, including without limitation
* the rights to use, copy, modify, merge, publish, distribute, sublicense,
* and/or sell copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
* DEALINGS IN THE SOFTWARE.
*/
/**
* "gammaenv" produces smoothed-out S-curve envelope signal with the specified
* attack and release characteristics. The attack and release times can be
* further adjusted in real-time. Delay parameter is also specified as the
* percentage of the total time.
*
* The S-curve produced by this envelope algorithm closely resembles a
* sine-wave signal slightly augmented via the tanh() function. Such
* augmentation makes the shape slightly steeper and in the end allows the
* algorithm to follow it closer. The name "gammaenv" relates to this
* algorithm's version.
*
* The algorithm's topology is based on 5 sets of "leaky integrators" (the
* simplest form of 1st order low-pass filters). Each set (except the 5th) use
* 4 low-pass filters in series. Outputs of all sets are then simply
* summed/subtracted to produce the final result. The topology is numerically
* stable for any valid input signal, but may produce envelope overshoots
* depending on the input signal.
*
* Up to 25% of total attack (or release) time can be allocated (via Delay
* parameters) to the delay stage. The delay is implemented by the same
* topology: this has the benefit of not requiring additional memory
* buffering. For example, it is possible to get up to 250 ms delay on
* a 1-second envelope release stage without buffering.
*
* The processSymm() function provides the "perfect" implementation of the
* algorithm, but it is limited to the same attack and release times. A more
* universal process() function can work with any attack and release times,
* but it is about 2 times less efficient and the actual attack stage's
* envelope can range from the "designed" U to the undesired sharp V shape.
* Unfortunately, the author was unable to find an approach that could be
* similar to the processSymm() function while providing differing attack and
* release times (the best approach found so far lengthens the delay stage
* unpredictably).
*/
/// gammaenv from Aleksey Vaneev is a better way to have an attack-release smoothing
struct GammaEnv(T) if (is(T == float) || is(T == double))
{
public:

    /**
    * Function initializes or updates the internal variables. All public
    * variables have to be defined before calling this function.
    *
    * @param SampleRate Sample rate.
    */
    void initialize(double sampleRate, double Attack, double Release, 
                                       double AttackDelay, double ReleaseDelay,
                                       bool isInverse) nothrow @nogc
    {
        double a;
        double adly;
        double b;
        double bdly;

        if( Attack < Release )
        {
            a = Attack;
            b = Release;
            adly = AttackDelay;
            bdly = ReleaseDelay;
        }
        else
        {
            b = Attack;
            a = Release;
            bdly = AttackDelay;
            adly = ReleaseDelay;
        }

        _isInverse = isInverse;

        // FUTURE: move this in processing whenever attack or release changes
        calcMults( sampleRate, a, adly, enva.ptr, enva5 );
        calcMults( sampleRate, b, bdly, envb.ptr, envb5 );

        clearState(0);
    }

    double nextSample( double v ) nothrow @nogc
    {
        const double resa = nextSampleSymmetric( v );
        const double cres = ( _isInverse ? resa <= prevr : resa >= prevr );
        int i;

        if( cres )
        {
            for( i = 0; i < envcount4; i += 4 )
            {
                envr[ i + 0 ] = resa;
                envr[ i + 1 ] = resa;
                envr[ i + 2 ] = resa;
                envr[ i + 3 ] = resa;
            }

            envr5 = resa;
            prevr = resa;

            return( resa );
        }

        envr[ 0 ] += ( v - envr[ 0 ]) * envb[ 0 ];
        envr[ 1 ] += ( envr5 - envr[ 1 ]) * envb[ 1 ];
        envr[ 2 ] += ( envr[ 4 * 3 + 1 ] - envr[ 2 ]) * envb[ 2 ];
        envr[ 3 ] += ( envr[ 4 * 3 + 0 ] - envr[ 3 ]) * envb[ 3 ];
        envr5 += ( envr[ 4 * 3 + 0 ] - envr5 ) * envb5;

        for( i = 4; i < envcount4; i += 4 )
        {
            envr[ i + 0 ] += ( envr[ i - 4 ] - envr[ i + 0 ]) * envb[ 0 ];
            envr[ i + 1 ] += ( envr[ i - 3 ] - envr[ i + 1 ]) * envb[ 1 ];
            envr[ i + 2 ] += ( envr[ i - 2 ] - envr[ i + 2 ]) * envb[ 2 ];
            envr[ i + 3 ] += ( envr[ i - 1 ] - envr[ i + 3 ]) * envb[ 3 ];
        }

        prevr = envr[ i - 4 ] + envr[ i - 3 ] + envr[ i - 2 ] -
            envr[ i - 1 ] - envr5;

        return( prevr );
    }

    void nextBuffer(const(T)* input, T* output, int frames) nothrow @nogc
    {
        for (int i = 0; i < frames; ++i)
        {
            output[i] = nextSample(input[i]);
        }
    }

private:
    enum int envcount = 4; ///< The number of envelopes in use.
    enum int envcount4 = envcount * 4; ///< =envcount * 4 (fixed).
    double[ envcount4 ] env; ///< Signal envelope stages 1-4.
    double[ 4 ] enva; ///< Attack stage envelope multipliers 1-4.
    double[ 4 ] envb; ///< Release stage envelope multipliers 1-4.
    double[ envcount4 ] envr; ///< Signal envelope (release) stages 1-4.
    double env5; ///< Signal envelope stage 5.
    double enva5; ///< Attack stage envelope multiplier 5.
    double envb5; ///< Release stage envelope multiplier 5.
    double envr5; ///< Signal envelope (release) stage 5.
    double prevr; ///< Previous output (release).
    bool _isInverse;

    /**
    * Function clears state of *this object.
    *
    * @param initv Initial state value.
    */

    void clearState( const double initv ) nothrow @nogc
    {
        int i;

        for( i = 0; i < envcount4; i += 4 )
        {
            env[ i + 0 ] = initv;
            env[ i + 1 ] = initv;
            env[ i + 2 ] = initv;
            env[ i + 3 ] = initv;
            envr[ i + 0 ] = initv;
            envr[ i + 1 ] = initv;
            envr[ i + 2 ] = initv;
            envr[ i + 3 ] = initv;
        }

        env5 = initv;
        envr5 = initv;
        prevr = initv;
    }


    /**
    * Function performs 1 sample processing and produces output sample
    * (symmetric mode, attack and release should be equal).
    */
    double nextSampleSymmetric(double v) nothrow @nogc
    {
        env[ 0 ] += ( v - env[ 0 ]) * enva[ 0 ];
        env[ 1 ] += ( env5 - env[ 1 ]) * enva[ 1 ];
        env[ 2 ] += ( env[ 4 * 3 + 1 ] - env[ 2 ]) * enva[ 2 ];
        env[ 3 ] += ( env[ 4 * 3 + 0 ] - env[ 3 ]) * enva[ 3 ];
        env5 += ( env[ 4 * 3 + 0 ] - env5 ) * enva5;
        int i;

        for( i = 4; i < envcount4; i += 4 )
        {
            env[ i + 0 ] += ( env[ i - 4 ] - env[ i + 0 ]) * enva[ 0 ];
            env[ i + 1 ] += ( env[ i - 3 ] - env[ i + 1 ]) * enva[ 1 ];
            env[ i + 2 ] += ( env[ i - 2 ] - env[ i + 2 ]) * enva[ 2 ];
            env[ i + 3 ] += ( env[ i - 1 ] - env[ i + 3 ]) * enva[ 3 ];
        }

        return( env[ i - 4 ] + env[ i - 3 ] + env[ i - 2 ] -
                env[ i - 1 ] - env5 );
    }


    static void calcMults( const double SampleRate, const double Time,
                           const double o, double* envs, ref double envs5 ) nothrow @nogc
    {
        const double o2 = o * o;

        if( o <= 0.074 )
        {
            envs[ 3 ] = 0.44548 + 0.00920770 * cos( 90.2666 * o ) -
                3.18551 * o - 0.132021 * cos( 377.561 * o2 ) -
                90.2666 * o * o2 * cos( 90.2666 * o );
        }
        else
            if( o <= 0.139 )
            {
                envs[ 3 ] = 0.00814353 + 3.07059 * o + 0.00356226 *
                    cos( 879.555 * o2 );
            }
            else
                if( o <= 0.180 )
                {
                    envs[ 3 ] = 0.701590 + o2 * ( 824.473 * o * o2 - 11.8404 );
                }
                else
                {
                    envs[ 3 ] = 1.86814 + o * ( 84.0061 * o2 - 10.8637 ) -
                        0.0122863 / o2;
                }

        const double e3 = envs[ 3 ];

        envs[ 0 ] = 0.901351 + o * ( 12.2872 * e3 + o * ( 78.0614 -
                                                          213.130 * o ) - 9.82962 ) + e3 * ( 0.024808 *
                                                                                             exp( 7.29048 * e3 ) - 5.4571 * e3 );
        const double e0 = envs[ 0 ];

        const double e3exp = exp( 1.31354 * e3 + 0.181498 * o );
        envs[ 1 ] = e3 * ( e0 * ( 2.75054 * o - 1.0 ) - 0.611813 * e3 *
                           e3exp ) + 0.821369 * e3exp - 0.845698;
        const double e1 = envs[ 1 ];

        envs[ 2 ] = 0.860352 + e3 * ( 1.17208 - 0.579576 * e0 ) + o * ( e0 *
                                                                        ( 1.94324 - 1.95438 * o ) + 1.20652 * e3 ) - 1.08482 * e0 -
            2.14670 * e1;

        if( o >= 0.0750 )
        {
            envs5 = 0.00118;
        }
        else
        {
            envs5 = e0 * ( 2.68318 - 2.08720 * o ) + 0.485294 * log( e3 ) +
                3.5805e-10 * exp( 27.0504 * e0 ) - 0.851199 - 1.24658 * e3 -
                0.885938 * log( e0 );
        }

        const double c = 2 * PI / SampleRate;
        envs[ 0 ] = calcLP1CoeffLim( c / ( Time * envs[ 0 ]));
        envs[ 1 ] = calcLP1CoeffLim( c / ( Time * envs[ 1 ]));
        envs[ 2 ] = calcLP1CoeffLim( c / ( Time * envs[ 2 ]));
        envs[ 3 ] = calcLP1CoeffLim( c / ( Time * envs[ 3 ]));
        envs5 = calcLP1CoeffLim( c / ( Time * envs5 ));
    }

    /**
    * Function calculates first-order low-pass filter coefficient for the
    * given Theta frequency (0 to pi, inclusive). Returned coefficient in the
    * form ( 1.0 - coeff ) can be used as a coefficient for a high-pass
    * filter. This ( 1.0 - coeff ) can be also used as a gain factor for the
    * high-pass filter so that when high-passed signal is summed with
    * low-passed signal at the same Theta frequency the resuling sum signal
    * is unity.
    *
    * @param theta Low-pass filter's circular frequency, >= 0.
    */
    static double calcLP1Coeff( const double theta ) nothrow @nogc
    {
        const double costheta2 = 2.0 - cos( theta );
        return( 1.0 - ( costheta2 - sqrt( costheta2 * costheta2 - 1.0 )));
    }

    /**
    * Function checks the supplied parameter, limits it to "pi" and calls the
    * calcLP1Coeff() function.
    *
    * @param theta Low-pass filter's circular frequency, >= 0.
    */
    static double calcLP1CoeffLim( const double theta ) nothrow @nogc
    {
        return( calcLP1Coeff( theta < PI ? theta : PI ));
    }
}

unittest
{
    GammaEnv!float a;
    GammaEnv!double b;
}