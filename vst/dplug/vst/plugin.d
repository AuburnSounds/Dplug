// See Steinberg VST license here: http://www.gersic.com/vstsdk/html/plug/intro.html#licence
module dplug.vst.plugin;

import core.stdc.stdlib,
       core.stdc.string;

import std.conv,
       std.typecons;

import dplug.plugin.client;

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

/// VST client wrapper
class VSTClient
{
public:
    AEffect _effect;
    VSTHost _host;
    Client _client;

    this(Client client, HostCallbackFunction hostCallback)
    {
        _host.init(hostCallback, &_effect);
        _client = client; // copy

        _effect = _effect.init;

        _effect.magic = kEffectMagic;
        _effect.flags = effFlagsCanReplacing;
        _effect.numInputs = 2;
        _effect.numOutputs = 2;
        _effect.numParams = cast(int)(client.params().length);
        _effect.numPrograms = 0;
        _effect.version_ = client.pluginVersion();
        _effect.uniqueID = client.uniqueID();
        _effect.processReplacing = &processReplacingCallback;
        _effect.dispatcher = &dispatcherCallback;
        _effect.setParameter = &setParameterCallback;
        _effect.getParameter = &getParameterCallback;
        _effect.user = cast(void*)(this);
        _effect.object = cast(void*)(this);
        _effect.processDoubleReplacing = null;

        //deprecated
        _effect.DEPRECATED_ioRatio = 1.0;
        _effect.DEPRECATED_process = &processCallback;
    }

    /// VST opcode dispatcher
    final VstIntPtr dispatcher(int opcode, int index, ptrdiff_t value, void *ptr, float opt)
    {
        // Important message from Cockos:
        // "Assume everything can (and WILL) run at the same time as your 
        // process/processReplacing, except:
        //   - effOpen/effClose
        //   - effSetChunk -- while effGetChunk can run at the same time as audio 
        //     (user saves project, or for automatic undo state tracking), effSetChunk 
        //     is guaranteed to not run while audio is processing.
        // So nearly everything else should be threadsafe."

        switch(opcode)
        {
            case effOpen:
                onOpen();
                return 0;

            case effClose:
                onClose();
                return 0;

            case effSetProgram:
                // TODO
                return 0;

            case effGetProgram:
                return 0; // TODO

            case effSetProgramName:
                return 0; // TODO

            case effGetProgramName:  // max 23 chars
            {
                // currently always return ""
                char* p = cast(char*)ptr;
                *p = '\0';
                return 0; // TODO
            }

            case effGetParamLabel:
            {
                char* p = cast(char*)ptr;
                if (!_client.isValidParamIndex(index))
                    *p = '\0';
                else
                    stringNCopy(p, 8, _client.param(index).label());
                return 0;
            }

            case effGetParamDisplay:
            {
                char* p = cast(char*)ptr;
                if (!_client.isValidParamIndex(index))
                    *p = '\0';
                else
                    _client.param(index).toStringN(p, 8);
                return 0;
            }

            case effGetParamName:
            { 
                char* p = cast(char*)ptr;
                if (!_client.isValidParamIndex(index))
                    *p = '\0';
                else
                    stringNCopy(p, 32, _client.param(index).name());
                return 0;
            }

            case effSetSampleRate:
                return 0; // TODO
           
            case effSetBlockSize:
                return 0; // TODO, give the maximum number of frames used in processReplacing

            case effMainsChanged:
                return 0; // TODO, plugin should clear its state

            case effEditGetRect:
            case effEditOpen:
            case effEditClose:
            case DEPRECATED_effEditDraw: 
            case DEPRECATED_effEditMouse: 
            case DEPRECATED_effEditKey: 
            case effEditIdle: 
            case DEPRECATED_effEditTop: 
            case DEPRECATED_effEditSleep: 
            case DEPRECATED_effIdentify: 
                return 0;

            case effGetChunk:
                return 0; // TODO

            case effSetChunk:
                return 0; // TODO

            case effProcessEvents:
                return 0; // TODO

            case effCanBeAutomated:
                return 1; // can always be automated

            case effString2Parameter:
                return 0; // TODO

            case DEPRECATED_effGetNumProgramCategories:
                return 1; // no real program categories

            case effGetProgramNameIndexed:
            {
                // currently always return ""
                char* p = cast(char*)ptr;
                *p = '\0';
                return 1; // TODO
            }

            case effProcessVarIo:
                return 0;

            case effGetPlugCategory:
                return kPlugCategEffect; // effect

            case effGetProductString:
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    strcpy(p, "lolg-plugin");
                }
                return 0;
            }

            case effCanDo:
                return -1; // can't do anything

            case effGetVstVersion:
                return 2400; // version 2.4

        default:
            return 0; // unknown opcode
        }
    }

    protected
    {
        void onOpen()
        {
        }

        void onClose()
        {
        }


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
            auto plugin = cast(VSTClient)(effect.user);
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
            auto plugin = cast(VSTClient)effect.user;
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
            auto plugin = cast(VSTClient)effect.user;
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
            auto plugin = cast(VSTClient)effect.user;
            Client client = plugin._client;

            if (index < 0)
                return;
            if (index >= client.params().length)
                return;

            return client.params()[index].set(parameter);
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
            auto plugin = cast(VSTClient)(effect.user);
            Client client = plugin._client;

            if (!client.isValidParamIndex(index))
                return 0.0f;

            return client.param(index).get();
        }
        catch (Throwable e)
        {
            unrecoverableError(); // should not throw in a callback

            // Still here? Return zero.
            return 0.0f;
        }
    }
}

// Copy source into dest.
// dest must contain room for maxChars characters
// A zero-byte character is then appended.
private void stringNCopy(char* dest, size_t maxChars, string source)
{
    if (maxChars == 0)
        return;

    size_t max = maxChars < source.length ? maxChars - 1 : source.length;
    for (int i = 0; i < max; ++i)
        dest[i] = source[i];
    dest[max] = '\0';
}