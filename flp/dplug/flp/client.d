/**
FL Plugin client.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flp.client;

import dplug.core.nogc;
import dplug.client.client;
import dplug.flp.types;



debug = logFLPClient;

final extern(C++) class FLPCLient : TFruityPlug
{
nothrow @nogc:

    this(TFruityHost pHost, TPluginTag tag)
    {
        _host = pHost;
    }

    // <Implements TFruityPlug>

    extern(Windows) override
    {
        void DestroyObject()
        {
            destroyFree(this);
        }

        intptr_t Dispatcher(intptr_t ID, intptr_t Index, intptr_t Value)
        {
            debug(logFLPClient) debugLogf("Dispatcher ID = %llu index = %llu value = %llu\n", ID, Index, Value);
            return 0;
        }

        void Idle_Public()
        {
             // TODO
        }

        void SaveRestoreState(IStream *Stream, BOOL Save)
        {
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
            debug(logFLPClient) debugLogf("ProcessEvent %d %d %d\n", EventID, EventValue, Flags);
            return 0;
        }

        int ProcessParam(int Index, int Value, int RECFlags)
        {
            debug(logFLPClient) debugLogf("ProcessParam %d %d %d\n", Index, Value, RECFlags);
            return 0;
        }

        // effect processing (source & dest can be the same)
        void Eff_Render(PWAV32FS SourceBuffer, PWAV32FS DestBuffer, int Length)
        {
            debug(logFLPClient) debugLogf("Eff_Render %p %p %d\n", SourceBuffer, DestBuffer, Length);
        }

        // generator processing (can render less than length)
        void Gen_Render(PWAV32FS DestBuffer, ref int Length)
        {
            debug(logFLPClient) debugLogf("Gen_Render %p %d\n", DestBuffer, Length);
        }

        // <voice handling>
        TVoiceHandle TriggerVoice(PVoiceParams VoiceParams, intptr_t SetTag)
        {
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
    TFruityHost _host;

}