import std.math;
import dplug.core, dplug.client, dplug.vst;

// This create the DLL entry point
mixin(DLLEntryPoint!());

// This create the VST entry point
mixin(VSTEntryPoint!MSEncode);

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
        PluginInfo info;
        info.vendorName = "No Name Audio";
        info.vendorUniqueID = "NoAu";
        info.pluginName = "MSEncodator";
        info.pluginUniqueID = "NAms";
        info.pluginVersion = PluginVersion(1, 0, 0);
        info.isSynth = false;
        info.hasGUI = false;
        return info;
    }

    override Parameter[] buildParameters()
    {
        auto params = makeAlignedBuffer!Parameter();
        params.pushBack( mallocEmplace!BoolParameter(paramOnOff, "on/off", true) );
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeAlignedBuffer!LegalIO();
        io.pushBack(LegalIO(2, 2));
        return io.releaseData();
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        if (readBoolParamValue(paramOnOff))
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
