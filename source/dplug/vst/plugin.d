module dplug.vst.plugin;

import dplug.vst.aeffectx;

class VSTPlugin 
{
public:
    AEffect _effect;
    HostCallbackFunction _hostCallback;

    this(HostCallbackFunction hostCallback) 
    {
        _hostCallback = hostCallback;

        _effect.magic = kEffectMagic;
        _effect.flags = effFlagsCanReplacing;
        _effect.numInputs = 0;
        _effect.numOutputs = 0;
        _effect.numParams = 0;
        _effect.numPrograms = 0;
        _effect.version_ = 1;
        _effect.uniqueID = CCONST('N', 'o', 'E', 'f');
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
        return 0;       
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
