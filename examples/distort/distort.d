import std.math;

import dplug.plugin,
       dplug.vst;

/// Example mono/stereo distortion plugin.
final class Distort : dplug.plugin.Client
{
    override Flags getFlags() pure const nothrow
    {
        return 0; // Not a synth, no GUI
    }

    override int getPluginID() pure const nothrow
    {
        return CCONST('g', 'f', 'm', '0');
    }

    override void buildParameters()
    {
        addParameter(new Parameter("input", "db"));
        addParameter(new Parameter("drive", "%"));
        addParameter(new Parameter("output", "db"));
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
    }

    override void processAudio(double **inputs, double **outputs, int frames)
    {
        int numInputs = maxInputs();
        int numOutputs = maxOutputs();

        int minChan = numInputs > numOutputs ? numOutputs : numInputs;

        for (int chan = 0; chan < minChan; ++chan)
            for (int f = 0; f < frames; ++f)
            {
                double input = 2.0 * inputs[chan][f];
                double distorted = tanh(input);
                outputs[chan][f] = distorted;
            }

        // fill with zero the remaining channels
        for (int chan = minChan; chan < numOutputs; ++chan)
        {
            for (int f = 0; f < frames; ++f)
                outputs[chan][f] = 0;
        }
    }
}

__gshared VSTClient plugin;
__gshared Distort client;

extern (C) nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) 
{
    if (hostCallback is null)
        return null;

    try
    {
        auto client = new Distort();
        plugin = new VSTClient(client, hostCallback);
    }
    catch (Throwable e)
    {
        unrecoverableError(); // should not throw in a callback
        return null;
    }
    return &plugin._effect;
}

