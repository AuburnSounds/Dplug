/**
VST host implementation.

Copyright: Auburn Sounds 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.host.vst;

import std.string;
import std.algorithm.mutation;

import dplug.core.sharedlib;
import dplug.core.nogc;
import dplug.host.host;
import dplug.vst;


alias VSTPluginMain_t = extern(C) AEffect* function(HostCallbackFunction fun);

VSTPluginMain_t getVSTEntryPoint(ref SharedLib lib)
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
        throw new Exception("Did not find a VST entry point");
    else
        return cast(VSTPluginMain_t)result;
}

private __gshared VSTPluginHost[AEffect*] reverseMapping;

final class VSTPluginHost : IPluginHost
{
    this(SharedLib lib)
    {
        _lib = move(lib);

        VSTPluginMain_t VSTPluginMain = getVSTEntryPoint(_lib);

        _aeffect = VSTPluginMain(&hostCallback);

        reverseMapping[_aeffect] = this;

        // various checks
        if (_aeffect.magic != 0x56737450) /* 'VstP' */
            throw new Exception("Wrong VST magic number");
        if (_aeffect.dispatcher == null)
            throw new Exception("aeffect.dispatcher is null");
        if (_aeffect.setParameter == null)
            throw new Exception("aeffect.setParameter is null");
        if (_aeffect.getParameter == null)
            throw new Exception("aeffect.getParameter is null");

        _dispatcher = _aeffect.dispatcher;

        // open plugin
        _dispatcher(_aeffect, effOpen, 0, 0, null, 0.0f);
    }

    override void setParameter(int paramIndex, float normalizedValue)
    {
        _aeffect.setParameter(_aeffect, paramIndex, normalizedValue);
    }

    override float getParameter(int paramIndex)
    {
        return _aeffect.getParameter(_aeffect, paramIndex);
    }

    override void close()
    {
        if (!_suspended)
            throw new Exception("Cannot close VST plugin while not suspended");

        // close plugin
        _dispatcher(_aeffect, effClose, 0, 0, null, 0.0f);

        // TODO: disabled because this breaks the second time the DLL is unloaded on Windows
        // unload dynlib
        // Note: probably fixed now
        //  _lib.unload();
    }

    override string getVendorString()
    {
        char[65] buf;
        _dispatcher(_aeffect, effGetVendorString, 0, 0, buf.ptr, 0.0f);
        return fromStringz(buf.ptr).idup;
    }

    override string getEffectName()
    {
        char[65] buf;
        _dispatcher(_aeffect, effGetEffectName, 0, 0, buf.ptr, 0.0f);
        return fromStringz(buf.ptr).idup;
    }

    override string getProductString()
    {
        char[65] buf;
        _dispatcher(_aeffect, effGetProductString, 0, 0, buf.ptr, 0.0f);
        return fromStringz(buf.ptr).idup;
    }

    override void processAudioFloat(float** inputs, float** outputs, int samples)
    {
        if (_suspended)
            throw new Exception("Cannot process audio with VST plugin while suspended");
        _aeffect.processReplacing(_aeffect, inputs, outputs, samples);
        _processedSamples += samples;
    }

    override void beginAudioProcessing()
    {
        _dispatcher(_aeffect, effMainsChanged, 0, 1, null, 0.0f);
        _suspended = false;
    }

    override void endAudioProcessing()
    {
        _dispatcher(_aeffect, effMainsChanged, 0, 0, null, 0.0f);
        _suspended = true;
    }

    override void setSampleRate(float sampleRate)
    {
        if (!_suspended)
            throw new Exception("Cannot set sample rate of VST plugin while not suspended");
        _dispatcher(_aeffect, effSetSampleRate, 0, 0, null, sampleRate);
    }

    override void setMaxBufferSize(int samples)
    {
        if (!_suspended)
            throw new Exception("Cannot set block sizeof VST plugin while not suspended");
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

    override ubyte[] saveState()
    {
        if (_aeffect.flags && effFlagsProgramChunks)
        {
            ubyte* pChunk = null;
            VstIntPtr size = _dispatcher(_aeffect, effGetChunk, 0 /* want a bank */, 0, &pChunk, 0.0f);

            if (size == 0 || pChunk == null)
                throw new Exception("effGetChunk returned an empty chunk");

            return pChunk[0..size].dup;
        }
        else
            throw new Exception("This VST doesn't support chunks");

    }

    override void restoreState(ubyte[] chunk)
    {
        VstIntPtr result = _dispatcher(_aeffect, effSetChunk, 0 /* want a bank */, chunk.length, chunk.ptr, 0.0f);
        if (result != 1)
            throw new Exception("effSetChunk failed");
    }

    override int getCurrentProgram()
    {
        return cast(int)( _dispatcher(_aeffect, effGetProgram, 0, 0, null, 0.0f) );
    }

private:
    SharedLib _lib;
    AEffect* _aeffect;
    AEffectDispatcherProc _dispatcher;
    long _processedSamples;
    VstTimeInfo timeInfo;
    bool _suspended = true;
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
            VSTPluginHost* phost = effect in reverseMapping;
            if (!phost)
                return 0;

            VSTPluginHost host = *phost;
            host.timeInfo.samplePos = host._processedSamples;
            host.timeInfo.flags = 0;

            return cast(VstIntPtr)(&host.timeInfo);
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
