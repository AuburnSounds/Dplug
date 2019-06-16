/**
Copyright: Guillaume Piolat 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
import std.math;
import dplug.core, dplug.client, dplug.vst;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!MSEncode);

enum : int
{
    paramOnOff
}

/// Simplest VST plugin you could make.
final class MSEncode : dplug.client.Client
{
public:

    override PluginInfo buildPluginInfo()
    {
        // Plugin info is parsed from plugin.json here at compile time.
        // Indeed it is strongly recommended that you do not fill PluginInfo 
        // manually, else the information could diverge.
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        params ~= mallocNew!BoolParameter(paramOnOff, "on/off", true);
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(2, 2);
        return io.releaseData();
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        if (readParam!bool(paramOnOff))
        {
            outputs[0][0..frames] = ( (inputs[0][0..frames] + inputs[1][0..frames]) ) * SQRT1_2;
            outputs[1][0..frames] = ( (inputs[0][0..frames] - inputs[1][0..frames]) ) * SQRT1_2;
        }
        else
        {
            outputs[0][0..frames] = inputs[0][0..frames];
            outputs[1][0..frames] = inputs[1][0..frames];
        }
    }
}
