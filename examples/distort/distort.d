import std.math;

import dplug.plugin,
       dplug.vst;

mixin(DLLEntryPoint!());
mixin(VSTEntryPoint!Distort);

/// Example mono/stereo distortion plugin.
final class Distort : dplug.plugin.Client
{
    override Flags getFlags() pure const nothrow
    {
        return 0; // Not a synth, no GUI
    }

    override int getPluginID() pure const nothrow
    {
        return CCONST('g', 'f', 'm', '0'); // change this!
    }

    override void buildParameters()
    {
        addParameter(new FloatParameter("input", "db", 0.0f, 2.0f, 1.0f));
        addParameter(new FloatParameter("drive", "%", 1.0f, 2.0f, 1.0f));
        addParameter(new FloatParameter("output", "db", 0.0f, 1.0f, 0.9f));
    }

    override void buildLegalIO()
    {
        addLegalIO(1, 1);
        addLegalIO(1, 2);
        addLegalIO(2, 1);
        addLegalIO(2, 2);
    }

    override void reset(double sampleRate, size_t maxFrames)
    {
        // Clear here any state and delay buffers you might have.
    }

    override void processAudio(double **inputs, double **outputs, int frames) nothrow @nogc
    {
        int numInputs = maxInputs();
        int numOutputs = maxOutputs();

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        float inputGain = (cast(FloatParameter)param(0)).value();        
        float drive = (cast(FloatParameter)param(1)).value();
        float outputGain = (cast(FloatParameter)param(2)).value();

        for (int chan = 0; chan < minChan; ++chan)
            for (int f = 0; f < frames; ++f)
            {
                double input = inputGain * 2.0 * inputs[chan][f];
                double distorted = tanh(input * drive) / drive;
                outputs[chan][f] = outputGain * distorted;
            }

        // fill with zero the remaining channels
        for (int chan = minChan; chan < numOutputs; ++chan)
        {
            for (int f = 0; f < frames; ++f)
                outputs[chan][f] = 0;
        }
    }
}


