/**
* Copyright: Copyright Auburn Sounds 2015-2017
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module main;

import std.math;

import dplug.core,
       dplug.client,
       dplug.dsp;

import gui;

mixin(DLLEntryPoint!());

version(VST)
{
    import dplug.vst;
    mixin(VSTEntryPoint!DistortClient);
}

version(AU)
{
    import dplug.au;
    mixin(AUEntryPoint!DistortClient);
}

enum : int
{
    paramInput,
    paramDrive,
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
        params.pushBack( mallocNew!GainParameter(paramInput, "input", 6.0, 0.0) );
        params.pushBack( mallocNew!LinearFloatParameter(paramDrive, "drive", "%", 1.0f, 2.0f, 1.0f) );
        params.pushBack( mallocNew!GainParameter(paramOutput, "output", 6.0, 0.0) );
        params.pushBack( mallocNew!BoolParameter(paramOnOff, "on/off", true) );
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

        static immutable float[] silenceParams = [0.0f, 0.0f, 0.0f, 1.0f, 0];
        presets.pushBack( mallocNew!Preset("Silence", silenceParams) );

        static immutable float[] fullOnParams = [1.0f, 1.0f, 0.4f, 1.0f, 0];
        presets.pushBack( mallocNew!Preset("Full-on", fullOnParams) );
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

        foreach(channel; 0..2)
        {
            _inputRMS[channel].initialize(sampleRate);
            _outputRMS[channel].initialize(sampleRate);
        }
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames,
                               TimeInfo info) nothrow @nogc
    {
        assert(frames <= 512); // guaranteed by audio buffer splitting

        int numInputs = cast(int)inputs.length;
        int numOutputs = cast(int)outputs.length;

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        float inputGain = deciBelToFloat(readFloatParamValue(paramInput));
        float drive = readFloatParamValue(paramDrive);
        float outputGain = deciBelToFloat(readFloatParamValue(paramOutput));

        bool enabled = readBoolParamValue(paramOnOff);

        float[2] RMS = 0;

        if (enabled)
        {
            for (int chan = 0; chan < minChan; ++chan)
            {
                for (int f = 0; f < frames; ++f)
                {
                    float inputSample = inputGain * 2.0 * inputs[chan][f];

                    // Feed the input RMS computation
                    _inputRMS[chan].nextSample(inputSample);

                    // Distort signal
                    float distorted = tanh(inputSample * drive) / drive;
                    float outputSample = outputGain * distorted;
                    outputs[chan][f] = outputSample;

                    // Feed the output RMS computation
                    _outputRMS[chan].nextSample(outputSample);
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
            float[2] inputLevels;
            inputLevels[0] = floatToDeciBel(_inputRMS[0].RMS());
            inputLevels[1] = minChan >= 1 ? floatToDeciBel(_inputRMS[1].RMS()) : inputLevels[0];
            gui.inputBargraph.setValues(inputLevels);

            float[2] outputLevels;
            outputLevels[0] = floatToDeciBel(_outputRMS[0].RMS());
            outputLevels[1] = minChan >= 1 ? floatToDeciBel(_outputRMS[1].RMS()) : outputLevels[0];
            gui.outputBargraph.setValues(outputLevels);

            graphicsRelease();
        }
    }

    override IGraphics createGraphics()
    {
        return mallocNew!DistortGUI(this);
    }

private:
    CoarseRMS!float[2] _inputRMS;
    CoarseRMS!float[2] _outputRMS;
}

