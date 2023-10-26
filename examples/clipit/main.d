/**
Copyright: Guillaume Piolat 2015-2017.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module main;

import std.math;

import dplug.core,
       dplug.dsp,
       dplug.client;

import gui;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!ClipitClient);

enum : int
{
    paramInputGain,
    paramClip,
    paramOutputGain,
    paramMix,
    paramMode,
    paramBassBoost
}


/// Example mono/stereo distortion plugin.
final class ClipitClient : dplug.client.Client
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
    // in the same order as the parameter enum.
    override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        params ~= mallocNew!LinearFloatParameter(paramInputGain, "input gain", "dB", -12.0f, 12.0f, 0.0f) ;
        params ~= mallocNew!LinearFloatParameter(paramClip, "clip", "%", 0.0f, 100.0f, 0.0f) ;
        params ~= mallocNew!LinearFloatParameter(paramOutputGain, "output gain", "db", -12.0f, 12.0f, 0.0f) ;
        params ~= mallocNew!LinearFloatParameter(paramMix, "mix", "%", 0.0f, 100.0f, 100.0f) ;
        params ~= mallocNew!BoolParameter(paramMode, "mode", false);
        params ~= mallocNew!LinearFloatParameter(paramBassBoost, "bass boost", "db", 0.0f, 6.0f, 0.0f) ;
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(1, 1);
        io ~= LegalIO(2, 2);
        return io.releaseData();
    }

    // This override is optional, the default implementation will
    // have one default preset.
    override Preset[] buildPresets()
    {
        auto presets = makeVec!Preset();
        presets ~= makeDefaultPreset();
        return presets.releaseData();
    }

    // This override is also optional. It allows to split audio buffers in order to never
    // exceed some amount of frames at once.
    // This can be useful as a cheap chunking for parameter smoothing.
    // Buffer splitting also allows to allocate statically or on the stack with less worries.
    override int maxFramesInProcess()
    {
        return 512;
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) 
    {
        // Clear here any state and delay buffers you might have.
        assert(maxFrames <= 512); // guaranteed by audio buffer splitting
        assert(numInputs == numOutputs);

        _sampleRate = sampleRate;

        foreach(chan; 0..numInputs)
            _bassFilter[chan].initialize();
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info)
    {
        assert(frames <= 512); // guaranteed by audio buffer splitting

        int numInputs = cast(int)inputs.length;
        int numOutputs = cast(int)outputs.length;

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        /// Read parameter values
        /// Convert decibel values to floating point
        immutable float inputGain = pow(10, readParam!float(paramInputGain) /20);
        immutable float outputGain = pow(10, readParam!float(paramOutputGain) /20);

        float bassBoost_dB = readParam!float(paramBassBoost);

        immutable float mix = readParam!float(paramMix) / 100.0f;

        immutable bool hardClip = readParam!bool(paramMode);

        float clipAmount;
        float clipInv;
        if(hardClip)
        {
            clipAmount = 1 - (readParam!float(paramClip) / 100.0f);

            // Clamp clipAmount to ensure it is never 0
            if (clipAmount < 0.1f)
                clipAmount = 0.1f;
        }
        else
        {
            clipAmount = readParam!float(paramClip) / 3;
            clipInv = 1 / clipAmount;
        }

        for (int chan = 0; chan < minChan; ++chan)
        {
            // Copy to output, since output buffers are read/write unlike input buffers.
            outputs[chan][0..frames] = inputs[chan][0..frames];

            // Apply bass boost
            BiquadCoeff bassBoostCoeff = biquadRBJLowShelf(250, _sampleRate, bassBoost_dB);
            _bassFilter[chan].nextBuffer(outputs[chan], outputs[chan], frames, bassBoostCoeff);

            for (int f = 0; f < frames; ++f)
            {
                float inputSample  = outputs[chan][f] * inputGain;
                float outputSample = inputSample;

                /// Hard clip mode
                if(hardClip)
                {
                    if(outputSample > clipAmount)
                        outputSample = clipAmount;
                    if(outputSample < -clipAmount)
                        outputSample = -clipAmount;
                }
                /// Soft clip mode
                else
                {
                    /// Clip the signal
                    if(clipAmount > 0)
                        outputSample = clipInv * atan( outputSample * clipAmount);
                }

                outputs[chan][f] = ((outputSample * mix) + (inputSample * (1 - mix))) * outputGain;

            }
        }

        // fill with zero the remaining channels
        for (int chan = minChan; chan < numOutputs; ++chan)
            outputs[chan][0..frames] = 0; // D has array slices assignments and operations

        /// Get access to the GUI
        if (ClipitGUI gui = cast(ClipitGUI) graphicsAcquire())
        {
            /// This is where you would update any elements in the gui
            /// such as feeding values to meters.

            graphicsRelease();
        }
    }

    override IGraphics createGraphics()
    {
        return mallocNew!ClipitGUI(this);
    }

private:

    float _sampleRate;
    BiquadDelay[2] _bassFilter;
    
}

