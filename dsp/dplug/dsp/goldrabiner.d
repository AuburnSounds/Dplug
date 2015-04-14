module dplug.dsp.goldrabiner;

import std.math;

import gfm.math;

import dplug.dsp.funcs,
       dplug.dsp.iir;


/// Monophonic voice pitch detector.
/// - for pitch detection, implements
///   "Parallel Processing Techniques for Estimating Pitch Periods of Speech in the Time Domain" from Gold & Rabiner (1969)    //
/// - for voiced/unvoiced detection, implements
///   "Notes on Buzz-Hiss Detection" from Bernard Gold (1964)
///
/// TODO: should HP filter should track current frequency?
///       "Digital Processing of Speech Signal" bu Rabiner & Shaffer recommends two-stage median filtering
struct GoldRabiner
{
private:

    // Pitch Period Estimator
    struct PPE
    {
        float _pitchPeriod; // estimated
        float _currentPitchPeriodSecs;
        float _lastPulseTime; // time since last pulse detected
        float _invSamplerate;
        double _samplerate;
        float _currentSignal;
        double _expFactor;
        float _blankTime;
        float[2] _lastPitchPeriodSecs; // two previous pitch period estimates (smoothed)
        int _numPulseUntilReady;

        void initialize(double samplerate)
        {
            _currentPitchPeriodSecs = 0.007f; // 0.7 ms at start
            _lastPitchPeriodSecs[0] = 0.007f;
            _lastPitchPeriodSecs[1] = 0.007f;
            _lastPulseTime = 0;
            _invSamplerate = cast(float)(1.0 / samplerate);
            _samplerate = samplerate;
            _currentSignal = 0;
            _numPulseUntilReady = 1;
            recomputePitchDependentParameters();
        }

        void recomputePitchDependentParameters()
        {
            float clampedPitchPeriod = _pitchPeriod;
            if (clampedPitchPeriod < 0.004f)
                clampedPitchPeriod = 0.004f;
            if (clampedPitchPeriod > 0.010f)
                clampedPitchPeriod = 0.010f;
            float rundownTime = _currentPitchPeriodSecs * 1.438848920f; /// 0.695f;
            _expFactor = expDecayFactor(rundownTime, _samplerate);//(float)expFactor(rundownTime, _samplerate);
            _blankTime = 0.4f * _currentPitchPeriodSecs;
        }

        bool next(float pulse)
        {
            assert(pulse >= 0);
            _lastPulseTime += _invSamplerate;
            _currentSignal = cast(float)(_currentSignal * (1.0 - _expFactor));

            if (_lastPulseTime >= _blankTime && pulse > _currentSignal)
            {
                // new pulse detected
                _currentSignal = pulse;
                _lastPitchPeriodSecs[1] = _lastPitchPeriodSecs[0];
                _lastPitchPeriodSecs[0] = _currentPitchPeriodSecs;

                _currentPitchPeriodSecs = _lastPulseTime;
                _lastPulseTime = 0;
                recomputePitchDependentParameters();

                // decrement counter
                if (_numPulseUntilReady > 0)
                    _numPulseUntilReady = _numPulseUntilReady - 1;

                return true;
            }
            return false;
        }
    };

    enum State
    {
        Initial,
        Ascending,
        Descending
    }

    State _ascendingState;
    float _last;
    float _lastPositivePeakValue;
    float _lastNegativePeakValue;

    private:

    float _lastPitchPeriodEstimateSecs;
    float _lastVoicedness;
    float _minPitchPeriod;



    // filter
    BiquadCoeff!double _HPCoeff;
    BiquadDelay!double[2] _HPState;
    BiquadCoeff!double _LPCoeff;
    BiquadDelay!double[3] _LPState;

    // out filters
    BiquadDelay!double _LPPitchState;
    BiquadCoeff!double _LPCoeffPitch;
    BiquadDelay!double _LPVoicedState;
    BiquadCoeff!double _LPCoeffVoiced;

    PPE[6] _PPE;

    public:

        // return approximate latency in samples
    int initialize(double samplerate)
    {
        _last = 0;
        _lastPitchPeriodEstimateSecs = 0.007f;
        _lastVoicedness = 0;
        _minPitchPeriod = 0.5f / cast(float)samplerate;

        // 24 dB/oct high-pass filter around 100hz
        _HPCoeff = highpassFilterRBJ!double(100.0, samplerate, cast(double)SQRT1_2);

        // 36 dB/oct low-pass filter around 600hz
        _LPCoeff = lowpassFilterRBJ!double(600.0, samplerate, cast(double)SQRT1_2);
        _HPState[0].clear();
        _HPState[1].clear();
        _LPState[0].clear();
        _LPState[1].clear();
        _LPState[2].clear();
        _ascendingState = State.Initial;
        _last = 0; // whatever

        for (int i = 0; i < 6; ++i)
            _PPE[i].initialize(samplerate);

        _lastPositivePeakValue = 0;
        _lastNegativePeakValue = 0;

        // 12 dB/oct low-pass
        _LPCoeffPitch = lowpassFilterRBJ!double(50.0, samplerate, cast(double)SQRT1_2);


        _LPCoeffVoiced = lowpassFilterRBJ!double(30.0, samplerate, cast(double)SQRT1_2);
        _LPPitchState.clear();
        _LPVoicedState.clear();

        // should have approx 10 ms latency
        return cast(int)(0.5 + 0.010 * samplerate);
    }

    /// Process next incoming sample. The input signal should be a mono-channel, monophonic signal.
    /// Returns: true if pitch and voicedness have been returned.
    ///          false in warm-up phase. Once warmed it won't return false again unless you call initialize() again.
    bool next(float input, float* outPitchPeriodSecs, float* outVoicedness)
    {
        // filter
        double dinput = input;
        dinput = _LPState[0].next!double(dinput, _LPCoeff);
        dinput = _LPState[1].next!double(dinput, _LPCoeff);
        dinput = _LPState[2].next!double(dinput, _LPCoeff);

        dinput = _HPState[0].next!double(dinput, _HPCoeff);
        dinput = _HPState[1].next!double(dinput, _HPCoeff);

        input = cast(float)dinput;


        bool isPositivePeak = (_ascendingState == State.Ascending) && input < _last;
        bool isNegativePeak = (_ascendingState == State.Descending) && input > _last;

        float[6] M; // M[0] = m1 in paper
        for (int i = 0; i < 6; ++i)
            M[i] = 0;

        // Implementation note: it's unclear in the paper what should be done if m1, m2, m4 or m5 are negative
        // this happen in practice so we clamp to zero

        if (isPositivePeak)
        {
            //ASSERT(x >= 0);
            M[0] = _last; // height of peak.
            M[1] = _last - _lastNegativePeakValue;
            M[2] = _last - _lastPositivePeakValue;
            if (M[0] < 0) M[0] = 0;
            if (M[1] < 0) M[1] = 0;
            if (M[2] < 0) M[2] = 0;
            _lastPositivePeakValue = _last;
            _ascendingState = State.Descending;
        }
        else if (isNegativePeak)
        {
            M[3] = -_last; // height of peak
            M[4] = -_last - _lastPositivePeakValue;
            M[5] = -_last - _lastPositivePeakValue;
            if (M[3] < 0) M[3] = 0;
            if (M[4] < 0) M[4] = 0;
            if (M[5] < 0) M[5] = 0;
            _lastNegativePeakValue = _last;
            _ascendingState = State.Ascending;
        }
        else if (_ascendingState == State.Initial)
        {
            if (input > _last)
                _ascendingState = State.Ascending;
            if (input < _last)
                _ascendingState = State.Descending;

            // if equal, stay in initial state
        }
        _last = input;

        bool pulseDetected = false;
        for (int i = 0; i < 6; ++i)
        {
            if (_PPE[i].next(M[i]))
            {
                pulseDetected = true;
            }
        }

        // at least one pulse was detected, compute pitch
        if (pulseDetected)
        {
            float[6][6] mat;
            for (int i = 0; i < 6; ++i)
            {
                float p0 = _PPE[i]._currentPitchPeriodSecs;
                float pm1 = _PPE[i]._lastPitchPeriodSecs[0];
                float pm2 = _PPE[i]._lastPitchPeriodSecs[1];
                mat[0][i] = p0;
                mat[1][i] = pm1;
                mat[2][i] = pm2;
                mat[3][i] = p0 + pm1;
                mat[4][i] = pm1 + pm2;
                mat[5][i] = p0 + pm1 + pm2;
            }


            static immutable int[4][4] COINCIDENCE_WINDOW =
            [
                [ 1, 2, 3, 4 ],
                [ 2, 4, 6, 8 ],
                [ 4, 8, 12, 16 ],
                [ 8, 16, 24, 32 ],
            ];

            static immutable int[4] BIAS = [ 1, 2, 5, 7 ];

            // find maximum number of coincidence

            float[6] bestResult;

            for (int i = 0; i < 6; ++i)
            {
                float candidate = mat[0][i];
                int coincidenceLine;
                if (candidate < 0.0031)
                    coincidenceLine = 0;
                else if (candidate < 0.0063)
                    coincidenceLine = 1;
                else if (coincidenceLine < 12.7)
                    coincidenceLine = 2;
                else
                    coincidenceLine = 3;

                bestResult[i] = -1000;

                // test for 4 coincidence window size
                for (int c = 0; c < 4; ++c)
                {
                    float biasedResult = cast(float)(-BIAS[c] - 1); // subtract one to account for identity comparison
                    float windowWidthInSecs = COINCIDENCE_WINDOW[coincidenceLine][c] * 0.0001f;

                    // test aginst all values

                    for (int k = 0; k < 6; ++k)
                    {
                        for (int l = 0; l < 6; ++l)
                        {
                            float contrib = 1.0f - std.math.abs(candidate - mat[k][l]) / windowWidthInSecs;
                            if (contrib < 0.0f)
                                contrib = 0.0f;
                            biasedResult += contrib;
                        }
                    }
                    bestResult[i] = bestResult[i] > biasedResult ? bestResult[i] : biasedResult;
                }
            }

            float choosenResult = -1000.0f;
            int choosenIndex = -1;
            for (int i = 0; i < 6; ++i)
            {
                if (bestResult[i] > choosenResult)
                {
                    choosenResult = bestResult[i];
                    choosenIndex = i;
                }
            }

            _lastPitchPeriodEstimateSecs = _PPE[choosenIndex]._currentPitchPeriodSecs;
            const int unvoicedValue = 4; // measured on two inputs, my voice and sistah
            const int voicedValue = 7;

            float clamped = choosenResult;
            if (clamped < 4.0f) clamped = 4.0f;
            if (clamped > 7.0f) clamped = 7.0f;
            _lastVoicedness = (clamped - 4.0f) / 3.0f; // evaluate better method?
            //_lastVoicedness = clamp<float>(_lastVoicedness, 0.0f, 1.0f);
        }

        assert(_lastPitchPeriodEstimateSecs > 0);

        // filter results
        double filteredPitch = _lastPitchPeriodEstimateSecs;
        filteredPitch = _LPPitchState.next!double(filteredPitch, _LPCoeffPitch);

        double filteredVoiced = _lastVoicedness;
        filteredVoiced = _LPVoicedState.next!double(filteredVoiced, _LPCoeffVoiced);


        // avoid low-pass ripple that cause negative periods!
        if (filteredPitch < _minPitchPeriod)
            filteredPitch = _minPitchPeriod;


        *outPitchPeriodSecs = filteredPitch;
        *outVoicedness = clamp!float(filteredVoiced, 0.0f, 1.0f);

        // don't test 4 and 5
        bool allPPEReady = true;
        for (int i = 0; i < 4; ++i)
        {
            if (_PPE[i]._numPulseUntilReady != 0)
            {
                allPPEReady = false;
                break;
            }
        }

        bool resultIsSignificant = _ascendingState != State.Initial && allPPEReady;
        return resultIsSignificant;
    }

}
