/**
FL Plugin client.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flp.client;

import core.atomic;

import dplug.core.nogc;
import dplug.core.vec;
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

    // Important SDK note about FL plug-in threading:
    //
    // " (G) = called from GUI thread, 
    //   (M) = called from mixer thread, 
    //   (GM) = both, 
    //   (S) = called from MIDI synchronization thread
    //   (M) calls are done inside the plugin lock (LockPlugin / UnlockPlugin)"
    // 
    // Comment: LockPlugin/UnlockPlugin is implemented at the discretion of the client, contrarily
    // to what this comment seems to imply.
    //
    // "TriggerVoice and Voice_ functions are also called inside the plugin lock
    //  assume that any other call is not locked! (so call LockPlugin / UnlockPlugin 
    //  where necessary, but no more than that.
    //  Don't call back to the host while inside a LockPlugin / UnlockPlugin block"
    //
    // In this client we'll tag the overrides with UDAs @guiThread @mixerThread and midiSyncThread.
    // In addition, variables that are @mixerThread are only ever accessed from mixer thread.
    
    private enum guiThread = 0;
    private enum mixerThread = 0;
    private enum midiSyncThread = 0;

    extern(Windows) override
    {
        @guiThread
        void DestroyObject()
        {
            destroyFree(_client);
            _client = null;
            destroyFree(this);
        }

        @guiThread @mixerThread
        intptr_t Dispatcher(intptr_t ID, intptr_t Index, intptr_t Value)
        {

            // Note: it's not really documented what the return values should be.
            // In general it seems opcode dependent, with a value of zero maybe meaning "unhandled".
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            debug(logFLPClient) 
                debugLogf("Dispatcher ID = %llu index = %llu value = %llu\n", ID, Index, Value);

            switch (ID)
            {
                case FPD_ShowEditor:                 /* 0 */
                case FPD_ProcessMode:                /* 1 */
                case FPD_Flush:                      /* 2 */

                case FPD_SetBlockSize:               /* 3 */
                    // Client maxframes will change at next buffer asynchronously.
                    atomicStore(_hostMaxFrames, Value); 
                    return 0;

                case FPD_SetSampleRate:              /* 4 */
                    // Client sampleRate will change at next buffer asynchronously.
                    atomicStore(_hostSampleRate, Value);
                    return 0;

                case FPD_WindowMinMax:               /* 5 */
                case FPD_KillAVoice:                 /* 6 */
                case FPD_UseVoiceLevels:             /* 7 */
                case FPD_SetPreset:                  /* 9 */
                case FPD_ChanSampleChanged:          /* 10 */
                case FPD_SetEnabled:                 /* 11 */
                case FPD_SetPlaying:                 /* 12 */
                case FPD_SongPosChanged:             /* 13 */
                    break;

                case FPD_SetTimeSig:                 /* 14 */
                    // TODO
                    return 0; // ignored

                case FPD_CollectFile:                /* 15 */
                case FPD_SetInternalParam:           /* 16 */
                case FPD_SetNumSends:                /* 17 */
                case FPD_LoadFile:                   /* 18 */
                case FPD_SetFitTime:                 /* 19 */
                    break;
                
                case FPD_SetSamplesPerTick:          /* 20 */
                    // TODO
                    return 0;

                case FPD_SetIdleTime:                /* 21 */
                case FPD_SetFocus:                   /* 22 */
                case FPD_Transport:                  /* 23 */
                case FPD_MIDIIn:                     /* 24 */
                case FPD_RoutingChanged:             /* 25 */
                case FPD_GetParamInfo:               /* 26 */
                case FPD_ProjLoaded:                 /* 27 */
                case FPD_WrapperLoadState:           /* 28 */
                case FPD_ShowSettings:               /* 29 */
                case FPD_SetIOLatency:               /* 30 */
                case FPD_PreferredNumIO:             /* 32 */
                case FPD_GetGUIColor:                /* 33 */
                case FPD_CloseAllWindows:            /* 34 */
                case FPD_RenderWindowBitmap:         /* 35 */
                case FPD_StealKBFocus:               /* 36 */
                case FPD_GetHelpContext:             /* 37 */
                case FPD_RegChanged:		         /* 38 */
                case FPD_ArrangeWindows: 	         /* 39 */
                case FPD_PluginLoaded:		         /* 40 */
                case FPD_ContextInfoChanged:         /* 41 */
                case FPD_ProjectInfoChanged:         /* 42 */
                case FPD_GetDemoPlugins:             /* 43 */
                case FPD_UnLockDemoPlugins:          /* 44 */
                case FPD_ColorWasPicked:             /* 46 */
                case FPD_IsInDebugMode:              /* 47 */
                case FPD_ColorsHaveChanged:          /* 48 */
                case FPD_GetStateSizeEstimate:       /* 49 */
                case FPD_UseIncreasedMIDIResolution: /* 50 */
                case FPD_ConvertStringToValue:       /* 51 */
                case FPD_GetParamType:               /* 52 */
                    break;

                default:
                    // unknown ID
                    break;

            }
            return 0;
        }

        @guiThread
        void Idle_Public()
        {
            // "This function is called continuously. It allows the plugin to perform certain tasks
            // that are not time-critical and which do not take up a lot of time either. For 
            // example, TDelphiFruityPlug and TCPPFruityPlug implement this function to show a hint
            // message when the mouse moves over a control in the editor."
            // Well, thank you but not needed.
        }

        @guiThread
        void SaveRestoreState(IStream *Stream, BOOL Save)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            // TODO
            debug(logFLPClient) debugLogf("SaveRestoreState save = %d\n", Save);
        }

        // names (see FPN_Param) (Name must be at least 256 chars long)
        @guiThread
        void GetName(int Section, int Index, int Value, char *Name)
        {
            debug(logFLPClient) debugLogf("GetName %d %d %d\n", Section, Index, Value);
        }

        // events
        @guiThread @mixerThread
        int ProcessEvent(int EventID, int EventValue, int Flags)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            debug(logFLPClient) debugLogf("ProcessEvent %d %d %d\n", EventID, EventValue, Flags);
            return 0;
        }

        @guiThread @mixerThread
        int ProcessParam(int Index, int Value, int RECFlags)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            debug(logFLPClient) debugLogf("ProcessParam %d %d %d\n", Index, Value, RECFlags);
            return 0;
        }

        // effect processing (source & dest can be the same)
        @mixerThread
        void Eff_Render(PWAV32FS SourceBuffer, PWAV32FS DestBuffer, int Length)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            resetClientIfNeeded(2, 2, Length);

            float*[2] pInputs  = [ _inputBuf[0].ptr,  _inputBuf[1].ptr  ];
            float*[2] pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];

            deinterleaveBuffers(SourceBuffer, pInputs[0], pInputs[1], Length);

            TimeInfo info; // TODO timing information
            _client.processAudioFromHost(pInputs[0..2], pOutputs[0..2], Length, info);

            interleaveBuffers(pOutputs[0], pOutputs[1], DestBuffer, Length);
        }

        // generator processing (can render less than length)
        @mixerThread
        void Gen_Render(PWAV32FS DestBuffer, ref int Length)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            resetClientIfNeeded(0, 2, Length);

            float*[2] pInputs  = [ _inputBuf[0].ptr,  _inputBuf[1].ptr ];
            float*[2] pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];
            TimeInfo info; // TODO timing information
            _client.processAudioFromHost(pInputs[0..0], pOutputs[0..2], Length, info);
            interleaveBuffers(pOutputs[0], pOutputs[1], DestBuffer, Length);

            debug(logFLPClient) debugLogf("Gen_Render %p %d\n", DestBuffer, Length);
        }

        // <voice handling>
        @guiThread @mixerThread
        TVoiceHandle TriggerVoice(PVoiceParams VoiceParams, intptr_t SetTag)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();
            return 0;
        }

        @guiThread @mixerThread
        void Voice_Release(TVoiceHandle Handle)
        {
        }

        @guiThread @mixerThread
        void Voice_Kill(TVoiceHandle Handle)
        {
        }

        @guiThread @mixerThread
        int Voice_ProcessEvent(TVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();
            return 0;
        }

        @guiThread @mixerThread
        int Voice_Render(TVoiceHandle Handle, PWAV32FS DestBuffer, ref int Length)
        {
            return 0;
        }
        // </voice handling>


        // (see FPF_WantNewTick) called before a new tick is mixed (not played)
        // internal controller plugins should call OnControllerChanged from here
        @mixerThread
        void NewTick() 
        {
        }

        // (see FHD_WantMIDITick) called when a tick is being played (not mixed) (not used yet)
        @midiSyncThread
        void MIDITick() 
        {
        }

        // MIDI input message (see FHD_WantMIDIInput & TMIDIOutMsg) (set Msg to MIDIMsg_Null if it has to be killed)
        @guiThread @mixerThread
        void MIDIIn(ref int Msg)
        {
            // TODO
        }

        // buffered messages to itself (see PlugMsg_Delayed)
        @midiSyncThread
        void MsgIn(intptr_t Msg)
        {
            // TODO
        }

        // voice handling
        @guiThread @mixerThread
        int OutputVoice_ProcessEvent(TOutVoiceHandle Handle, intptr_t EventID, intptr_t EventValue,
                                     intptr_t Flags)
        {
            // Not implemented, as we never report Output Voices, a FL-specific feature. 
            // Not sure what the return value should be from the SDK, but probaby FLStudio won't 
            // call this.
            return 0;
        }

        @guiThread @mixerThread
        void OutputVoice_Kill(TVoiceHandle Handle)
        {
            // Not implemented, as we never report Output Voices, a FL-specific feature.
        }

        // </Implements TFruityPlug>
    }

private:

    Client _client;                         /// Wrapped generic client.
    TFruityPlugHost _host;                  /// A whole lot of callbacks to host.
    TFruityPlugInfo _fruityPlugInfo;        /// Plug-in formation for the host to read.

    char[128] _longNameBuf;                 /// Buffer for plugin long name.
    char[32] _shortNameBuf;                 /// Buffer for plugin short name.
    
    shared(size_t) _hostMaxFrames = 512;    /// Max frames that the host demanded.
    @mixerThread int _clientMaxFrames = 0;  /// Max frames last used by client.    
    shared(size_t) _hostSampleRate = 44100; /// Samplerate that the host demanded.
    @mixerThread int _clientSampleRate = 0; /// Samplerate last used by client.

    @mixerThread float[][2] _inputBuf;       /// Temp buffers to deinterleave and pass to plug-in.
    @mixerThread float[][2] _outputBuf;      /// Plug-in outoput, deinterleaved.

    void initializeInfo()
    {
        int flags                     = FPF_NewVoiceParams | FPF_MacNeedsNSView;
        if (_client.isSynth)   flags |= FPF_Generator;
        if (!_client.hasGUI)   flags |= FPF_Interfaceless; // SDK says it's not implemented? mm.
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

    @mixerThread
    void resetClientIfNeeded(int numInputs, int numOutputs, int framesJustGiven)
    {
        int hostMaxFrames  = cast(int) atomicLoad(_hostMaxFrames);
        int hostSampleRate = cast(int) atomicLoad(_hostSampleRate);

        // FLStudio would have an issue if it was the case, since we did use an atomic.
        assert (framesJustGiven <= hostMaxFrames);

        bool maxFramesChanged  = hostMaxFrames  != _clientMaxFrames;
        bool sampleRateChanged = hostSampleRate != _clientSampleRate;

        if (maxFramesChanged || sampleRateChanged)
        {
            _client.resetFromHost(hostSampleRate, hostMaxFrames, numInputs, numOutputs);
            _clientMaxFrames = hostMaxFrames;
            _clientSampleRate = hostSampleRate;

            _inputBuf[0].reallocBuffer(hostMaxFrames); // even if unused in generator case.
            _inputBuf[1].reallocBuffer(hostMaxFrames);
            _outputBuf[0].reallocBuffer(hostMaxFrames);
            _outputBuf[1].reallocBuffer(hostMaxFrames);
        }
    }

    @mixerThread
    void deinterleaveBuffers(float[2]* input, float* leftOutput, float* rightOutput, int frames)
    {
        for (int n = 0; n < frames; ++n)
        {
            leftOutput[n]  = input[n][0];
            rightOutput[n] = input[n][1];
        }
    }

    @mixerThread
    void interleaveBuffers(float* leftInput, float* rightInput, float[2]* output, int frames)
    {
        for (int n = 0; n < frames; ++n)
        {
            output[n][0] = leftInput[n];
            output[n][1] = rightInput[n];
        }
    }
}