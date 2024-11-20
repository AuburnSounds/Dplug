module main;

import dplug.core, dplug.client;
import gui;

mixin(pluginEntryPoints!MyClient);

final class MyClient : Client
{
public:
nothrow:
@nogc:

    this()
    {
    }

    ~this()
    {
    }

    override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();

        // ...
        // Add parameters here
        // ...

        return params.releaseData();
    }

    override void reset(double sampleRate,
                        int maxFrames,
                        int numInputs,
                        int numOutputs)
    {
        // ...
        // Add DSP initialization here
        // ...
    }

    override void processAudio(const(float*)[] inputs,
                               float*[]outputs,
                               int frames,
                               TimeInfo info)
    {

        // ...
        // Add signal processing here (DSP)
        // ...

        // Bypass
        outputs[0][0..frames] = inputs[0][0..frames];
        outputs[1][0..frames] = inputs[1][0..frames];
    }

    override PluginInfo buildPluginInfo()
    {
        // IMPORTANT change the values in plugin.json
        static immutable info = parsePluginInfo(import("plugin.json"));
        return info;
    }

    override IGraphics createGraphics()
    {
        return mallocNew!TemplateGUI(this);
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(2, 2);
        return io.releaseData();
    }
}

