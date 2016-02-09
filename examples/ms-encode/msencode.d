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
        info.isSynth = false;
        info.hasGUI = false;
        info.pluginID = CCONST('b', 'e', 'a', 'r');
        info.productName = "MS-Encode";
        info.effectName = "MS-Encode";
        info.vendorName = "Witty Audio";
        info.pluginVersion = 1000;
        return info;
    }

    override Parameter[] buildParameters()
    {
        return [ new BoolParameter(paramOnOff, "on/off", true) ];
    }

    override void buildLegalIO()
    {       
        addLegalIO(2, 2);
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {        
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        if (readBoolParamValue(paramOnOff))
        {
            outputs[0][0..frames] = ( (inputs[0][0..frames] + inputs[1][0..frames]) ) * SQRT1_2;
            outputs[1][0..frames] = ( (inputs[1][0..frames] - inputs[1][0..frames]) ) * SQRT1_2;
        }
        else
        {
            outputs[0][0..frames] = inputs[0][0..frames];
            outputs[1][0..frames] = inputs[1][0..frames];
        }
    }
}
