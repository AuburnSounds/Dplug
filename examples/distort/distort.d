import dplug.vst;

import dplug.plugin;
import dplug.vst;

/// Example stereo distortion plugin.
final class Distort : dplug.plugin.Client
{
    override Flags getFlags()
    {
        return 0; // Not a synth, no GUI
    }

    override int getPluginID()
    {
        return CCONST('l', 'o', 'l', 'd');
    }

    override void buildParameters()
    {
        addParameter(new Parameter("input", "db"));
        addParameter(new Parameter("drive", "%"));
        addParameter(new Parameter("output", "db"));
    }

    /// Override to clear state state (eg: delay lines) and allocate buffers.
    override void reset(double sampleRate, size_t maxFrames)
    {
    }

    /// Process some audio.
    /// Override to make some noise.
    override void processAudio(double **inputs, double **outputs, int frames)
    {
        for (int i = 0; i < frames; ++i)
        {
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

