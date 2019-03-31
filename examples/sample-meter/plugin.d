/**
Copyright: Elias Batek (0xEAB) 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
import dplug.core, dplug.client;
import core.stdc.stdio;

// This define entry points for plugin formats,
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!SampleMeter);

final class SampleMeter : dplug.client.Client
{
nothrow @nogc:

private:

    FILE* _log;
    int _previousFrames = -1; // -1 cannot occur in practice, so this makes a good default

public:

    this()
    {
        super();
        this._log = fopen("sample-meter.log", "a");
    }

    ~this()
    {
        this._log.fclose();
    }

public override:

    PluginInfo buildPluginInfo()
    {
        // Plugin info is parsed from plugin.json here at compile time.
        // Indeed it is strongly recommended that you do not fill PluginInfo
        // manually, else the information could diverge.
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        return params.releaseData();
    }

    LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io.pushBack(LegalIO(2, 2));
        return io.releaseData();
    }

    void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs)
    {
    }

    void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo)
    {
        // did frame-count change?
        if (frames != this._previousFrames)
        {
            // yes
            this._previousFrames = frames;
            this._log.fprintf("%d\n", frames);
            this._log.fflush();
        }

        outputs[0][0..frames] = inputs[0][0..frames];
        outputs[1][0..frames] = inputs[1][0..frames];
    }
}
