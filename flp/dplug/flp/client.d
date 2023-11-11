/**
FL Plugin client.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flp.client;

import dplug.core.nogc;
import dplug.client.client;
import dplug.core.runtime;
import dplug.flp.types;



debug = logFLPClient;

// SDK insists that there is such a global, not sure if needed yet.
__gshared TFruityPlugHost g_host = null;


final extern(C++) class FLPCLient : TFruityPlug
{
nothrow @nogc:

    this(TFruityPlugHost pHost, TPluginTag tag, Client client, bool* err)
    {
        g_host = pHost;

        this.HostTag = tag;
        this.Info = &_fruityPlugInfo;
        this._host = pHost;
        this._client = client;
        initializeInfo();

        // If a synth ("generator" in FL dialect), it must supports 0-2.
        // If an effect, it must supports 2-2.
        // Else fail instantiation.

        bool compatibleIO;
        if (_client.isSynth)
            compatibleIO = _client.isLegalIO(0, 2);
        else
            compatibleIO = _client.isLegalIO(2, 2);

        *err = false;
        if (!compatibleIO)
            *err = true;
    }

    // <Implements TFruityPlug>

    extern(Windows) override
    {
        void DestroyObject()
        {
            destroyFree(_client);
            _client = null;
            destroyFree(this);
        }

        intptr_t Dispatcher(intptr_t ID, intptr_t Index, intptr_t Value)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            debug(logFLPClient) debugLogf("Dispatcher ID = %llu index = %llu value = %llu\n", ID, Index, Value);
            return 0;
        }

        void Idle_Public()
        {
             // TODO
        }

        void SaveRestoreState(IStream *Stream, BOOL Save)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            // TODO
            debug(logFLPClient) debugLogf("SaveRestoreState save = %d\n", Save);
        }

        // names (see FPN_Param) (Name must be at least 256 chars long)
        void GetName(int Section, int Index, int Value, char *Name)
        {
            debug(logFLPClient) debugLogf("GetName %d %d %d\n", Section, Index, Value);
        }

        // events
        int ProcessEvent(int EventID, int EventValue, int Flags)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            debug(logFLPClient) debugLogf("ProcessEvent %d %d %d\n", EventID, EventValue, Flags);
            return 0;
        }

        int ProcessParam(int Index, int Value, int RECFlags)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            debug(logFLPClient) debugLogf("ProcessParam %d %d %d\n", Index, Value, RECFlags);
            return 0;
        }

        // effect processing (source & dest can be the same)
        void Eff_Render(PWAV32FS SourceBuffer, PWAV32FS DestBuffer, int Length)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            //debug(logFLPClient) debugLogf("Eff_Render %p %p %d\n", SourceBuffer, DestBuffer, Length);
        }

        // generator processing (can render less than length)
        void Gen_Render(PWAV32FS DestBuffer, ref int Length)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            debug(logFLPClient) debugLogf("Gen_Render %p %d\n", DestBuffer, Length);
        }

        // <voice handling>
        TVoiceHandle TriggerVoice(PVoiceParams VoiceParams, intptr_t SetTag)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();
            return 0;
        }

        void Voice_Release(TVoiceHandle Handle)
        {
        }

        void Voice_Kill(TVoiceHandle Handle)
        {
        }

        int Voice_ProcessEvent(TVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();
            return 0;
        }

        int Voice_Render(TVoiceHandle Handle, PWAV32FS DestBuffer, ref int Length)
        {
            return 0;
        }
        // </voice handling>


        // (see FPF_WantNewTick) called before a new tick is mixed (not played)
        // internal controller plugins should call OnControllerChanged from here
        void NewTick()
        {
        }

        // (see FHD_WantMIDITick) called when a tick is being played (not mixed) (not used yet)
        void MIDITick()
        {
        }

        // MIDI input message (see FHD_WantMIDIInput & TMIDIOutMsg) (set Msg to MIDIMsg_Null if it has to be killed)
        void MIDIIn(ref int Msg)
        {
            // TODO
        }

        // buffered messages to itself (see PlugMsg_Delayed)
        void MsgIn(intptr_t Msg)
        {
            // TODO
        }

        // voice handling
        int OutputVoice_ProcessEvent(TOutVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();
            // TODO
            return 0;
        }

        void OutputVoice_Kill(TVoiceHandle Handle)
        {
            // TODO
        }

        // </Implements TFruityPlug>
    }

private:

    Client _client;
    TFruityPlugHost _host;
    TFruityPlugInfo _fruityPlugInfo;
    char[128] _longNameBuf;
    char[32] _shortNameBuf;

    void initializeInfo()
    {
        int flags                     = FPF_NewVoiceParams | FPF_MacNeedsNSView;
        if (_client.isSynth)   flags |= FPF_Generator;
        if (!_client.hasGUI)   flags |= FPF_Interfaceless; // SDK says it's not implemented, so not sure
        if (_client.sendsMIDI) flags |= FPF_MIDIOut;

        if (_client.tailSizeInSeconds() == float.infinity) 
        {
            flags |= FPF_CantSmartDisable;
        }

        _client.getPluginFullName(_longNameBuf.ptr, 128);        
        _client.getPluginName(_shortNameBuf.ptr, 32);
        _fruityPlugInfo.SDKVersion   = 1;
        _fruityPlugInfo.LongName     = _longNameBuf.ptr;
        _fruityPlugInfo.ShortName    = _shortNameBuf.ptr;
        _fruityPlugInfo.Flags        = flags;
        _fruityPlugInfo.NumParams    = cast(int)(_client.params.length);
        _fruityPlugInfo.DefPoly      = 0;
        _fruityPlugInfo.NumOutCtrls  = 0;
        _fruityPlugInfo.NumOutVoices = 0;
        _fruityPlugInfo.Reserved[]   = 0;

    }
}