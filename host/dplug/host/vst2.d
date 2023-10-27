/**
VST 2.4 host implementation.

Copyright: Auburn Sounds 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.host.vst2;

import core.stdc.string: strlen, memset;
import dplug.core.sharedlib;
import dplug.core.nogc;
import dplug.core.vec;
import dplug.host.host;
import dplug.vst2;

nothrow @nogc:

alias VSTPluginMain_t = extern(C) void* function(void* fun);

/// Returns: a VST2 entry point, or `null` in case of errors.
VSTPluginMain_t getVST2EntryPoint(ref SharedLib lib)
{
    void* result = null;

    void tryEntryPoint(string name)
    {
        if (result != null)
            return;

        if (lib.hasSymbol(name))
            result = lib.loadSymbol(name);
        else
            result = null;
    }
    tryEntryPoint("VSTPluginMain");
    tryEntryPoint("main_macho");
    tryEntryPoint("main");

    if (result == null)
        return null; // Did not find a VST entry point
    else
        return cast(VSTPluginMain_t)result;
}

version(VST2):

final class VST2PluginHost : IPluginHost
{
nothrow @nogc:

    // Note: in case of error, it's OK the object will be partially constructed and
    // its destructor can be called.
    this(SharedLibHandle lib, bool* err)
    {
        *err = true;
        _lib.initializeWithHandle(lib);

        VSTPluginMain_t VSTPluginMain = getVST2EntryPoint(_lib);
        if (VSTPluginMain is null)
            return;

        HostCallbackFunction hostFun = &hostCallback;

        AEffect* aeffect = cast(AEffect*) VSTPluginMain(hostFun);

        // various checks
        if (aeffect.magic != 0x56737450) /* 'VstP' */
            return; // Wrong VST magic number
        if (aeffect.dispatcher == null)
            return; // aeffect.dispatcher is null
        if (aeffect.setParameter == null)
            return; // aeffect.setParameter is null
        if (aeffect.getParameter == null)
            return; // aeffect.getParameter is null

        // aeffect passed those basic checks
        _aeffect = aeffect;
        _aeffect.resvd2 = cast(size_t) cast(void*) this;

        _dispatcher = _aeffect.dispatcher;

        // open plugin
        _dispatcher(_aeffect, effOpen, 0, 0, null, 0.0f);
        _parameterNames.reallocBuffer(33 * _aeffect.numParams);

        // get initial latency
        updateLatency();

        *err = false;
    }

    override void close()
    {
        // not used anymore (remove in Dplug v15), destructor does this instead
    }

    // This destructor must handle a partially constructed object!
    ~this()
    {
        // close plugin
        if (_aeffect !is null)
        {
            // Cannot close VST plugin while not suspended
            // This is a programming error.
            assert (_suspended); 

            // close plugin
            _dispatcher(_aeffect, effClose, 0, 0, null, 0.0f);
            
            // remove mapping
            // TODO Is this safe though? What if the host is still calling audio processing?
            _aeffect.resvd2 = 0;

            _aeffect = null;
        }

        _lib.unload();
    }

    override void setParameter(int paramIndex, float normalizedValue)
    {
        _aeffect.setParameter(_aeffect, paramIndex, normalizedValue);
    }

    override float getParameter(int paramIndex)
    {
        return _aeffect.getParameter(_aeffect, paramIndex);
    }

    override const(char)[] getParameterName(int paramIndex)
    {
        char* buf = &_parameterNames[33 * paramIndex];
        _dispatcher(_aeffect, effGetParamName, paramIndex, 0, buf, 0.0f);
        return buf[0..strlen(buf)];
    }

    override int getParameterCount()
    {
        return _aeffect.numParams;
    }

    override const(char)[] getVendorString()
    {
        _dispatcher(_aeffect, effGetVendorString, 0, 0, _vendorString.ptr, 0.0f);
        return _vendorString[0..strlen(_vendorString.ptr)];
    }

    override const(char)[] getEffectName()
    {   
        _dispatcher(_aeffect, effGetEffectName, 0, 0, _effectName.ptr, 0.0f);
        return _effectName[0..strlen(_effectName.ptr)];
    }

    override const(char)[] getProductString()
    {        
        _dispatcher(_aeffect, effGetProductString, 0, 0, _productString.ptr, 0.0f);
        return _productString[0..strlen(_productString.ptr)];
    }

    override void processAudioFloat(float** inputs, float** outputs, int samples)
    {
        assert (!_suspended);
        _aeffect.processReplacing(_aeffect, inputs, outputs, samples);
        _processedSamples += samples;
    }

    override void beginAudioProcessing()
    {
        _dispatcher(_aeffect, effMainsChanged, 0, 1, null, 0.0f);
        _suspended = false;
        updateLatency();
    }

    override void endAudioProcessing()
    {
        _dispatcher(_aeffect, effMainsChanged, 0, 0, null, 0.0f);
        _suspended = true;
    }

    override bool setIO(int numInputs, int numOutputs)
    {
        assert(numInputs <= 8 && numOutputs <= 8);
        VstSpeakerArrangement pInputArr, pOutputArr;
        memset(&pInputArr, 0, pInputArr.sizeof);
        memset(&pOutputArr, 0, pOutputArr.sizeof);
        pInputArr.type = kSpeakerArrEmpty;
        pOutputArr.type = kSpeakerArrEmpty;
        pInputArr.numChannels = numInputs;
        pOutputArr.numChannels = numOutputs;

        size_t value = cast(size_t)(&pInputArr);
        void* ptr = cast(void*)(&pOutputArr);
        _dispatcher(_aeffect, effSetSpeakerArrangement, 0, value, ptr, 0.0f);

        // Dplug Issue #186: effSetSpeakerArrangement always says no
        // so we return "yes" here, compounded bug
        return true;
    }

    override void setSampleRate(float sampleRate)
    {
        assert(_suspended); // FUTURE: report success or error
        _dispatcher(_aeffect, effSetSampleRate, 0, 0, null, sampleRate);
    }

    override void setMaxBufferSize(int samples)
    {
        assert(_suspended); // FUTURE: report success or error
        _dispatcher(_aeffect, effSetBlockSize, 0, cast(VstIntPtr)samples, null, 0.0f);
    }

    override void loadPreset(int presetIndex)
    {
        _dispatcher(_aeffect, effSetProgram, 0, cast(ptrdiff_t)(presetIndex), null, 0.0f);
    }

    override void openUI(void* windowHandle)
    {
        _dispatcher(_aeffect, effEditOpen, 0, 0, windowHandle, 0.0f);
    }

    override void closeUI()
    {
        _dispatcher(_aeffect, effEditClose, 0, 0, null, 0.0f);
    }

    override int[2] getUISize()
    {
        ERect* rect;
        _dispatcher(_aeffect, effEditGetRect, 0, 0, &rect, 0.0f);
        int[2] size;
        size[0] = rect.right - rect.left;
        size[1] = rect.bottom - rect.top;
        return size;
    }

    override const(ubyte)[] saveState()
    {
        if (_aeffect.flags && effFlagsProgramChunks)
        {
            ubyte* pChunk = null;
            VstIntPtr size = _dispatcher(_aeffect, effGetChunk, 0 /* want a bank */, 0, &pChunk, 0.0f);

            if (size == 0 || pChunk == null)
                return null; // bug in client, effGetChunk returned an empty chunk

            // Local copy
            _lastStateChunkOutput.resize(size);
            _lastStateChunkOutput[][0..size] = pChunk[0..size];

            return _lastStateChunkOutput[];
        }
        else
            return null;

    }

    override bool restoreState(const(ubyte)[] chunk)
    {
        if (chunk is null)
            return false;
        size_t size = chunk.length;

        _lastStateChunkInput.resize(size);
        _lastStateChunkInput[][0..size] = chunk[0..size];

        VstIntPtr result = _dispatcher(_aeffect, 
                                       effSetChunk, 
                                       0 /* want a bank */, 
                                       _lastStateChunkInput.length, 
                                       _lastStateChunkInput.ptr, 
                                       0.0f);
        if (result != 1)
            return false; // effSetChunk failed
        else
            return true;
    }

    override int getCurrentProgram()
    {
        return cast(int)( _dispatcher(_aeffect, effGetProgram, 0, 0, null, 0.0f) );
    }

    override int getLatencySamples()
    {
        return _currentLatencySamples;
    }

    override double getTailSizeInSeconds()
    {
        double r = cast(double) _dispatcher(_aeffect, effGetTailSize, 0, 0, null, 0.0f);
        return r;
    }

private:
    SharedLib _lib;
    AEffect* _aeffect;
    AEffectDispatcherProc _dispatcher;
    long _processedSamples;
    VstTimeInfo timeInfo;
    bool _suspended = true;
    int _currentLatencySamples;

    char[] _parameterNames; // 33 x paramlength names.
    char[65] _productString;
    char[65] _vendorString;
    char[65] _effectName; 

    // Using Vec to avoid allocating down.
    Vec!ubyte _lastStateChunkOutput;
    Vec!ubyte _lastStateChunkInput;

    void updateLatency()
    {
        _currentLatencySamples = _aeffect.initialDelay;
    }
}

extern(C) nothrow @nogc VstIntPtr hostCallback(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt)
{
    import core.stdc.stdio;

    // unimplemented stuff will printf

    switch(opcode)
    {
        case audioMasterAutomate: printf("audioMasterAutomate\n"); return 0;
        case audioMasterVersion: return 2400;
        case audioMasterCurrentId: printf("audioMasterCurrentId\n"); return 0;
        case audioMasterIdle: printf("audioMasterIdle\n"); return 0;
        case DEPRECATED_audioMasterPinConnected: printf("DEPRECATED_audioMasterPinConnected\n"); return 0;
        case DEPRECATED_audioMasterWantMidi: return 0;
        case audioMasterGetTime:
        {
            VST2PluginHost phost = cast(VST2PluginHost) cast(void*) effect.resvd2;
            if (!phost)
                return 0;

            phost.timeInfo.samplePos = phost._processedSamples;
            phost.timeInfo.flags = 0;

            return cast(VstIntPtr)(&phost.timeInfo);
        }
        case audioMasterProcessEvents: printf("audioMasterProcessEvents\n"); return 0;
        case DEPRECATED_audioMasterSetTime: printf("DEPRECATED_audioMasterSetTime\n"); return 0;
        case DEPRECATED_audioMasterTempoAt: printf("DEPRECATED_audioMasterTempoAt\n"); return 0;
        case DEPRECATED_audioMasterGetNumAutomatableParameters: printf("DEPRECATED_audioMasterGetNumAutomatableParameters\n"); return 0;
        case DEPRECATED_audioMasterGetParameterQuantization: printf("DEPRECATED_audioMasterGetParameterQuantization\n"); return 0;
        case audioMasterIOChanged: printf("audioMasterIOChanged\n"); return 0;
        case DEPRECATED_audioMasterNeedIdle: printf("DEPRECATED_audioMasterNeedIdle\n"); return 0;
        case audioMasterSizeWindow: printf("audioMasterSizeWindow\n"); return 0;
        case audioMasterGetSampleRate: printf("audioMasterGetSampleRate\n"); return 0;
        case audioMasterGetBlockSize: printf("audioMasterGetBlockSize\n"); return 0;
        case audioMasterGetInputLatency: printf("audioMasterGetInputLatency\n"); return 0;
        case audioMasterGetOutputLatency: printf("audioMasterGetOutputLatency\n"); return 0;
        case DEPRECATED_audioMasterGetPreviousPlug: printf("DEPRECATED_audioMasterGetPreviousPlug\n"); return 0;
        case DEPRECATED_audioMasterGetNextPlug: printf("DEPRECATED_audioMasterGetNextPlug\n"); return 0;
        case DEPRECATED_audioMasterWillReplaceOrAccumulate: printf("DEPRECATED_audioMasterWillReplaceOrAccumulate\n"); return 0;

        case audioMasterGetCurrentProcessLevel: 
            return 2; /* kVstProcessLevelRealtime */

        case audioMasterGetAutomationState: printf("audioMasterGetAutomationState\n"); return 0;
        case audioMasterOfflineStart: printf("audioMasterOfflineStart\n"); return 0;
        case audioMasterOfflineRead: printf("audioMasterOfflineRead\n"); return 0;
        case audioMasterOfflineWrite: printf("audioMasterOfflineWrite\n"); return 0;
        case audioMasterOfflineGetCurrentPass: printf("audioMasterOfflineGetCurrentPass\n"); return 0;
        case audioMasterOfflineGetCurrentMetaPass: printf("audioMasterOfflineGetCurrentMetaPass\n"); return 0;
        case DEPRECATED_audioMasterSetOutputSampleRate: printf("DEPRECATED_audioMasterSetOutputSampleRate\n"); return 0;
        case DEPRECATED_audioMasterGetOutputSpeakerArrangement: printf("DEPRECATED_audioMasterGetOutputSpeakerArrangement\n"); return 0;

        case audioMasterGetVendorString:
        case audioMasterGetProductString:
        {
            char* p = cast(char*)ptr;
            if (p !is null)
                stringNCopy(p, 64, "Dplug host");
            return 0;
        }

        case audioMasterGetVendorVersion: return 0x200; // 2.0

        case audioMasterVendorSpecific: printf("audioMasterVendorSpecific\n"); return 0;
        case DEPRECATED_audioMasterSetIcon: printf("DEPRECATED_audioMasterSetIcon\n"); return 0;
        case audioMasterCanDo: printf("audioMasterCanDo\n"); return 0;
        case audioMasterGetLanguage: printf("audioMasterGetLanguage\n"); return 0;
        case DEPRECATED_audioMasterOpenWindow: printf("DEPRECATED_audioMasterOpenWindow\n"); return 0;
        case DEPRECATED_audioMasterCloseWindow: printf("DEPRECATED_audioMasterCloseWindow\n"); return 0;
        case audioMasterGetDirectory: printf("audioMasterGetDirectory\n"); return 0;
        case audioMasterUpdateDisplay: printf("audioMasterUpdateDisplay\n"); return 0;
        case audioMasterBeginEdit: printf("audioMasterBeginEdit\n"); return 0;
        case audioMasterEndEdit: printf("audioMasterEndEdit\n"); return 0;
        case audioMasterOpenFileSelector: printf("audioMasterOpenFileSelector\n"); return 0;
        case audioMasterCloseFileSelector: printf("audioMasterCloseFileSelector\n"); return 0;
        case DEPRECATED_audioMasterEditFile: printf("DEPRECATED_audioMasterEditFile\n"); return 0;
        case DEPRECATED_audioMasterGetChunkFile: printf("DEPRECATED_audioMasterGetChunkFile\n"); return 0;
        case DEPRECATED_audioMasterGetInputSpeakerArrangement: printf("DEPRECATED_audioMasterGetInputSpeakerArrangement\n"); return 0;
        default: printf(" unknown opcode %d\n", opcode); return 0;
    }
}
