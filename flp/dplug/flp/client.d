/**
FL Plugin client.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flp.client;

import core.atomic;

import dplug.core.nogc;
import dplug.core.vec;
import dplug.core.runtime;
import dplug.client.client;
import dplug.client.graphics;
import dplug.client.daw;
import dplug.flp.types;



debug = logFLPClient;

// SDK insists that there is such a global, not sure if needed yet.
//__gshared TFruityPlugHost g_host = null;


final extern(C++) class FLPCLient : TFruityPlug
{
nothrow @nogc:

    this(TFruityPlugHost pHost, TPluginTag tag, Client client, bool* err)
    {
        //g_host = pHost;

        this.HostTag = tag;
        this.Info = &_fruityPlugInfo;
        this._host = pHost;
        this._client = client;
        initializeInfo();

        _hostCommand = mallocNew!FLHostCommand(pHost);
        _client.setHostCommand(_hostCommand);

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

    ~this()
    {
        destroyFree(_hostCommand);
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

            debug(logFLPClient) debugLogf("Dispatcher ID = %llu index = %llu value = %llu\n", ID, Index, Value);

            switch (ID)
            {
                case FPD_ShowEditor:                 /* 0 */
                    if (Value == 0)
                    {
                        // hide editor
                        if (_client.hasGUI) _client.closeGUI();
                    }
                    else
                    {
                        void* parent = cast(void*) Value;
                        if (_client.hasGUI) _client.openGUI(parent, null, GraphicsBackend.autodetect);
                        return Value;
                    }
                    return 0; // right return value according to TTestPlug

                case FPD_ProcessMode:                /* 1 */
                    // "this ID can be ignored"
                    // Gives a quality hint.
                    return 0;

                case FPD_Flush:                      /* 2 */
                    // "FPD_Flush warns the plugin that the next samples do not follow immediately
                    //  in time to the previous block of samples. In other words, the continuity is
                    //  broken."
                    //
                    // Interesting, Dplug plugins normally follow this already, since it's common
                    // while the DAW is looping.
                    return 0;

                case FPD_SetBlockSize:               /* 3 */
                    // Client maxframes will change at next buffer asynchronously.
                    atomicStore(_hostMaxFrames, Value); 
                    return 0;

                case FPD_SetSampleRate:              /* 4 */
                    // Client sampleRate will change at next buffer asynchronously.
                    atomicStore(_hostSampleRate, Value);
                    return 0; // right return value according to TTestPlug

                case FPD_WindowMinMax:               /* 5 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    return 0;

                case FPD_KillAVoice:                 /* 6 */
                case FPD_UseVoiceLevels:             /* 7 */
                case FPD_SetPreset:                  /* 9 */
                case FPD_ChanSampleChanged:          /* 10 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_SetEnabled:                 /* 11 */  //
                    bool bypassed = (Value == 0);
                    atomicStore(_hostBypass, bypassed);
                    break;

                case FPD_SetPlaying:                 /* 12 */
                    atomicStore(_hostHostPlaying, Value != 0);
                    return 0;

                case FPD_SongPosChanged:             /* 13 */  //
                    // song position has been relocated (loop?)                    
                    return 0;

                case FPD_SetTimeSig:                 /* 14 */
                    return 0; // ignored

                case FPD_CollectFile:                /* 15 */
                case FPD_SetInternalParam:           /* 16 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_SetNumSends:                /* 17 */ //                    
                    return 0; // ignored

                case FPD_LoadFile:                   /* 18 */
                case FPD_SetFitTime:                 /* 19 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;
                
                case FPD_SetSamplesPerTick:          /* 20 */
                    // "FPD_SetSamplesPerTick lets you know how many samples there are in a "tick"
                    //  (the basic period of time in FL Studio). This changes when the tempo, PPQ 
                    //  or sample rate have changed. This can be called from the mixing thread."
                    atomicStore(_hostSamplesInATick, Value);
                    return 0;

                case FPD_SetIdleTime:                /* 21 */
                    return 0;

                case FPD_SetFocus:                   /* 22 */
                    return 0;

                case FPD_Transport:                  /* 23 */
                case FPD_MIDIIn:                     /* 24 */
                case FPD_RoutingChanged:             /* 25 */
                case FPD_GetParamInfo:               /* 26 */
                case FPD_ProjLoaded:                 /* 27 */
                case FPD_WrapperLoadState:           /* 28 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_ShowSettings:               /* 29 */
                    // When Settings window is selected or not.
                    return 0;

                case FPD_SetIOLatency:               /* 30 */
                    return 0; // FL gives input/output latency here. Nice idea.

                case FPD_PreferredNumIO:             /* 32 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_GetGUIColor:                /* 33 */
                    return 0; // background color, apparently

                case FPD_CloseAllWindows:            /* 34 */
                case FPD_RenderWindowBitmap:         /* 35 */
                case FPD_StealKBFocus:               /* 36 */
                case FPD_GetHelpContext:             /* 37 */
                case FPD_RegChanged:		         /* 38 */
                case FPD_ArrangeWindows: 	         /* 39 */
                case FPD_PluginLoaded:		         /* 40 */
                    break;

                case FPD_ContextInfoChanged:         /* 41 */
                    // "Index holds the type of information (see CI_ constants), call FHD_GetContextInfo for the new value(s)"
                    debugLogf("Context info %d changed\n", Index);
                    // TODO probably something to do for CI_TrackPan and CI_TrackVolume, host always give this
                    return 0;

                case FPD_ProjectInfoChanged:         /* 42 */
                case FPD_GetDemoPlugins:             /* 43 */
                case FPD_UnLockDemoPlugins:          /* 44 */
                case FPD_ColorWasPicked:             /* 46 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_IsInDebugMode:              /* 47 */
                    // return 0 for no, 1 for yes
                    // When testing, didn't see what it changed anyway.
                    return 0;

                case FPD_ColorsHaveChanged:          /* 48 */
                case FPD_GetStateSizeEstimate:       /* 49 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_UseIncreasedMIDIResolution: /* 50 */
                    return 1; // increased MIDI resolution is supported

                case FPD_ConvertStringToValue:       /* 51 */
                case FPD_GetParamType:               /* 52 */
                    debug(logFLPClient) debugLog("Not implemented\n");
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

            switch (EventID)
            {
                case FPE_Tempo:
                    float tempo = *cast(float*)(&EventValue);
                    atomicStore(_hostTempo, tempo);
                    break;

                default:
                    break;
            }

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

            pOutputs[0][0..Length] = pInputs[0][0..Length];
            pOutputs[1][0..Length] = pInputs[1][0..Length];
            TimeInfo info; // TODO timing information
            _client.processAudioFromHost(pInputs[0..2], pOutputs[0..2], Length, info);

            pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];
            interleaveBuffers(pOutputs[0], pOutputs[1], DestBuffer, Length);
        }

        // generator processing (can render less than length)
        @mixerThread
        void Gen_Render(PWAV32FS DestBuffer, ref int Length)
        {
            // Oddity about Length:
            // "The Length parameter in Gen_Render serves a somewhat different purpose than in 
            //  Eff_Render. It still specifies how many samples are in the buffers for each 
            //  channel, just like in Eff_Render. But this value is a maximum in Gen_Render. 
            //  The generator may choose to generate less samples than Length specifies. In this 
            //  case, Length has to be set to the actual amount of samples that were generated 
            //  before the function returns. For this reason, Length in Gen_Render can be altered
            //  by the function (it is a var parameter in Delphi and a reference (&) in C++)."
            //
            // But here we ignores that and just generates the maximum amount.

            // "You can take a look at Osc3 for an example of what Gen_Render has to do."
            // It seems FLStudio has an envelope and a knowledge of internal voices.
            // TODO: lie to FL about one such voice existing, so that we can get this envelope thingy working.

            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            resetClientIfNeeded(0, 2, Length);

            float*[2] pInputs  = [ _inputBuf[0].ptr,  _inputBuf[1].ptr ];
            float*[2] pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];
            TimeInfo info; // TODO timing information
            _client.processAudioFromHost(pInputs[0..0], pOutputs[0..2], Length, info);
            pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];
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

        // MIDI input message
        @guiThread @mixerThread
        void MIDIIn(ref int Msg)
        {
            // (see FHD_WantMIDIInput & TMIDIOutMsg) 
            // (set Msg to MIDIMsg_Null if it has to be killed)
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

    Client _client;                          /// Wrapped generic client.
    TFruityPlugHost _host;                   /// A whole lot of callbacks to host.
    TFruityPlugInfo _fruityPlugInfo;         /// Plug-in formation for the host to read.
    FLHostCommand _hostCommand;              /// Host command object.

    char[128] _longNameBuf;                  /// Buffer for plugin long name.
    char[32] _shortNameBuf;                  /// Buffer for plugin short name.
    
    shared(size_t) _hostMaxFrames = 512;     /// Max frames that the host demanded.
    @mixerThread int _clientMaxFrames = 0;   /// Max frames last used by client.    
    shared(size_t) _hostSampleRate = 44100;  /// Samplerate that the host demanded.
    @mixerThread int _clientSampleRate = 0;  /// Samplerate last used by client.
    shared(size_t) _hostSamplesInATick = 32; /// Number of samples in a FL "tick".
    shared(float) _hostTempo = 120.0f;       /// Tempo reported by host.
    shared(bool) _hostHostPlaying = false;   /// Whether the host is playing.
    shared(bool) _hostBypass = false;        /// Is the plugin "enabled".

    @mixerThread float[][2] _inputBuf;       /// Temp buffers to deinterleave and pass to plug-in.
    @mixerThread float[][2] _outputBuf;      /// Plug-in outoput, deinterleaved.

    void initializeInfo()
    {
        int flags                     = FPF_NewVoiceParams;
        version(OSX)
            flags |= FPF_MacNeedsNSView;
        if (_client.isSynth)   flags |= FPF_Generator;
        if (!_client.hasGUI)   flags |= FPF_NoWindow; // SDK says it's not implemented? mm.
        if (_client.sendsMIDI) flags |= FPF_MIDIOut;

        if (_client.tailSizeInSeconds() == float.infinity) 
        {
            flags |= FPF_CantSmartDisable;
        }

        _client.getPluginName(_longNameBuf.ptr, 128);        
        _client.getPluginName(_shortNameBuf.ptr, 32); // yup, same name
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

class FLHostCommand: IHostCommand 
{
public:
nothrow @nogc:

    this(TFruityPlugHost pHost)
    {
        _host = pHost;
    }

    ~this()
    {
    }

    override void beginParamEdit(int paramIndex)
    {
        // TODO
    }

    override void paramAutomate(int paramIndex, float value)
    {
        // TODO
    }

    override void endParamEdit(int paramIndex)
    {
        // TODO
    }
    
    override bool requestResize(int widthLogicalPixels, int heightLogicalPixels)
    {
        return false;
    }

    override DAW getDAW()
    {
        return DAW.FLStudio;
    }

    PluginFormat getPluginFormat()
    {
        return PluginFormat.flp;
    }

private:
    TFruityPlugHost _host;

}