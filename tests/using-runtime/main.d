/// This test shows how to use the runtime in a plug-in which
/// would have an need otherwise disabled runtime

import core.memory;
import std.stdio;
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

    // TODO check POSIX runtime cleanup and multiple instances

    // <needed for runtime> This is required so that the rest of the plug-in can make runtime calls.
    ScopedRuntime _runtime;
    this()
    {
        _runtime.initialize();
    }
    // </needed for runtime>

    // needed for the removal of _heapObject
    // this has to be mirrored
    ~this()
    {       
        runtimeSection(&cleanupObject)(_heapObject);
    }

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
        // Note: this doesn't need to be `@nogc`.
        // This has to be a delegate, not a raw function pointer.
        int functionThatUseRuntime(ref HeapObject obj) nothrow 
        {
            // Note: here you can call runtime functions and stuff, however
            // keep in mind nothing GC-allocated must escape that function.
            // That limits applicability 

            // If you create garbage, this will be claimed at the end of this function
            // So this one line doesn't leak.
            float[] invalidMemory = new float[13];
            assert(invalidMemory.capacity != 0);
            
            // Allocate an object on the GC heap
            if (obj is null) 
            {
                obj = new HeapObject;            
                // Make it survive the end of the Runtime Section by being referenced elsewhere
                GC.addRoot(cast(void*)obj);
            }

            return 1984;
        }

        // Note: this returns a callable Voldemort from a GC-using delegate
        // However this delegate should not have a GC closure, so you can't refer to _members.
        auto runtimeUsingFunction = runtimeSection(&functionThatUseRuntime);
        int result = runtimeUsingFunction(_heapObject);
        assert(result == 1984);
    
        // You can call stand-alone functions or methods
        try
        {
            size_t len = runtimeSection(&myCarelessFunction)(false);
            assert(len == 4000);
            len = runtimeSection(&myCarelessFunction)(true);            
        }
        catch(Exception e)
        {
            // for some reason the Exception allocated in the runtime section hasn't been 
            // collected, not sure why
            // Anyway it's UB to read it
            //printf("%s\n", e.msg.ptr);
        }
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info)
    {    
        for (int n = 0; n < frames && n < _invalidMemory.length; ++n)
            outputs[0][n] = _invalidMemory[n];
    }

    float[] _invalidMemory;

    HeapObject _heapObject;
}

class HeapObject
{
    this() nothrow
    {
        try
        {
            writeln("Creating a GC object");
        }
        catch(Exception e)
        {
        }
    }

    ~this() nothrow
    {
        try
        {
            writeln("Destroying a GC object");
        }
        catch(Exception e)
        {
        }
    }
}

static void cleanupObject(ref HeapObject obj) nothrow
{
    if (obj !is null) 
    {
        GC.removeRoot(cast(void*)obj);
        obj = null;
    }
}

size_t myCarelessFunction(bool doThrow)
{
    auto A = new ubyte[4000];
    if (doThrow)
        throw new Exception("an error!");
    else
        return A.length;
}

