/// This test shows how to use the runtime in a plug-in which
/// would have an otherwise disabled runtime
///
/// ============================================================================
///
///         VERY IMPORTANT MESSAGE
///     This is a bit of an experimental feature!
///
///     1. You can't use it with DMD + macOS. Because DMD doesn't support 
///        shared library initialization on macOS.
///
///     2. It is yet unknown how far Mac compatibility is broken by using 
///        the runtime. It is known to work since macOS 10.12 with LDC >= 1.3
///        but we don't have the data for previous macOS versions.
///
///     3. The behaviour on POSIX in presence of multiple instances is yet unknown.
///        Please let us know.
///
/// ============================================================================
module main;

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

    // <needed for runtime> This is required so that the rest of the plug-in can make runtime calls.
    ScopedRuntime _runtime;
    this()
    {
        _runtime.initialize();
    }
    // </needed for runtime>

    // Needed for the removal of _heapObject which was added as root.
    // So this has to be mirrored.
    //
    // Note: You are subjected to the classical D limitation with regards
    //       to the order of finalization of GC objects.
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

            // Here you can create garbage
            float[] invalidMemory = new float[13];
            assert(invalidMemory.capacity != 0);
            
            if (obj is null) 
            {
                // Allocate an object on the GC heap
                obj = new HeapObject;

                // Make it survive the end of the Runtime Section by being referenced elsewhere
                // (than the stack of this thread)
                GC.addRoot(cast(void*)obj);
            }

            return 1984;
        }

        // Note: this returns a callable Voldemort from a GC-using delegate
        // However this delegate should not have a GC closure, so you can't refer to _members.
        // This is a stark limitation, sorry.
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
            // Anyway it's UB to read it and I'm not sure you can really catch it in the first place.
            //printf("%s\n", e.msg.ptr);
        }
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info)
    {    
        for (int n = 0; n < frames && n < _invalidMemory.length; ++n)
            outputs[0][n] = _invalidMemory[n];
    }

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

