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

final class VSTPluginHost : IPluginHost
{
	this(SharedLib lib)
	{
        _lib = lib;
        
        // TODO other symbol names like main_macho or main
        VSTPluginMain_t VSTPluginMain = getVSTEntryPoint(lib); 

        _aeffect = VSTPluginMain(&hostCallback);

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
}

extern(C) nothrow VstIntPtr hostCallback(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt)
{
    try
    {
        import std.stdio;
        writeln("Received opcode: ");
        switch(opcode)
        {
            case DEPRECATED_audioMasterWantMidi: writeln("DEPRECATED_audioMasterWantMidi"); return 0;
            case audioMasterGetTime: writeln("audioMasterGetTime"); return 0;
            case audioMasterProcessEvents: writeln("audioMasterProcessEvents"); return 0;
            case DEPRECATED_audioMasterSetTime: writeln("DEPRECATED_audioMasterSetTime"); return 0;
            case DEPRECATED_audioMasterTempoAt: writeln("DEPRECATED_audioMasterTempoAt"); return 0;
            case DEPRECATED_audioMasterGetNumAutomatableParameters: writeln("DEPRECATED_audioMasterGetNumAutomatableParameters"); return 0;
            case DEPRECATED_audioMasterGetParameterQuantization: writeln("DEPRECATED_audioMasterGetParameterQuantization"); return 0;
            case audioMasterIOChanged: writeln("audioMasterIOChanged"); return 0;
            case DEPRECATED_audioMasterNeedIdle: writeln("DEPRECATED_audioMasterNeedIdle"); return 0;
            case audioMasterSizeWindow: writeln("audioMasterSizeWindow"); return 0;
            case audioMasterGetSampleRate: writeln("audioMasterGetSampleRate"); return 0;
            case audioMasterGetBlockSize: writeln("audioMasterGetBlockSize"); return 0;
            case audioMasterGetInputLatency: writeln("audioMasterGetInputLatency"); return 0;
            case audioMasterGetOutputLatency: writeln("audioMasterGetOutputLatency"); return 0;
            case DEPRECATED_audioMasterGetPreviousPlug: writeln("DEPRECATED_audioMasterGetPreviousPlug"); return 0;
            case DEPRECATED_audioMasterGetNextPlug: writeln("DEPRECATED_audioMasterGetNextPlug"); return 0;
            case DEPRECATED_audioMasterWillReplaceOrAccumulate: writeln("DEPRECATED_audioMasterWillReplaceOrAccumulate"); return 0;
            case audioMasterGetCurrentProcessLevel: writeln("audioMasterGetCurrentProcessLevel"); return 0;
            case audioMasterGetAutomationState: writeln("audioMasterGetAutomationState"); return 0;
            case audioMasterOfflineStart: writeln("audioMasterOfflineStart"); return 0;
            case audioMasterOfflineRead: writeln("audioMasterOfflineRead"); return 0;
            case audioMasterOfflineWrite: writeln("audioMasterOfflineWrite"); return 0;
            case audioMasterOfflineGetCurrentPass: writeln("audioMasterOfflineGetCurrentPass"); return 0;
            case audioMasterOfflineGetCurrentMetaPass: writeln("audioMasterOfflineGetCurrentMetaPass"); return 0;
            case DEPRECATED_audioMasterSetOutputSampleRate: writeln("DEPRECATED_audioMasterSetOutputSampleRate"); return 0;
            case DEPRECATED_audioMasterGetOutputSpeakerArrangement: writeln("DEPRECATED_audioMasterGetOutputSpeakerArrangement"); return 0;
            case audioMasterGetVendorString: writeln("audioMasterGetVendorString"); return 0;
            case audioMasterGetProductString: writeln("audioMasterGetProductString"); return 0;
            case audioMasterGetVendorVersion: writeln("audioMasterGetVendorVersion"); return 0;
            case audioMasterVendorSpecific: writeln("audioMasterVendorSpecific"); return 0;
            case DEPRECATED_audioMasterSetIcon: writeln("DEPRECATED_audioMasterSetIcon"); return 0;
            case audioMasterCanDo: writeln("audioMasterCanDo"); return 0;
            case audioMasterGetLanguage: writeln("audioMasterGetLanguage"); return 0;
            case DEPRECATED_audioMasterOpenWindow: writeln("DEPRECATED_audioMasterOpenWindow"); return 0;
            case DEPRECATED_audioMasterCloseWindow: writeln("DEPRECATED_audioMasterCloseWindow"); return 0;
            case audioMasterGetDirectory: writeln("audioMasterGetDirectory"); return 0;
            case audioMasterUpdateDisplay: writeln("audioMasterUpdateDisplay"); return 0;
            case audioMasterBeginEdit: writeln("audioMasterBeginEdit"); return 0;
            case audioMasterEndEdit: writeln("audioMasterEndEdit"); return 0;
            case audioMasterOpenFileSelector: writeln("audioMasterOpenFileSelector"); return 0;
            case audioMasterCloseFileSelector: writeln("audioMasterCloseFileSelector"); return 0;
            case DEPRECATED_audioMasterEditFile: writeln("DEPRECATED_audioMasterEditFile"); return 0;
            case DEPRECATED_audioMasterGetChunkFile: writeln("DEPRECATED_audioMasterGetChunkFile"); return 0;
            case DEPRECATED_audioMasterGetInputSpeakerArrangement: writeln("DEPRECATED_audioMasterGetInputSpeakerArrangement"); return 0;
            default: writeln(" unknown opcode"); return 0;
        }
    }
    catch(Exception e)
    {
        return 0;
    }
}
