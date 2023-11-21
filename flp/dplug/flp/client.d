/**
FL Plugin client.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flp.client;

import core.atomic;
import core.stdc.stdio: snprintf;
import core.stdc.string: strlen, memmove, memset;

import std.array;

import dplug.core.nogc;
import dplug.core.vec;
import dplug.core.sync;
import dplug.core.thread;
import dplug.core.runtime;
import dplug.core.binrange;
import dplug.client.client;
import dplug.client.params;
import dplug.client.graphics;
import dplug.client.midi;
import dplug.client.daw;
import dplug.flp.types;

import std.math: round;


//debug = logFLPClient;

final extern(C++) class FLPCLient : TFruityPlug
{
nothrow @nogc:

    this(TFruityPlugHost pHost, TPluginTag tag, Client client, bool* err)
    {
        this.HostTag = tag;
        this.Info = &_fruityPlugInfo;
        this._host = pHost;
        this._client = client;
        initializeInfo();

        _hostCommand = mallocNew!FLHostCommand(pHost, tag);
        _client.setHostCommand(_hostCommand);

        // If a synth ("generator" in FL dialect), it must supports 0-2.
        // If an effect, it must supports 2-2.
        // Else fail instantiation.

        bool compatibleIO;
        if (_client.isSynth)
        {
            initializeVoices();
            compatibleIO = _client.isLegalIO(0, 2);
        }
        else
            compatibleIO = _client.isLegalIO(2, 2);

        *err = false;
        if (!compatibleIO)
            *err = true;

        _graphicsMutex = makeMutex;
        _midiInputMutex = makeMutex;

        if (_client.receivesMIDI)
            _hostCommand.wantsMIDIInput();

        _hostCommand.disableIdleNotifications();

        _mixingTimeInSamples = 0;
        _hostTicksReference = 0;
        _hostTicksChanged = false;
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

    extern(System) override
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
                //@guiThread
                case FPD_ShowEditor:                 /* 0 */
                    if (Value == 0)
                    {
                        // hide editor
                        if (_client.hasGUI)
                        {
                            _graphicsMutex.lock();
                            _client.closeGUI();
                            _graphicsMutex.unlock();
                            this.EditorHandle = null;
                        }
                    }
                    else
                    {
                        if (_client.hasGUI)
                        {
                            void* parent = cast(void*) Value;
                            _graphicsMutex.lock();
                            void* windowHandle = _client.openGUI(parent, null, GraphicsBackend.autodetect);
                            _graphicsMutex.unlock();
                            this.EditorHandle = windowHandle;
                        }
                    }
                    return 0; // no error, apparently


                // @guiThread, says the documentation
                case FPD_ProcessMode:                /* 1 */
                    // "this ID can be ignored"
                    // Gives a quality hint.

                    // Tell how many internal presets there are.
                    // Quite arbitrarily, this is where we choose to change preset number.
                    // Doing this at plugin creation is ignored.
                    _hostCommand.setNumPresets( _client.presetBank.numPresets() );

                    // Again, for some reason having this in the constructor doesn't work.
                    // Hack to put it in FPD_ProcessMode.
                    if (_client.sendsMIDI)
                        _hostCommand.enableMIDIOut();

                    return 0;

                // @guiThread @mixerThread
                case FPD_Flush:                      /* 2 */
                    // "FPD_Flush warns the plugin that the next samples do not follow immediately
                    //  in time to the previous block of samples. In other words, the continuity is
                    //  broken."
                    // Interesting, Dplug plugins normally handle this correctly already, since it's common
                    // while the DAW is looping.
                    return 0;

                // @guiThread
                case FPD_SetBlockSize:               /* 3 */
                    // Client maxframes will change at next buffer asynchronously. Works from any thread.
                    atomicStore(_hostMaxFrames, Value); 
                    return 0;

                // @guiThread
                case FPD_SetSampleRate:              /* 4 */
                    // Client sampleRate will change at next buffer asynchronously. Works from any thread.
                    atomicStore(_hostSampleRate, Value);
                    return 0; // right return value according to TTestPlug

                // @guiThread
                case FPD_WindowMinMax:               /* 5 */
                    // Minor lol, the FL SDK doesn't define the TRect and Tpoint, those are Delphi types.
                    // Here we assume the ui thread is calling this, but not strictly defined in SDK.

                    _graphicsMutex.lock();
                    IGraphics graphics = _client.getGraphics();

                    // Find min size, in logical pixels.
                    int minX = 1, minY = 1;
                    graphics.getNearestValidSize(&minX,& minY);

                    // Find max size, in logical pixels.
                    int maxX = 32768, maxY = 32768;
                    graphics.getNearestValidSize(&maxX, &maxY);

                    _graphicsMutex.unlock();

                    TRect* outRect = cast(TRect*)Index;
                    outRect.x1 = minX;
                    outRect.y1 = minY;
                    outRect.x2 = maxX;
                    outRect.y2 = maxY;
                    TPoint* outSnap = cast(TPoint*)Value;
                    outSnap.x = 1; // quite smooth really
                    outSnap.y = 1;
                    return 0;

                case FPD_KillAVoice:                 /* 6 */
                    return 0; // refuse to kill a voice

                case FPD_UseVoiceLevels:             /* 7 */
                    // "return 0 if the plugin doesn't support the default per-voice level Index"
                    return 0;

                case FPD_SetPreset:                  /* 9 */
                {
                    int presetIndex = cast(int)Index;
                    if (!_client.presetBank.isValidPresetIndex(presetIndex))
                        return 0;
            
                    // Load preset, doesn't change "current" preset in PresetBank, doesn't
                    // overwrite presetbank.
                    _client.presetBank.preset(presetIndex).loadFromHost(_client);
                    return 0;
                }

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
                    // song position has been relocated (loop, click in timeline...)

                    double ticks, samples;
                    _hostCommand.getMixingTimeInTicks(ticks, samples);

                    // If it's not, we have udged FL unfairly and it can loop in increment lower than ticks.
                    // Interesting.
                    assert(samples == 0);

                    atomicStore(_hostTicksReference, ticks);
                    atomicStore(_hostTicksChanged, true);

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
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_SetFitTime:                 /* 19 */
                    // ignored
                    return 0;
                
                case FPD_SetSamplesPerTick:          /* 20 */
                    // "FPD_SetSamplesPerTick lets you know how many samples there are in a "tick"
                    //  (the basic period of time in FL Studio). This changes when the tempo, PPQ 
                    //  or sample rate have changed. This can be called from the mixing thread."
                    float fValue = *cast(float*)(&Value);
                    atomicStore(_hostSamplesInATick, fValue);
                    return 0;

                case FPD_SetIdleTime:                /* 21 */
                    return 0;

                case FPD_SetFocus:                   /* 22 */
                    return 0;

                case FPD_Transport:                  /* 23 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_MIDIIn:                     /* 24 */
                {
                    // Not sure when this message should come.
                    debug(logFLPClient) debugLog("FPD_MIDIIn\n");
                    break;
                }

                case FPD_RoutingChanged:             /* 25 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_GetParamInfo:               /* 26 */
                {
                    enum int PI_CantInterpolate    = 1;     // makes no sense to interpolate parameter values (when values are not levels)
                    enum int PI_Float              = 2;     // parameter is a normalized (0..1) single float. (Integer otherwise)
                    enum int PI_Centered           = 4;     // parameter appears centered in event editors

                    if (!_client.isValidParamIndex(cast(int)Index))
                        return 0;

                    Parameter param = _client.param(cast(int)Index);
                    if (auto bp = cast(BoolParameter)param)
                    {
                        return PI_CantInterpolate;
                    }
                    else if (auto ip = cast(IntegerParameter)param)
                    {
                        return PI_CantInterpolate;
                    }
                    else if (auto fp = cast(FloatParameter)param)
                    {
                        return 0;
                    }
                    else
                    {
                        assert(false); // TODO whenever there is more parameter types around.
                    }
                }

                case FPD_ProjLoaded:                 /* 27 */
                    // "called after a project has been loaded, to leave a chance to kill 
                    //  automation (that could be loaded after the plugin is created)"
                    // Well, we don't mess with user sessions around here.
                    return 0;

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
                case FPD_RegChanged:                 /* 38 */
                case FPD_ArrangeWindows:             /* 39 */
                case FPD_PluginLoaded:               /* 40 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_ContextInfoChanged:         /* 41 */
                    // "Index holds the type of information (see CI_ constants), call FHD_GetContextInfo for the new value(s)"
                    debug(logFLPClient) debugLogf("Context info %d changed\n", Index);
                    // TODO probably something to do for CI_TrackPan and CI_TrackVolume, host always give this
                    return 0;

                case FPD_ProjectInfoChanged:         /* 42 */
                case FPD_GetDemoPlugins:             /* 43 */
                case FPD_UnLockDemoPlugins:          /* 44 */
                case FPD_ColorWasPicked:             /* 46 */
                    debug(logFLPClient) debugLog("Not implemented\n");
                    break;

                case FPD_IsInDebugMode:              /* 47 */
                    // When testing, didn't see what it changes anyway, perhaps logging.
                    debug(logFLPClient)
                        return 1;
                    else
                        return 0;

                case FPD_ColorsHaveChanged:          /* 48 */
                    // We don't really care about that.
                    return 0; 


                case FPD_GetStateSizeEstimate:       /* 49 */
                    return _client.params().length * 8;

                case FPD_UseIncreasedMIDIResolution: /* 50 */
                    // increased MIDI resolution is supported, this seems related to REC_FromMIDI 
                    // having an updated range.
                    // It is also ignored by FL12 and probably earlier FL.
                    return 1; 

                case FPD_ConvertStringToValue:       /* 51 */
                    return 0;


                case FPD_GetParamType:               /* 52 */



                    // FPD_GetParamType options
                    enum int PT_Default = 0;
                    enum int PT_Db = 1;
                    enum int PT_Hz = 2;
                    enum int PT_Centered = 3;
                    enum int PT_Ms = 4;
                    enum int PT_Percent = 5;
                    enum int PT_Time = 6;
                    enum int PT_Value = 7;
                    enum int PT_Number = 8;
                    enum int PT_Text = 9;
                    int iparam = cast(int)Index;

                    if ( ! _client.isValidParamIndex(iparam))
                    {
                        return PT_Default;
                    }

                    return PT_Default;// not sure why implement that correctly

                    /*
                    Parameter p = _client.param(iparam);
                    if (p.label == "ms")
                        return PT_Ms;
                    else if (p.label == "%")
                        return PT_Percent;
                    else if (p.label == "Hz")
                        return PT_Hz;
                    else
                        return PT_Value;
                    */

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
        void SaveRestoreState(IStream Stream, BOOL Save)
        {
            // SDK documentation says it's for Parameters mostly, so indeed we need the full chunk,
            // not just the extra binary state.

            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            static immutable ubyte[8] MAGIC = ['D', 'F', 'L', '0', 0, 0, 0, 0];

            // Being @guiThread, we assume SaveRestoreState is not called twice simultaneously.
            // Hence, _lastChunk is used for both saving and restoring.

            if (Save)
            {
                debug(logFLPClient) debugLog("SaveRestoreState save a chunk\n");

                _lastChunk.clearContents();

                // We need additional framing, since FL provide no chunk length on read.
                // Our chunk looks like this:
                // -------------    
                // 0000 "DFL0"      // Version of our chunking for dplug:flp client.
                // 0004 len         // Bytes in following chunk, 32-bit uint, Little Endian. 
                // 0008 <chunk>     // Chunk given by dplug:client.
                // -------------

                for (int n = 0; n < 8; ++n)
                    _lastChunk.pushBack(MAGIC[n]); // add room for len too

                size_t sizeBefore = _lastChunk.length;
                _client.presetBank.appendStateChunkFromCurrentState(_lastChunk);
                size_t sizeAfter = _lastChunk.length;
                size_t len = cast(int)(sizeAfter - sizeBefore);

                // If you fail here, your saved chunk exceeds 2gb, which is probably an error.
                assert(len + 8 <= int.max);

                // Update len field
                ubyte[] lenLoc = _lastChunk[4..8];
                writeLE!uint(lenLoc, cast(uint)len);

                ULONG written;
                Stream.Write(_lastChunk.ptr, cast(int)_lastChunk.length, &written);
            }
            else
            {
                debug(logFLPClient) debugLog("SaveRestoreState load a chunk\n");

                ubyte[8] header;
                ULONG read;
                HRESULT hr = Stream.Read(header.ptr, 8, &read);
                if (hr < 0 || read != 8)
                    return;     

                if (header[0..4] != MAGIC[0..4])
                    return; // unrecognized chunks and/or version

                bool err;
                const(ubyte)[] lenLoc = header[4..8];
                uint len = popLE!uint(lenLoc, &err);
                if (err)
                    return;

                // plan to read as much from Stream
                _lastChunk.resize(len);
                hr = Stream.Read(_lastChunk.ptr, len, &read);
                if (hr < 0 || read != len)
                    return;

                // Load chunk in client
                _client.presetBank.loadStateChunk(_lastChunk[], &err);
                if (err)
                    return;
            }
        }

        // names (see FPN_Param) (Name must be at least 256 chars long)
        @guiThread
        void GetName(int Section, int Index, int Value, char *Name)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            if (Section == FPN_Param)
            {
                if (!_client.isValidParamIndex(Index))
                    return;
                string name = _client.param(Index).name;
                snprintf(Name, 256, "%.*s", cast(int)name.length, name.ptr);                
            }
            else if (Section == FPN_ParamValue)
            {
                if (!_client.isValidParamIndex(Index))
                    return;
                Parameter param = _client.param(Index);
                param.toDisplayN(Name, 256);
                size_t len = strlen(Name);
                string unitLabel = param.label();

                // Add the unit if enough room.
                if ((unitLabel.length > 0) && (len + unitLabel.length < 254))
                {
                    snprintf(Name + len, 256 - len, "%.*s", cast(int)unitLabel.length, unitLabel.ptr);
                }
            }
            else if (Section == FPN_Preset)
            {
                if (!_client.presetBank.isValidPresetIndex(Index))
                    return;

                const(char)[] name = _client.presetBank.preset(Index).name;
                snprintf(Name, 256, "%.*s", cast(int)name.length, name.ptr);
            }
            else
            {
                debug(logFLPClient) debugLogf("Unsupported name Section = %d\n", Section);
            }
            version(DigitalMars)
                Name[255] = '\0'; // DigitalMars snprintf workaround
        }

        // events
        @guiThread @mixerThread
        int ProcessEvent(int EventID, int EventValue, int Flags)
        {
            switch (EventID)
            {
                case FPE_Tempo:
                    float tempo = *cast(float*)(&EventValue);
                    atomicStore(_hostTempo, tempo);
                    break;

                case FPE_MaxPoly:
                    // ignored, we use 100 as default value instead
                    int maxPoly = EventValue;
                    break;

                case FPE_MIDI_Pitch:
                    // ignored, we use 100 as default value instead
                    debug(logFLPClient) debugLogf("FPE_MIDI_Pitch = %d\n", EventValue);
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
            int origValue = Value;

            enum int REC_UpdateValue       =1;     // update the value
            enum int REC_GetValue          =2;     // retrieves the value
            enum int REC_ShowHint          =4;     // updates the hint (if any)
            enum int REC_UpdateControl     =16;    // updates the wheel/knob
            enum int REC_FromMIDI          =32;    // value from 0 to FromMIDI_Max has to be translated (& always returned, even if REC_GetValue isn't set)
            enum int REC_NoLink            =1024;  // don't check if wheels are linked (internal to plugins, useful for linked controls)
            enum int REC_InternalCtrl      =2048;  // sent by an internal controller - internal controllers should pay attention to those, to avoid nasty feedbacks
            enum int REC_PlugReserved      =4096;  // free to use by plugins

            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            if ( ! _client.isValidParamIndex(Index))
            {
                return Value; // well,  as gain example
            }

            // Rather protracted callback.
            //
            // "First, you need to check if REC_FromMIDI is included. If it is, this means that the
            //  Value parameter contains a value between 0 and <smthg>. This Value then needs to be 
            //  translated to fall in the range that the plugin uses for the parameter. For this 
            //  reason, TDelphiFruityPlug and TCPPFruityPlug implement the function TranslateMidi. 
            //  You pass it Value and the minimum and maximum value of your parameter, and it 
            //  returns the right value.
            //  REC_FromMIDI is really important and has to be supported by the plugin. It is not 
            //  just used by FL Studio to provide you with a new parameter value, but also to 
            //  determine the minimum and maximum values for a parameter."

            Parameter param = _client.param(Index);
            float Valuef; // use instead of Value, if the parameter is FloatParameter.
          
            if (RECFlags & REC_FromMIDI)
            {
                // Example says 1073741824 as max value
                // Doc says 65536 as max value, but it is wrong.
                double normalizeMIDI = 1.0 / 1073741824.0;

                // Before FL20, this maximum value is 65536.
                if (_host.majorVersion() < 20)
                    normalizeMIDI = 1.0 / 65536.0;

                double fNormValue = Value * normalizeMIDI;
                
                if (auto bp = cast(BoolParameter)param)
                {
                    Value = (fNormValue >= 0.5 ? 1 : 0);
                }
                else if (auto ip = cast(IntegerParameter)param)
                {
                    Value = ip.fromNormalized(fNormValue);
                }
                else if (auto fp = cast(FloatParameter)param)
                {
                    Valuef = fp.fromNormalized(fNormValue);
                }
                else
                {
                    assert(false); // TODO whenever there is more parameter types around.
                }
            }
            else
            {
                Valuef = 0.0f; // whatever, will be unused
                if (auto fp = cast(FloatParameter)param)
                {
                    Valuef = *cast(float*)&Value;
                }
            }

            // At this point, both Value (or Valuef) contain a value provided by the host.
            // In non-normalized space.

            if (RECFlags & REC_UpdateValue)
            {
                // Choosing to ignore REC_UpdateControl here, not sure why it would be the host
                // prerogative. Especially with the issue of double-updates when editing.
                //
                // Parameters setFromHost take only normalized things, so that's what we do, we
                // get (back?) to normalized space.
                if (auto bp = cast(BoolParameter)param)
                {
                    bp.setFromHost(Value ? 1.0 : 0.0);
                }
                else if (auto ip = cast(IntegerParameter)param)
                {
                    ip.setFromHost(ip.toNormalized(Value));
                }
                else if (auto fp = cast(FloatParameter)param)
                {
                    fp.setFromHost(fp.toNormalized(Valuef));
                }
                else
                {
                    assert(false);
                }
            }
            else if (RECFlags & REC_GetValue) 
            {
                if (auto bp = cast(BoolParameter)param)
                {
                    Value = bp.value() ? 1 : 0;
                }
                else if (auto ip = cast(IntegerParameter)param)
                {
                    Value = ip.value();
                }
                else if (auto fp = cast(FloatParameter)param)
                {
                    float v = fp.value();
                    Value = *cast(int*)&v;
                }
                else
                {
                    assert(false);
                }
            }
            return Value;
        }

        // effect processing (source & dest can be the same)
        @mixerThread
        void Eff_Render(PWAV32FS SourceBuffer, PWAV32FS DestBuffer, int Length)
        {
            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            resetClientIfNeeded(2, 2, Length);
            enqueuePendingMIDIInputMessages();

            bool bypass = atomicLoad(_hostBypass);

            TimeInfo info;
            updateTimeInfoBegin(info);

            // clear MIDI out buffers
            if (_client.sendsMIDI)
                _client.clearAccumulatedOutputMidiMessages();

            if (bypass)
            {
                // Note: no delay compensation.
                // Do nothing for MIDI messages, same as VST3. Not sure what should happen here.
                memmove(DestBuffer, SourceBuffer, Length * float.sizeof * 2);
            }
            else
            {
                float*[2] pInputs  = [ _inputBuf[0].ptr,  _inputBuf[1].ptr  ];
                float*[2] pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];

                deinterleaveBuffers(SourceBuffer, pInputs[0], pInputs[1], Length);

                pOutputs[0][0..Length] = pInputs[0][0..Length];
                pOutputs[1][0..Length] = pInputs[1][0..Length];

                _client.processAudioFromHost(pInputs[0..2], pOutputs[0..2], Length, info);

                pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];
                interleaveBuffers(pOutputs[0], pOutputs[1], DestBuffer, Length);
            }
            sendPendingMIDIOutput();
            updateTimeInfoEnd(Length);
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

            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();

            resetClientIfNeeded(0, 2, Length);
            enqueuePendingMIDIInputMessages();

            bool bypass = atomicLoad(_hostBypass); // Note: it seem FL prefers to simply not send MIDI rather than this.

            TimeInfo info;
            updateTimeInfoBegin(info);

            // clear MIDI out buffers
            if (_client.sendsMIDI)
                _client.clearAccumulatedOutputMidiMessages();

            if (bypass)
            {
                // Do nothing for MIDI messages, same as VST3. Not sure what should happen here.
                memset(DestBuffer, 0, Length * float.sizeof * 2);
            }
            else
            {
                float*[2] pInputs  = [ _inputBuf[0].ptr,  _inputBuf[1].ptr ];
                float*[2] pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];
                _client.processAudioFromHost(pInputs[0..0], pOutputs[0..2], Length, info);
                pOutputs = [ _outputBuf[0].ptr, _outputBuf[1].ptr ];
                interleaveBuffers(pOutputs[0], pOutputs[1], DestBuffer, Length);                
            }
            sendPendingMIDIOutput();
            updateTimeInfoEnd(Length);
        }

        // <voice handling>
        // Some documentation says all such voice handling function are actually only @mixerThread.
        // Contradicts what the header says: "(GM)".
        // We'll makea trust call here and consider the function ARE 
        @guiThread @mixerThread
        TVoiceHandle TriggerVoice(TVoiceParams* VoiceParams, intptr_t SetTag)
        {

            // note sure what InitLevels to take?

            float noteInMidiScale = VoiceParams.InitLevels.Pitch / 100.0f;

            // FUTURE: put the reminder in some other MIDI message

            int noteNumber = cast(int) round( noteInMidiScale );
            float fractionalNote = noteInMidiScale - noteNumber;

            if (noteNumber < 0 || noteNumber > 127)
                return 0;

            int ivoice = allocVoice(VoiceParams, SetTag, ++_totalVoicesTriggered, noteNumber);

            if (ivoice == -1)
                return 0; // hopefully it means "no voice created"

            // Since from documentation, mixer lock is taken here, we can absolutely enqueue MIDI
            // messages from here.

            float Vol = VoiceParams.InitLevels.Vol;
            int velocity = cast(int)(128.0f * Vol);
            if (velocity < 1) velocity = 1;
            if (velocity > 127) velocity = 127;

            int channel = 0;
            _client.enqueueMIDIFromHost( makeMidiMessageNoteOn(0, channel, noteNumber, velocity) );

            // The handle is simply 1 + ivoice, so that we don't return zero.
            return 1 + ivoice;
        }

        @guiThread @mixerThread
        void Voice_Release(TVoiceHandle Handle)
        {
            if (Handle == 0)
                return;

            int channel = 0;
            int midiNote = voiceInfo(Handle).midiNote;
            int noteOffVelocity = 100; // unused, FUTURE
            _client.enqueueMIDIFromHost( makeMidiMessageNoteOff(0, channel, midiNote) ); 
            int index = cast(int)(Handle - 1);
            freeVoiceIndex(index);
        }

        @guiThread @mixerThread
        void Voice_Kill(TVoiceHandle Handle)
        {
            if (Handle == 0)
                return;

            if (voiceInfo(Handle).state == VOICE_PLAYING)
            {
                // Send note off, since it went from trigger to kill without release.
                int channel = 0;
                int midiNote = voiceInfo(Handle).midiNote;
                int noteOffVelocity = 100; // unused, FUTURE
                _client.enqueueMIDIFromHost( makeMidiMessageNoteOff(0, channel, midiNote) );

                int index = cast(int)(Handle - 1);
                freeVoiceIndex(index);
            }

            // Do nothing, we already sent a Note Off in Voice_release.
        }

        @guiThread @mixerThread
        int Voice_ProcessEvent(TVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags)
        {
            if (Handle == 0)
                return 0;

            // TODO retrigger should send a MIDI OFF, then a MIDI ON if voice alive.

            ScopedForeignCallback!(false, true) scopedCallback;
            scopedCallback.enter();
            return 0;
        }

        @guiThread @mixerThread
        int Voice_Render(TVoiceHandle Handle, PWAV32FS DestBuffer, ref int Length)
        {
            // Shouldn't be called ever, as we don't support generators that renders their voices separately.
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
            // If host calls this despite not receiving MIDI, we should evaluate our assumptions
            // regarding FL and MIDI Input.
            assert(_client.receivesMIDI);

            // This is our own Mutex
            ubyte status = Msg & 255;
            ubyte data1  = (Msg >>> 8) & 255;
            ubyte data2  = (Msg >>> 16) & 255;

            // In practice, MIDIIn is called from the mixer thread, so no sync issue are seen 
            // happen with guiThread calling `MIDIIn`. But since it's still possible from 
            // documentation, let's be good citizens and use a separate buffer.
            // Then enqueue it from the mixer thread before a buffer.
            int offset = 0; // FLStudio pass no offset, maybe it splits buffers alongside MIDI messages?
            MidiMessage msg = MidiMessage(offset, status, data1, data2);

            _midiInputMutex.lock();
            _incomingMIDI.pushBack(msg);
            _midiInputMutex.unlock();

            // Why would we "kill" the message? Not sure. FLStudio uses a rather clean Port + Channel way to route MIDI.
            // So: let's not kill it.
            bool kill = false;
            if (kill)
            {
                enum int MIDIMsg_Null = 0xFFFF_FFFF;
                Msg = MIDIMsg_Null; // kill message
            }
        }

        // buffered messages to itself (see PlugMsg_Delayed)
        @midiSyncThread
        void MsgIn(intptr_t Msg)
        {
            // Not sure why it's there.
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

    enum double MiddleCFreq = 523.251130601197;
    enum double MiddleCMul = cast(float)0x10000000 * MiddleCFreq * cast(float)0x10;

    Client _client;                          /// Wrapped generic client.
    TFruityPlugHost _host;                   /// A whole lot of callbacks to host.
    TFruityPlugInfo _fruityPlugInfo;         /// Plug-in formation for the host to read.
    FLHostCommand _hostCommand;              /// Host command object.
    UncheckedMutex _graphicsMutex;           /// An oddity mandated by dplug:client.

    char[128] _longNameBuf;                  /// Buffer for plugin long name.
    char[32] _shortNameBuf;                  /// Buffer for plugin short name.
    
    shared(size_t) _hostMaxFrames = 512;     /// Max frames that the host demanded.
    @mixerThread int _clientMaxFrames = 0;   /// Max frames last used by client.    
    shared(size_t) _hostSampleRate = 44100;  /// Samplerate that the host demanded.
    @mixerThread int _clientSampleRate = 0;  /// Samplerate last used by client.
    shared(float) _hostTempo = 120.0f;       /// Tempo reported by host.
    shared(bool) _hostHostPlaying = false;   /// Whether the host is playing.
    shared(bool) _hostBypass = false;        /// Is the plugin "enabled".

    @mixerThread float[][2] _inputBuf;       /// Temp buffers to deinterleave and pass to plug-in.
    @mixerThread float[][2] _outputBuf;      /// Plug-in outoput, deinterleaved.

    // Time management
    @mixerThread long _mixingTimeInSamples;    /// Only ever updated in mixer thread. Current stime.
    shared(double) _hostTicksReference;        /// Last tick reference given by host.
    shared(bool) _hostTicksChanged;            /// Set to true if tick reference changed. If true, 
                                               /// Look at `_hostTicksReference` value.
    shared(float) _hostSamplesInATick = 32.0f; /// Last known conversion from ticks to samples.

    Vec!MidiMessage _incomingMIDI;           /// Incoming MIDI messages for next buffer.
    UncheckedMutex _midiInputMutex;          /// Protects access to _incomingMIDI.
    Vec!ubyte _lastChunk;

    void initializeInfo()
    {
        int flags                     = FPF_NewVoiceParams;
        version(OSX)
            flags |= FPF_MacNeedsNSView;
        if (_client.isSynth)      flags |= FPF_Generator;
        if (!_client.hasGUI)      flags |= FPF_NoWindow; // SDK says it's not implemented? mm.
        if (_client.sendsMIDI)    flags |= FPF_MIDIOut;
        if (_client.receivesMIDI) flags |= FPF_GetNoteInput; // Note: generators ignore this apparently.

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

            // Report new latency
            _hostCommand.reportLatency(_client.latencySamples(_clientSampleRate));
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

    @mixerThread
    void enqueuePendingMIDIInputMessages()
    {
        if (!_client.receivesMIDI)
            return;

        _midiInputMutex.lock();
        foreach(msg; _incomingMIDI[])
        {
            _client.enqueueMIDIFromHost(msg);
        }
        _incomingMIDI.clearContents();
        _midiInputMutex.unlock();
    }

    @mixerThread
    void sendPendingMIDIOutput()
    {
        if (!_client.sendsMIDI)
            return;

        const(MidiMessage)[] outMsgs = _client.getAccumulatedOutputMidiMessages();

        foreach(msg; outMsgs)
        {
            ubyte[4] bytes = [0, 0, 0, 0];
            int len = msg.toBytes(bytes.ptr, 3);

            if (len == 0 || len > 3)
            {
                // nothing written, or length exceeded, ignore this message
                continue;
            }

            TMIDIOutMsg outMsg;
            outMsg.Status = bytes[0];
            outMsg.Data1 = bytes[1];
            outMsg.Data2 = bytes[2];

            // FUTURE: MIDI out for FLPlugins will need a way to change 
            // its output port... else not really usable in FL.
            // Well, you can still multiplex on channels I guess.
            outMsg.Port = 0; 

            // Let's trust FL to not need that pointer beyond that host call.
            debug(logFLPClient) debugLogf("  pass %d %d %d to host\n", bytes[0], bytes[1], bytes[2]);
            _hostCommand.sendMIDIMessage(*cast(uint*)&outMsg);
        }
    }

    // <voice pool>

    enum int VOICE_NOT_PLAYING = 0;
    enum int VOICE_PLAYING = 1;

    void initializeVoices()
    {
        availableVoices = MAX_FL_POLYPHONY;
        for (int n = 0; n < MAX_FL_POLYPHONY; ++n)
        {
            availableVoiceList[n] = n;
            voicePool[n].state = VOICE_NOT_PLAYING;
        }
    }

    // -1 if nothing available.
    int allocVoiceIndex()
    {
        if (availableVoices <= 0)
            return -1;

        int index = availableVoiceList[--availableVoices];
        assert(voicePool[index].state == VOICE_NOT_PLAYING);
        voicePool[index].state = VOICE_PLAYING;
        return index;
    }

    void freeVoiceIndex(int voiceIndex)
    {
        // Note: we don't check that FL gives back right voice ID there. Real trust going on there.
        assert(voicePool[voiceIndex].state == VOICE_PLAYING);
        voicePool[voiceIndex].state = VOICE_NOT_PLAYING;
        availableVoiceList[availableVoices++] = voiceIndex;        
        assert(availableVoices <= MAX_FL_POLYPHONY);
    }

    static struct VoiceInfo
    {
        int state;
        TVoiceParams* params;
        intptr_t tag;
        int numTotalVoiceTriggered;
        int midiNote; // 0 to 127

        bool isPlaying()
        {
            return state != VOICE_NOT_PLAYING;
        }
    }

    enum int MAX_FL_POLYPHONY = 100; // maximum possible of voices for generators.
    VoiceInfo[MAX_FL_POLYPHONY] voicePool;

    ref VoiceInfo voiceInfo(TVoiceHandle handle)
    {
        assert(handle != 0);
        return voicePool[handle - 1];
    }

    // stack of available voice indices.
    int[MAX_FL_POLYPHONY] availableVoiceList; // availableVoiceList[0..availableVoices] are the available indices.
    int availableVoices;
    int _totalVoicesTriggered; // a bit more unique identifier

    // -1 if not available
    int allocVoice(TVoiceParams* VoiceParams, intptr_t SetTag, int totalVoiceCount, int midiNote)
    {
        int index = allocVoiceIndex();

        if (index == -1)
            return -1;

        voicePool[index].state = VOICE_PLAYING;
        voicePool[index].params = VoiceParams;
        voicePool[index].tag = SetTag;
        voicePool[index].numTotalVoiceTriggered = totalVoiceCount;
        voicePool[index].midiNote = midiNote;
        return index;
    }

    // </voice pool>


    @mixerThread
    void updateTimeInfoBegin(out TimeInfo info)
    {
        if (cas(&_hostTicksChanged, true, false))
        {
            float samplesInTick = atomicLoad(_hostSamplesInATick);
            double hostTicks = atomicLoad(_hostTicksReference);

            // Not sure if .t2 should be added, but well.
            // I haven't seen FL loop with non-zero t2.
            _mixingTimeInSamples = cast(long)(hostTicks * samplesInTick);
        }

        info.tempo         = atomicLoad(_hostTempo);
        info.hostIsPlaying = atomicLoad(_hostHostPlaying);
        info.timeInSamples = _mixingTimeInSamples;

        //debug(logFLPClient) debugLogf("playing = %d  time = %llu\n", info.hostIsPlaying, info.timeInSamples);
    }

    @mixerThread
    void updateTimeInfoEnd(int samplesElapsed)
    {
        _mixingTimeInSamples += samplesElapsed;
    }
}

class FLHostCommand : IHostCommand 
{
public:
nothrow @nogc:

    this(TFruityPlugHost pHost,TPluginTag tag)
    {
        _host = pHost;
        _tag = tag;
    }

    ~this()
    {
    }

    override void beginParamEdit(int paramIndex)
    {
        // not needed in FL
    }

    override void paramAutomate(int paramIndex, float value)
    {
        // "In order to make your parameters recordable in FL Studio, you have to call this 
        //  function whenever a parameter is changed from within your plugin (probably because
        //  the user turned a wheel or something). You need to pass HostTag in the Sender 
        //  parameter. To let the host know which parameter has just been changed, pass the 
        //  parameter index in Index. Finally, pass the new value (as an integer) in Value."

        _host.OnParamChanged(_tag, paramIndex, *cast(int*)&value);
    }

    override void endParamEdit(int paramIndex)
    {
        // not needed in FL
    }
    
    override bool requestResize(int widthLogicalPixels, int heightLogicalPixels)
    {
        return false;
    }

    override bool notifyResized()
    {
        _host.Dispatcher(_tag, FHD_EditorResized, 0, 0);
        return true;
    }

    override DAW getDAW()
    {
        return DAW.FLStudio;
    }

    PluginFormat getPluginFormat()
    {
        return PluginFormat.flp;
    }

    void setNumPresets(int numPresets)
    {
        int res = cast(int) _host.Dispatcher(_tag, FHD_SetNumPresets, 0, numPresets);
    }

    void wantsMIDIInput()
    {
        _host.Dispatcher(_tag, FHD_WantMIDIInput, 0, 1);
    }

    void reportLatency(int latencySamples)
    {
        _host.Dispatcher(_tag, FHD_SetLatency, 0, latencySamples);
    }

    void disableIdleNotifications()
    {
        _host.Dispatcher(_tag, FHD_WantIdle, 0, 0);
    }

    void enableMIDIOut()
    {
        _host.Dispatcher(_tag, FHD_ActivateMIDI, 0, 0);
    }

    void sendMIDIMessage(uint Msg)
    {
        _host.MIDIOut_Delayed(_tag, Msg); // _host.MIDIOut doesn't work!
    }

    void getMixingTimeInTicks(out double ticks, out double samplesOffset)
    {
        enum int GT_Beats          = 0;          // beats
        enum int GT_AbsoluteMS     = 1;          // absolute milliseconds
        enum int GT_RunningMS      = 2;          // running milliseconds
        enum int GT_MSSinceStart   = 3;          // milliseconds since soundcard restart
        enum int GT_Ticks          = 4;          // ticks
        enum int GT_LocalTime      = 1 << 31;    // time relative to song start

        enum int GT_FlagsMask      = 0xFFFFFF00;
        enum int GT_TimeFormatMask = 0x000000FF;

        _time.t = 0;
        _time.t2 = 0;
       intptr_t Value = cast(intptr_t) &_time;
       intptr_t res = _host.Dispatcher(_tag, FHD_GetMixingTime, GT_Ticks | GT_LocalTime, Value);
       ticks = _time.t;
       samplesOffset = _time.t2;
    }

private:
    TFruityPlugHost _host;
    TPluginTag _tag;
    TFPTime _time;
}