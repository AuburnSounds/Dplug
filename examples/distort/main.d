/**
Copyright: Guillaume Piolat 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module main;

import std.math;

import dplug.core,
       dplug.client,
       dplug.dsp;

import gui;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!DistortClient);

enum : int
{
    paramInput,
    paramDrive,
    paramBias,
    paramOutput,
    paramOnOff,
}

/// Example mono/stereo distortion plugin.
final class DistortClient : dplug.client.Client
{
public:
nothrow:
@nogc:

    this()
    {
    }

    override PluginInfo buildPluginInfo()
    {
        // Plugin info is parsed from plugin.json here at compile time.
        // Indeed it is strongly recommended that you do not fill PluginInfo 
        // manually, else the information could diverge.
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    // This is an optional overload, default is zero parameter.
    // Caution when adding parameters: always add the indices
    // in the same order than the parameter enum.
    override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        params ~= mallocNew!GainParameter(paramInput, "input", 6.0, 0.0);
        params ~= mallocNew!LinearFloatParameter(paramDrive, "drive", "%", 0.0f, 100.0f, 20.0f);
        params ~= mallocNew!LinearFloatParameter(paramBias, "bias", "%", 0.0f, 100.0f, 50.0f);
        params ~= mallocNew!GainParameter(paramOutput, "output", 6.0, 0.0);
        params ~= mallocNew!BoolParameter(paramOnOff, "enabled", true);
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(1, 1);
        io ~= LegalIO(2, 2);
        return io.releaseData();
    }

    // This override is optional, this supports plugin delay compensation in hosts.
    // By default, 0 samples of latency.
    override int latencySamples(double sampleRate) pure const 
    {
        return 0;
    }

    // This override is optional, the default implementation will
    // have one default preset.
    override Preset[] buildPresets() nothrow @nogc
    {
        auto presets = makeVec!Preset();
        presets ~= makeDefaultPreset();

        static immutable float[] silenceParams = [0.0f, 0.0f, 0.0f, 1.0f, 0];
        presets ~= mallocNew!Preset("Silence", silenceParams);

        static immutable float[] fullOnParams = [1.0f, 1.0f, 0.4f, 1.0f, 0];
        presets ~= mallocNew!Preset("Full-on", fullOnParams);
        return presets.releaseData();
    }

    // This override is also optional. It allows to split audio buffers in order to never
    // exceed some amount of frames at once.
    // This can be useful as a cheap chunking for parameter smoothing.
    // Buffer splitting also allows to allocate statically or on the stack with less worries.
    override int maxFramesInProcess() const //nothrow @nogc
    {
        return 512;
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        // Clear here any state and delay buffers you might have.

        assert(maxFrames <= 512); // guaranteed by audio buffer splitting

        _sampleRate = sampleRate;

        foreach(channel; 0..2)
        {
            _inputRMS[channel].initialize(sampleRate);
            _outputRMS[channel].initialize(sampleRate);
            _hpState[channel].initialize();
        }
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames,
                               TimeInfo info) nothrow @nogc
    {
        assert(frames <= 512); // guaranteed by audio buffer splitting

        int numInputs = cast(int)inputs.length;
        int numOutputs = cast(int)outputs.length;

        const int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        const float inputGain = convertDecibelToLinearGain(readParam!float(paramInput));
        float drive = readParam!float(paramDrive) * 0.01f;
        float bias = readParam!float(paramBias) * 0.01f;
        const float outputGain = convertDecibelToLinearGain(readParam!float(paramOutput));

        const bool enabled = readParam!bool(paramOnOff);

        if (enabled)
        {
            BiquadCoeff highpassCoeff = biquadRBJHighPass(150, _sampleRate, SQRT1_2);
            for (int chan = 0; chan < minChan; ++chan)
            {
                // Distort and put the result in output buffers
                for (int f = 0; f < frames; ++f)
                {
                    const float inputSample = inputGain * 2.0 * inputs[chan][f];

                    // Feed the input RMS computation
                    _inputRMS[chan].nextSample(inputSample);

                    // Distort signal
                    const float distorted = tanh(inputSample * drive * 10.0f + bias) * 0.9f;
                    outputs[chan][f] = outputGain * distorted;
                }

                // Highpass to remove bias
                _hpState[chan].nextBuffer(outputs[chan], outputs[chan], frames, highpassCoeff);

                // Feed the output RMS computation
                for (int f = 0; f < frames; ++f)
                {
                    _outputRMS[chan].nextSample(outputs[chan][f]);
                }
            }
        }
        else
        {
            // Bypass mode
            for (int chan = 0; chan < minChan; ++chan)
                outputs[chan][0..frames] = inputs[chan][0..frames];
        }

        // fill with zero the remaining channels
        for (int chan = minChan; chan < numOutputs; ++chan)
            outputs[chan][0..frames] = 0; // D has array slices assignments and operations

        // Update RMS meters from the audio callback
        // The IGraphics object must be acquired and released, so that it does not
        // disappear under your feet
        if (DistortGUI gui = cast(DistortGUI) graphicsAcquire())
        {
            float[2] inputLevels, outputLevels;
            inputLevels[0] = convertLinearGainToDecibel(_inputRMS[0].RMS());
            inputLevels[1] = minChan >= 1 ? convertLinearGainToDecibel(_inputRMS[1].RMS()) : inputLevels[0];
            outputLevels[0] = convertLinearGainToDecibel(_outputRMS[0].RMS());
            outputLevels[1] = minChan >= 1 ? convertLinearGainToDecibel(_outputRMS[1].RMS()) : outputLevels[0];
            gui.setMetersLevels(inputLevels, outputLevels);
            graphicsRelease();
        }
    }

    override IGraphics createGraphics()
    {
        return mallocNew!DistortGUI(this);
    }

private:
    CoarseRMS[2] _inputRMS;
    CoarseRMS[2] _outputRMS;
    BiquadDelay[2] _hpState;
    float _sampleRate;
}



/// Simple envelope follower, filters the envelope with 24db/oct lowpass.
struct EnvelopeFollower
{
public:

    // typical frequency would be is 10-30hz
    void initialize(float cutoffInHz, float samplerate) nothrow @nogc
    {
        _coeff = biquadRBJLowPass(cutoffInHz, samplerate);
        _delay0.initialize();
        _delay1.initialize();
    }

    // takes on sample, return mean amplitude
    float nextSample(float x) nothrow @nogc
    {
        float l = abs(x);
        l = _delay0.nextSample(l, _coeff);
        l = _delay1.nextSample(l, _coeff);
        return l;
    }

    void nextBuffer(const(float)* input, float* output, int frames) nothrow @nogc
    {
        for(int i = 0; i < frames; ++i)
            output[i] = abs(input[i]);

        _delay0.nextBuffer(output, output, frames, _coeff);
        _delay1.nextBuffer(output, output, frames, _coeff);
    }

private:
    BiquadCoeff _coeff;
    BiquadDelay _delay0;
    BiquadDelay _delay1;
}

/// Sliding RMS computation
/// To use for coarse grained levels for visual display.
struct CoarseRMS
{
public:
    void initialize(double sampleRate) nothrow @nogc
    {
        // In Reaper, default RMS window is 500 ms
        _envelope.initialize(20, sampleRate);

        _last = 0;
    }

    /// Process a chunk of samples and return a value in dB (could be -infinity)
    void nextSample(float input) nothrow @nogc
    {
        _last = _envelope.nextSample(input * input);
    }

    void nextBuffer(float* input, int frames) nothrow @nogc
    {
        if (frames == 0)
            return;

        for (int i = 0; i < frames - 1; ++i)
            _envelope.nextSample(input[i] * input[i]);

        _last = _envelope.nextSample(input[frames - 1] * input[frames - 1]);
    }

    float RMS() nothrow @nogc
    {
        return sqrt(_last);
    }

private:
    EnvelopeFollower _envelope;
    float _last;
}

