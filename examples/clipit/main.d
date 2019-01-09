/**
Copyright: Guillaume Piolat 2015-2017.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module main;

import std.math;
import std.algorithm;

import dplug.core,
       dplug.client;

import gui;

mixin(DLLEntryPoint!());

version(VST)
{
    import dplug.vst;
    mixin(VSTEntryPoint!ClipitClient);
}

version(AU)
{
    import dplug.au;
    mixin(AUEntryPoint!ClipitClient);
}

version(LV2)
{
    import dplug.lv2;
    mixin(LV2EntryPoint!ClipitClient);
}

enum : int
{
    paramInputGain,
    paramClip,
    paramOutputGain,
    paramMix,
    paramMode,
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
        params.pushBack( mallocNew!LinearFloatParameter(paramInputGain, "input gain", "dB", -12.0f, 12.0f, 0.0f) );
        params.pushBack( mallocNew!LinearFloatParameter(paramClip, "clip", "%", 0.0f, 100.0f, 0.0f) );
        params.pushBack( mallocNew!LinearFloatParameter(paramOutputGain, "output gain", "db", -12.0f, 12.0f, 0.0f) );
        params.pushBack( mallocNew!LinearFloatParameter(paramMix, "mix", "%", 0.0f, 100.0f, 100.0f) );
        params.pushBack( mallocNew!BoolParameter(paramMode, "mode", false));
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io.pushBack(LegalIO(1, 1));
        io.pushBack(LegalIO(1, 2));
        io.pushBack(LegalIO(2, 1));
        io.pushBack(LegalIO(2, 2));
        return io.releaseData();
    }

    // This override is optional, the default implementation will
    // have one default preset.
    override Preset[] buildPresets() nothrow @nogc
    {
        auto presets = makeVec!Preset();
        presets.pushBack( makeDefaultPreset() );
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
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames,
                               TimeInfo info) nothrow @nogc
    {
        assert(frames <= 512); // guaranteed by audio buffer splitting

        int numInputs = cast(int)inputs.length;
        int numOutputs = cast(int)outputs.length;

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        /// Read parameter values
        /// Convert decibel values to floating point
        immutable float inputGain = pow(10, readFloatParamValue(paramInputGain) /20);
        immutable float outputGain = pow(10, readFloatParamValue(paramOutputGain) /20);

        immutable float mix = readFloatParamValue(paramMix) / 100.0f;

        immutable bool hardClip = readBoolParamValue(paramMode);

        float clipAmount;
        float clipInv;
        if(hardClip)
        {
            clipAmount = 1 - (readFloatParamValue(paramClip) / 100.0f);
            /// Clamp clipAmount to ensure it is never 0
            clipAmount = clamp(clipAmount, 0.1, 1);
        }
        else
        {
            clipAmount = readFloatParamValue(paramClip) / 3;
            clipInv = 1 / clipAmount;
        }

        for (int chan = 0; chan < minChan; ++chan)
        {
            for (int f = 0; f < frames; ++f)
            {
                float inputSample = inputs[chan][f] * inputGain;

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
    
}

