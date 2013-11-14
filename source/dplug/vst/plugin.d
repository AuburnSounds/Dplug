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
        _effect.processReplacing = &vstd_processReplacing;
        _effect.dispatcher = &vstd_dispacher;
        _effect.setParameter = &setParameterCallback;
        _effect.getParameter = &getParameterCallback;
        _effect.user = cast(void*)this;

        //deprecated
        _effect.DEPRECATED_ioRatio = 1.0;
        _effect.DEPRECATED_process = null;
    }

}



// VST callbacks

extern(C) nothrow
{
    VstIntPtr vstd_dispacher(AEffect *effect, int opcode, int index, int value, void *ptr, float opt) 
    {
        VSTPlugin plugin = cast(VSTPlugin)effect.user;

        return 0;
    }   

    void* vstd_process(AEffect *effect, float **inputs, float **outputs, int sampleFrames) 
    {
        VSTPlugin plugin = cast(VSTPlugin)effect.user;
        return null;
    }

    void vstd_processReplacing(AEffect *effect, float **inputs, float **outputs, int sampleFrames) 
    {
        VSTPlugin plugin = cast(VSTPlugin)effect.user;
    }

    void setParameterCallback(AEffect *effect, int index, float parameter) 
    {
        VSTPlugin plugin = cast(VSTPlugin)effect.user;        
    }

    float getParameterCallback(AEffect *effect, int index) 
    {
        VSTPlugin plugin = cast(VSTPlugin)effect.user;        
        return 0.0f;
    }
}
