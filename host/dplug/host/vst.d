/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.host.vst;

import std.string;

import derelict.util.sharedlib;

import dplug.host.host;
import dplug.vst;


alias VSTPluginMain_t = extern(C) AEffect* function(HostCallbackFunction fun);

VSTPluginMain_t getVSTEntryPoint(SharedLib lib)
{
    void* result = lib.loadSymbol("VSTPluginMain");
    if (result == null)
        result = lib.loadSymbol("main_macho");
    if (result == null)
        result = lib.loadSymbol("main");
    return cast(VSTPluginMain_t) result;
}

private __gshared VSTPluginHost[AEffect*] reverseMapping;

final class VSTPluginHost : IPluginHost
{
    this(SharedLib lib)
    {
        _lib = lib;
        
        // TODO other symbol names like main_macho or main
        VSTPluginMain_t VSTPluginMain = getVSTEntryPoint(lib); 

        _aeffect = VSTPluginMain(&hostCallback);

        reverseMapping[_aeffect] = this;

        // various checks
        if (_aeffect.magic != kEffectMagic)
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
        // close plugin
        _dispatcher(_aeffect, effClose, 0, 0, null, 0.0f);

        // unload dynlib
        _lib.unload();
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
        _aeffect.processReplacing(_aeffect, inputs, outputs, samples);
        _processedSamples += samples;
    }

    override void setSampleRate(float sampleRate)
    {
        _dispatcher(_aeffect, effSetSampleRate, 0, 0, null, sampleRate);
    }

    override void setMaxBufferSize(int samples)
    {
        _dispatcher(_aeffect, effSetBlockSize, 0, cast(VstIntPtr)samples, null, 0.0f);
    }

private:
    SharedLib _lib;
    AEffect* _aeffect;
    AEffectDispatcherProc _dispatcher;
    long _processedSamples;
    VstTimeInfo timeInfo;
}

extern(C) nothrow @nogc VstIntPtr hostCallback(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt)
{
    import core.stdc.stdio;

    switch(opcode)
    {
        case DEPRECATED_audioMasterWantMidi: printf("DEPRECATED_audioMasterWantMidi\n"); return 0;
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
        case audioMasterGetCurrentProcessLevel: printf("audioMasterGetCurrentProcessLevel\n"); return 0;
        case audioMasterGetAutomationState: printf("audioMasterGetAutomationState\n"); return 0;
        case audioMasterOfflineStart: printf("audioMasterOfflineStart\n"); return 0;
        case audioMasterOfflineRead: printf("audioMasterOfflineRead\n"); return 0;
        case audioMasterOfflineWrite: printf("audioMasterOfflineWrite\n"); return 0;
        case audioMasterOfflineGetCurrentPass: printf("audioMasterOfflineGetCurrentPass\n"); return 0;
        case audioMasterOfflineGetCurrentMetaPass: printf("audioMasterOfflineGetCurrentMetaPass\n"); return 0;
        case DEPRECATED_audioMasterSetOutputSampleRate: printf("DEPRECATED_audioMasterSetOutputSampleRate\n"); return 0;
        case DEPRECATED_audioMasterGetOutputSpeakerArrangement: printf("DEPRECATED_audioMasterGetOutputSpeakerArrangement\n"); return 0;
        case audioMasterGetVendorString: printf("audioMasterGetVendorString\n"); return 0;
        case audioMasterGetProductString: printf("audioMasterGetProductString\n"); return 0;
        case audioMasterGetVendorVersion: printf("audioMasterGetVendorVersion\n"); return 0;
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
        default: printf(" unknown opcode\n"); return 0;
    }
}
