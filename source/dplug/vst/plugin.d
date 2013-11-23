module dplug.vst.plugin;

import core.stdc.stdlib;

import std.conv,
       std.typecons;

import dplug.vst.aeffectx,
       dplug.vst.host;

//T* emplace(T, Args...)(T* chunk, auto ref Args args)
T mallocEmplace(T, Args...)(auto ref Args args)
{
    size_t len = __traits(classInstanceSize, T);
    void* p = cast(void*)malloc(len);
    return emplace!(T, Args)(p[0..len], args);
}

/// Use this mixin template to create the VST entry point
/// Example:
///     mixin VSTEntryPoint!MyVstPlugin;

// BUG: Unfortunately, can't export this function from a mixin template.
// Copy it by hand.
/+
mixin template VSTEntryPoint(alias VSTPluginClass, int uniqueID)
{
    __gshared VSTPluginClass plugin;

    extern (Windows) nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) 
    {
        if (hostCallback is null)
            return null;

        try
        {
            plugin = mallocEmplace!(VSTPluginClass, HostCallbackFunction, int)(hostCallback, uniqueID);
        }
        catch (Throwable e)
        {
            unrecoverableError(); // should not throw in a callback
            return null;
        }
        return &plugin._effect;
    }
}
+/
class VSTPlugin 
{
public:
    AEffect _effect;
    VSTHost _host;

    this(HostCallbackFunction hostCallback, int uniqueID) 
    {
        _host.init(hostCallback, &_effect);

        _effect.magic = kEffectMagic;
        _effect.flags = effFlagsCanReplacing;
        _effect.numInputs = 0;
        _effect.numOutputs = 0;
        _effect.numParams = 0;
        _effect.numPrograms = 0;
        _effect.version_ = 1;
        _effect.uniqueID = uniqueID;
        _effect.processReplacing = &processReplacingCallback;
        _effect.dispatcher = &dispatcherCallback;
        _effect.setParameter = &setParameterCallback;
        _effect.getParameter = &getParameterCallback;
        _effect.user = cast(void*)(&this);

        //deprecated
        _effect.DEPRECATED_ioRatio = 1.0;
        _effect.DEPRECATED_process = &processCallback;
    }

    VstIntPtr dispatcher(int opcode, int index, int value, void *ptr, float opt)
    {
        switch(opcode)
        {
            case effProcessEvents:
                // TODO: process events

                break;

            case effCanBeAutomated:
                // return 1 if param index can be automated
                return 0;

            case effString2Parameter:
            case DEPRECATED_effGetNumProgramCategories:
            case effGetProgramNameIndexed:
            case DEPRECATED_effCopyProgram:
            case DEPRECATED_effConnectInput:
            case DEPRECATED_effConnectOutput:
            case effGetInputProperties:
            case effGetOutputProperties:
            case effGetPlugCategory:
            case DEPRECATED_effGetCurrentPosition:
            case DEPRECATED_effGetDestinationBuffer:
            case effOfflineNotify:
            case effOfflinePrepare:
            case effOfflineRun:
            case effProcessVarIo:
            case effSetSpeakerArrangement:
            case DEPRECATED_effSetBlockSizeAndSampleRate:
            case effSetBypass:
            case effGetEffectName:
            case DEPRECATED_effGetErrorText:
            case effGetVendorString:
            case effGetProductString:
            case effGetVendorVersion:
            case effVendorSpecific:
            case effCanDo:
            case effGetTailSize:
            case DEPRECATED_effIdle:
            case DEPRECATED_effGetIcon:
            case DEPRECATED_effSetViewPosition:
            case effGetParameterProperties:
            case DEPRECATED_effKeysRequired:
            case effGetVstVersion:

            case effEditKeyDown:
            case effEditKeyUp:
            case effSetEditKnobMode:
            case effGetMidiProgramName:
            case effGetCurrentMidiProgram:
            case effGetMidiProgramCategory:
            case effHasMidiProgramsChanged:
            case effGetMidiKeyName:
            case effBeginSetProgram:
            case effEndSetProgram:
            case effGetSpeakerArrangement:   
            case effShellGetNextPlugin:      
            case effStartProcess:
            case effStopProcess:
            case effSetTotalSampleToProcess:
            case effSetPanLaw: 
            case effBeginLoadBank:
            case effBeginLoadProgram:
            case effSetProcessPrecision:
            case effGetNumMidiInputChannels:
            case effGetNumMidiOutputChannels:
            return 0; // unknown opcode

        default:
            return 0; // unknown opcode
        }

        return 0; // TODO
    }
}

void unrecoverableError() nothrow
{
    debug
    {
        assert(false); // crash the Host in debug mode
    }
    else
    {
        // forget about the error since it doesn't seem a good idea
        // to crash in audio production
    }
}

// VST callbacks

extern(C) private nothrow
{
    VstIntPtr dispatcherCallback(AEffect *effect, int opcode, int index, int value, void *ptr, float opt) 
    {
        try
        {
            auto plugin = cast(VSTPlugin*)effect.user;
            return plugin.dispatcher(opcode, index, value, ptr, opt);
        }
        catch (Throwable e)
        {
            unrecoverableError(); // should not throw in a callback
        }
        return 0;
    }   

    void processCallback(AEffect *effect, float **inputs, float **outputs, int sampleFrames) 
    {
        try
        {
            auto plugin = cast(VSTPlugin*)effect.user;
        }
        catch (Throwable e)
        {
            unrecoverableError(); // should not throw in a callback
        }
    }

    void processReplacingCallback(AEffect *effect, float **inputs, float **outputs, int sampleFrames) 
    {
        try
        {
            auto plugin = cast(VSTPlugin*)effect.user;
        }
        catch (Throwable e)
        {
            unrecoverableError(); // should not throw in a callback
        }
    }

    void setParameterCallback(AEffect *effect, int index, float parameter) 
    {
        try
        {
            auto plugin = cast(VSTPlugin*)effect.user;        
        }
        catch (Throwable e)
        {
            unrecoverableError(); // should not throw in a callback
        }        
    }

    float getParameterCallback(AEffect *effect, int index) 
    {
        try
        {
            auto plugin = cast(VSTPlugin*)effect.user;        
            return 0.0f;
        }
        catch (Throwable e)
        {
            unrecoverableError(); // should not throw in a callback

            // Still here? Return zero.
            return 0.0f;
        }
    }
}
