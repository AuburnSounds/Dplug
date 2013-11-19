module dplug.vst.plugin;

import std.conv;

import dplug.vst.aeffectx,
       dplug.vst.host;


/// Use this mixin template to create the VST entry point
/// Example:
///     mixin VSTEntryPoint!MyVstPlugin;
mixin template VSTEntryPoint(alias VSTPluginClass, int uniqueID)
{
    enum size_t pluginSize =  __traits(classInstanceSize, VSTPluginClass);
    __gshared ubyte[pluginSize] pluginBytes;

    extern(C) private nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) 
    {
        if (hostCallback is null)
            return null;

        try
        {
            VSTPluginClass plugin = emplace!(VSTPluginClass)(pluginBytes[], hostCallback, uniqueID);
        }
        catch (Throwable e)
        {
            unrecoverableError(); // should not throw in a callback
            return null;
        }
        return &plugin._effect;
    }
}



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
        _effect.user = cast(void*)this;

        //deprecated
        _effect.DEPRECATED_ioRatio = 1.0;
        _effect.DEPRECATED_process = &processCallback;
    }

    VstIntPtr dispatcher(int opcode, int index, int value, void *ptr, float opt)
    {
        return 0; // TODO
    }
}

private void unrecoverableError() nothrow
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
            VSTPlugin plugin = cast(VSTPlugin)effect.user;
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
            VSTPlugin plugin = cast(VSTPlugin)effect.user;
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
            VSTPlugin plugin = cast(VSTPlugin)effect.user;
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
            VSTPlugin plugin = cast(VSTPlugin)effect.user;        
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
            VSTPlugin plugin = cast(VSTPlugin)effect.user;        
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
