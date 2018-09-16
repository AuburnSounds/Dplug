/// This test shows how to use the runtime in a plug-in which
/// would have an need otherwise disabled runtime

import core.stdc.stdlib;
import dplug.core, dplug.client, dplug.vst;

// This create the DLL entry point
mixin(DLLEntryPoint!());

// This create the VST entry point
mixin(VSTEntryPoint!RuntimeTestPlugin);

final class RuntimeTestPlugin : dplug.client.Client
{
public:
nothrow:
@nogc:

    override PluginInfo buildPluginInfo()
    {
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io.pushBack(LegalIO(2, 2));
        return io.releaseData();
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) 
    {      
        // Note: this doesn't need to be `@nogc`
        int functionThatUseRuntime() nothrow 
        {
            // Note: here you can call runtime functions and stuff, however
            // keep in mind nothing GC-allocated must escape that function.
            // That limits applicability 

            // If you create garbage, this will be claimed at the end of this function
            // So this one line doesn't leak.
            float[] invalidMemory = new float[13];

            assert(invalidMemory.capacity != 0);

            return 1984;
        }

        // Note: this calls malloc, and need special clean-up
        auto runtimeUsingFunction = runtimeSection(&functionThatUseRuntime); 

        foreach(times; 0..10)
        {
            int result = runtimeUsingFunction();
            import core.stdc.stdio;
            assert(result = 1984);
            printf("%d\n", result);
        }

        finalizeRuntimeSection(runtimeUsingFunction); // this free the manual delegate context
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info)
    {    
        for (int n = 0; n < frames && n < _invalidMemory.length; ++n)
            outputs[0][n] = _invalidMemory[n];
    }

    float[] _invalidMemory;
}
