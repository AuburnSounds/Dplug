/**
FL Plugin interface.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flp.types;

nothrow @nogc:

import core.stdc.config;

// interlaced stereo 32Bit float buffer
alias TWAV32FS = float[2];
alias PWAV32FS = TWAV32FS*;
alias TWAV32FM = float;
alias PWAV32FM = float*;

// MIDI out message structure (3 bytes standard MIDI message + port)
struct TMIDIOutMsg
{
    align(1):
    char Status;
    char Data1;
    char Data2;
    char Port;
}
static assert(TMIDIOutMsg.sizeof == 4);
alias PMIDIOutMsg = TMIDIOutMsg*;

// Bar:Step:Tick
struct TSongTime
{
    int Bar;
    int Step;
    int Tick;
}

// Time sig info (easily converted to standard x/x time sig, but more powerful)
struct TTimeSigInfo
{
    int StepsPerBar;
    int StepsPerBeat;
    int PPQ;
}

deprecated alias HINSTANCE = void*;
deprecated alias HMENU = void*;
deprecated alias DWORD = uint;
deprecated alias HWND = void*;
alias HANDLE = void*;
deprecated enum MAX_PATH = 256;
deprecated alias ULONG = uint;
deprecated alias HRESULT = c_long;
deprecated alias ULARGE_INTEGER = ulong;
deprecated alias LARGE_INTEGER = long;

// plugin flags
enum int FPF_Generator         = 1;        // plugin is a generator (not effect)
enum int FPF_RenderVoice       = 1 << 1;   // generator will render voices separately (Voice_Render) (not used yet)
enum int FPF_UseSampler        = 1 << 2;   // 'hybrid' generator that will stream voices into the host sampler (Voice_Render)
enum int FPF_GetChanCustomShape= 1 << 3;   // generator will use the extra shape sample loaded in its parent channel (see FPD_ChanSampleChanged)
enum int FPF_GetNoteInput      = 1 << 4;   // plugin accepts note events (not used yet, but effects might also get note input later)
enum int FPF_WantNewTick       = 1 << 5;   // plugin will be notified before each mixed tick (& be able to control params (like a built-in MIDI controller) (see NewTick))
enum int FPF_NoProcess         = 1 << 6;   // plugin won't process buffers at all (FPF_WantNewTick, or special visual plugins (Fruity NoteBook))
enum int FPF_NoWindow          = 1 << 10;  // plugin will show in the channel settings window & not in its own floating window
enum int FPF_Interfaceless     = 1 << 11;  // plugin doesn't provide its own interface (not used yet)
enum int FPF_TimeWarp          = 1 << 13;  // supports timewarps, that is, can be told to change the playing position in a voice (direct from disk music tracks, ...) (not used yet)
enum int FPF_MIDIOut           = 1 << 14;  // plugin will send MIDI out messages (only those will be enabled when rendering to a MIDI file)
enum int FPF_DemoVersion       = 1 << 15;  // plugin is a trial version, & the host won't save its automation
enum int FPF_CanSend           = 1 << 16;  // plugin has access to the send tracks, so it can't be dropped into a send track or into the master
enum int FPF_MsgOut            = 1 << 17;  // plugin will send delayed messages to itself (will require the internal sync clock to be enabled)
enum int FPF_HybridCanRelease  = 1 << 18;  // plugin is a hybrid generator & can release its envelope by itself. If the host's volume envelope is disabled, then the sound will keep going when the voice is stopped, until the plugin has finished its own release
enum int FPF_GetChanSample     = 1 << 19;  // generator will use the sample loaded in its parent channel (see FPD_ChanSampleChanged)
enum int FPF_WantFitTime       = 1 << 20;  // fit to time selector will appear in channel settings window (see FPD_SetFitTime)
enum int FPF_NewVoiceParams    = 1 << 21;  // MUST BE USED - tell the host to use TVoiceParams instead of TVoiceParams_Old
enum int FPF_Reserved1         = 1 << 22;  // don't use (Delphi version specific)
enum int FPF_CantSmartDisable  = 1 << 23;  // plugin can't be smart disabled
enum int FPF_WantSettingsBtn   = 1 << 24;  // plugin wants a settings button on the titlebar (mainly for the wrapper)
enum int FPF_CanStealKBFocus   = 1 << 25;  // plugin can steal keyboard focus away from FL
enum int FPF_VFX               = 1 << 26;  // is VFX plugin
enum int FPF_MacNeedsNSView    = 1 << 27;  // On Mac: This plugin requires a NSView parent


// plugin dispatcher ID's
// called from GUI thread unless specified
enum int FPD_ShowEditor        =0;     // shows the editor (ParentHandle in Value)
enum int FPD_ProcessMode       =1;     // sets processing mode flags (flags in value) (can be ignored)
enum int FPD_Flush             =2;     // breaks continuity (empty delay buffers, filter mem, etc.) (warning: can be called from the mixing thread) (GM)
enum int FPD_SetBlockSize      =3;     // max processing length (samples) (in value)
enum int FPD_SetSampleRate     =4;     // sample rate in Value
enum int FPD_WindowMinMax      =5;     // allows the plugin to set the editor window resizable (min/max PRect in index, sizing snap PPoint in value)
enum int FPD_KillAVoice        =6;     // (in case the mixer was eating way too much CPU) the plugin is asked to kill its weakest voice & return 1 if it did something (not used yet)
enum int FPD_UseVoiceLevels    =7;     // return 0 if the plugin doesn't support the default per-voice level Index
                                        // return 1 if the plugin supports the default per-voice level Index (filter cutoff (0) or filter resonance (1))
                                        // return 2 if the plugin supports the per-voice level Index, but for another function (then check FPN_VoiceLevel)
                                        //=8;     (private message)
enum int FPD_SetPreset         =9;     // set internal preset Index (mainly for wrapper)
enum int FPD_ChanSampleChanged =10;    // (see FPF_GetChanCustomShape) sample has been loaded into the parent channel, & given to the plugin
// either as a wavetable (FPF_GetChanCustomshape) (pointer to shape in Value, same format as WaveTables)
// or as a sample (FPF_GetChanSample) (TSampleHandle in Index)
enum int FPD_SetEnabled        =11;    // the host has enabled/disabled the plugin (state in Value) (warning: can be called from the mixing thread) (GM)
enum int FPD_SetPlaying        =12;    // the host is playing (song pos info is valid when playing) (state in Value) (warning: can be called from the mixing thread) (GM)
enum int FPD_SongPosChanged    =13;    // song position has been relocated (by other means than by playing of course) (warning: can be called from the mixing thread) (GM)
enum int FPD_SetTimeSig        =14;    // PTimeSigInfo in Value (GM)
enum int FPD_CollectFile       =15;    // let the plugin tell which files need to be collected or put in zip files. File # in Index, starts from 0 until no more filenames are returned (PChar in Result).
enum int FPD_SetInternalParam  =16;    // (private message to known plugins, ignore) tells the plugin to update a specific, non-automated param
enum int FPD_SetNumSends       =17;    // tells the plugin how many send tracks there are (fixed to 4, but could be set by the user at any time in a future update) (number in Value) (!!! will be 0 if the plugin is in the master or a send track, since it can't access sends)
enum int FPD_LoadFile          =18;    // when a file has been dropped onto the parent channel's button (LFT_ type in Index, filename in Value). Result should be 0 if not handled, 1 if handled and 2 if a dropped file should be rejected
// LFT_DownloadDataPack option is used to download Flex packs: Result is -1 if failed, or Pack index on success
enum int FPD_SetFitTime        =19;    // set fit to time in beats (FLOAT time in value (need to typecast))
enum int FPD_SetSamplesPerTick =20;    // # of samples per tick (changes when tempo, PPQ or sample rate changes) (FLOAT in Value (need to typecast)) (warning: can be called from the mixing thread) (GM)
enum int FPD_SetIdleTime       =21;    // set the freq at which Idle is called (can vary), ms time in Value
enum int FPD_SetFocus          =22;    // the host has focused/unfocused the editor (focused in Value) (plugin can use this to steal keyboard focus ... also see FPD_StealKBFocus)
enum int FPD_Transport         =23;    // special transport messages, from a controller. See GenericTransport.pas for Index. Must return 1 if handled.
enum int FPD_MIDIIn            =24;    // live MIDI input preview, allows the plugin to steal messages (mostly for transport purposes). Must return 1 if handled. Packed message (only note on/off for now) in Value.
enum int FPD_RoutingChanged    =25;    // mixer routing changed, must check FHD_GetInOuts if necessary. See RCV_ constants for the meaning of the Value parameter.
enum int FPD_GetParamInfo      =26;    // retrieves info about a parameter. Param number in Index, see PI_Float for the result
enum int FPD_ProjLoaded        =27;    // called after a project has been loaded, to leave a chance to kill automation (that could be loaded after the plugin is created) if necessary
enum int FPD_WrapperLoadState  =28;    // (private message to the plugin wrapper) load a (VST1, DX) plugin state, pointer in Index, length in Value
enum int FPD_ShowSettings      =29;    // called when the settings button on the titlebar is switched. On/off in Value (1=active). See FPF_WantSettingsBtn
enum int FPD_SetIOLatency      =30;    // input/output latency (Index,Value) of the output, in samples (only for information)
enum int FPD_PreferredNumIO    =32;    // (message from Patcher) retrieves the preferred number (0=default, -1=none) of audio inputs (Index=0), audio outputs (Index=1) or voice outputs (Index=2)
enum int FPD_GetGUIColor       =33;    // retrieves the darkest background color of the GUI (Index=0 for background), for a nicer border around it
enum int FPD_CloseAllWindows   =34;    // hide all windows opened by the plugin (except the plugin editor window)
enum int FPD_RenderWindowBitmap=35;    // used by ZgeViz
enum int FPD_StealKBFocus      =36;    // switch stealing keyboard focus off or on (Value = 0 or 1)
enum int FPD_GetHelpContext    =37;    // for plugins that want to show specific help pages, like Patcher. Return the context as a UTF-8 encoded PAnsiChar as the result. Return 0 or an empty string for the default context.
enum int FPD_RegChanged        =38;    // notify plugin about registration change
enum int FPD_ArrangeWindows    =39;    // arrange subwindows into the workspace (Value = workspace PRect)
enum int FPD_PluginLoaded      =40;    // done opening the plugin - note that SaveRestoreState is called before this!
enum int FPD_ContextInfoChanged=41;    // Index holds the type of information (see CI_ constants), call FHD_GetContextInfo for the new value(s)
enum int FPD_ProjectInfoChanged=42;    // Index holds the value that changed (see GPI_ contants)
enum int FPD_GetDemoPlugins    =43;    // Returns ; delimited list (formatted as "productCode|name") of plugins in demo mode. If Value is 1, it should only list plugins that were saved as a demo.
enum int FPD_UnLockDemoPlugins =44;    // Tells a plugin to recheck demo mode and unlock purchased plugins
enum int FPD_ColorWasPicked = 46; // called after FHD_PickVoiceColor finishes. The new color value (an index, not RGB) is passed in Value.
enum int FPD_IsInDebugMode = 47; // return 0 for no, 1 for yes
enum int FPD_ColorsHaveChanged = 48; // some shared colors have changed. Index indicates the palette (see CP_ constants).
enum int FPD_GetStateSizeEstimate = 49; //get plugin estimated state size
enum int FPD_UseIncreasedMIDIResolution = 50; // return 1 if increased MIDI resolution is supported
enum int FPD_ConvertStringToValue = 51;  //let plugin do string to value conversion, value is pointer to TConvertStringToValueData record , used for custom type in value
enum int FPD_GetParamType = 52; //return control (Index) param type, see //FPD_GetParamType options below

// event ID's
enum int FPE_Tempo             =0;     // FLOAT tempo in value (need to typecast), & average samples per tick in Flags (DWORD) (warning: can be called from the mixing thread) (GM)
enum int FPE_MaxPoly           =1;     // max poly in value (infinite if <=0) (only interesting for standalone generators)
// since MIDI plugins, or other plugin wrappers won't support the voice system, they should be notified about channel pan, vol & pitch changes
enum int FPE_MIDI_Pan          =2;     // MIDI channel panning (0..127) in EventValue, FL panning in -64..+64 in Flags (warning: can be called from the mixing thread) (GM)
enum int FPE_MIDI_Vol          =3;     // MIDI channel volume (0..127) in EventValue + volume as normalized float in Flags (need to typecast) (warning: can be called from the mixing thread) (GM)
enum int FPE_MIDI_Pitch        =4;     // MIDI channel pitch in *cents* (to be translated according to current pitch bend range) in EventValue (warning: can be called from the mixing thread) (GM)

enum int CI_TrackName         = 0;  // (R/W) PAnsiChar encoded as UTF-8
enum int CI_TrackIndex        = 1;  // (R)
enum int CI_TrackColor        = 2;  // (R/W) color is RGBA
enum int CI_TrackSelected     = 3;  // (R/W) the track is selected (0=false 1=true, 2=selected with other tracks)
enum int CI_TrackFocused      = 4;  // (R) the track is focused for user input (0=false 1=true)
enum int CI_TrackIsOutput     = 5;  // (R) the track sends directly to an audio device output (0=false, 1=true)
enum int CI_TrackVolume       = 6;  // (R/W) (float+string) the value of the tracks' volume slider. Info is floating point (single / float) cast to an int32
enum int CI_TrackPan          = 7;  // (R/W) (float+string) the value of the track's panning knob, as a single / float (-1..1) cast to int32
enum int CI_TrackMuteSolo     = 8;  // (R/W) flags indicate mute and solo state for a track (see CIMS_ constants)
enum int CI_TrackSendCount    = 9;  // (R) returns the send count for the plugin's track
enum int CI_TrackSendLevel    = 10; // (R/W) (float+string) get or set the level for a specific send of this track. On read, Value holds the send index. On write, Value holds a pointer to a TContextInfo record with the new value in FloatValue.
enum int CI_TrackMaxVolume    = 11; // (R) get the maximum value for mixer track volume
enum int CI_TrackMaxSendLevel = 12; // (R) get the maximum value for mixer track send level


alias TPluginTag = intptr_t;

// plugin info, common to all instances of the same plugin
struct TFruityPlugInfo
{
align(4):
    int SDKVersion;    // =CurrentSDKVersion
    char* LongName;    // full plugin name (should be the same as DLL name)
    char* ShortName;   // & short version (for labels)
    int Flags;         // see FPF_Generator
    int NumParams;     // (maximum) number of parameters, can be overridden using FHD_SetNumParams
    int DefPoly;       // preferred (default) max polyphony (Fruity manages polyphony) (0=infinite)
    int NumOutCtrls;   // number of internal output controllers
    int NumOutVoices;  // number of internal output voices
    int[30] Reserved;  // set to zero
}

alias PFruityPlugInfo = TFruityPlugInfo*;



alias intptr_t = size_t;
alias TVoiceHandle = intptr_t;
alias TOutVoiceHandle = intptr_t;

// sample handle
alias TSampleHandle = intptr_t;

alias IStream = void*; // TODO
alias BOOL = int;

alias PVoiceParams = void*;
alias PWaveFormatExtensible = void*;
alias PSampleInfo = void*;
alias PSampleRegion = void*;
alias PIOBuffer = void*;


// plugin class, made extern(C++) to have no field and an empty v-table.
extern(C++) class TFruityPlug 
{
public:
nothrow:
@nogc:

    /// free for the host to use (parent object reference, ...), passed as 'Sender' to the host
    TPluginTag HostTag;

    PFruityPlugInfo Info;

    /// handle to the editor window panel (created by the plugin)
    void* EditorHandle;       

    int MonoRender;         // 0 or 1, last rendered voice rendered mono data (not used yet)

    int[32] Reserved;        // for future use, set to zero


    // *** functions ***
    // (G) = called from GUI thread, (M) = called from mixer thread, (GM) = both, (S) = called from MIDI synchronization thread
    // (M) calls are done inside the plugin lock (LockPlugin / UnlockPlugin)
    // + TriggerVoice and Voice_ functions are also called inside the plugin lock
    // + assume that any other call is not locked! (so call LockPlugin / UnlockPlugin where necessary, but no more than that)
    // + don't call back to the host while inside a LockPlugin / UnlockPlugin block

    // messages (to the plugin)
    extern(Windows) abstract
    {
        void DestroyObject();  // (G)
        intptr_t Dispatcher(intptr_t ID, intptr_t Index, intptr_t Value);  // (GM)
        void Idle_Public();  // (G) (used to be Idle())
        void SaveRestoreState(IStream *Stream, BOOL Save);  // (G)

        // names (see FPN_Param) (Name must be at least 256 chars long)
        void GetName(int Section, int Index, int Value, char *Name);  // (GM)

        // events
        int ProcessEvent(int EventID, int EventValue, int Flags);  // (GM)
        int ProcessParam(int Index, int Value, int RECFlags);  // (GM)

        // effect processing (source & dest can be the same)
        void Eff_Render(PWAV32FS SourceBuffer, PWAV32FS DestBuffer, int Length);  // (M)
        // generator processing (can render less than length)
        void Gen_Render(PWAV32FS DestBuffer, ref int Length);  // (M)

        // voice handling
        TVoiceHandle TriggerVoice(PVoiceParams VoiceParams, intptr_t SetTag);  // (GM)
        void Voice_Release(TVoiceHandle Handle);  // (GM)
        void Voice_Kill(TVoiceHandle Handle);  // (GM)
        int Voice_ProcessEvent(TVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags);  // (GM)
        int Voice_Render(TVoiceHandle Handle, PWAV32FS DestBuffer, ref int Length);  // (GM)


        // (see FPF_WantNewTick) called before a new tick is mixed (not played)
        // internal controller plugins should call OnControllerChanged from here
        void NewTick();  // (M)

        // (see FHD_WantMIDITick) called when a tick is being played (not mixed) (not used yet)
        void MIDITick();  // (S)

        // MIDI input message (see FHD_WantMIDIInput & TMIDIOutMsg) (set Msg to MIDIMsg_Null if it has to be killed)
        void MIDIIn(ref int Msg);  // (GM)

        // buffered messages to itself (see PlugMsg_Delayed)
        void MsgIn(intptr_t Msg);  // (S)

        // voice handling
        int OutputVoice_ProcessEvent(TOutVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags);  // (GM)
        void OutputVoice_Kill(TVoiceHandle Handle);  // (GM)
    }
}

extern(C++) class TFruityPlugHost 
{
public:
nothrow:
@nogc:

    alias PWaveT = void*;

    // *** params ***
    int HostVersion;     // current FruityLoops version stored as 01002003 (integer) for 1.2.3
    int Flags;           // reserved

    // windows
    HANDLE AppHandle;    // application handle, for slaving windows

    // handy wavetables (32Bit float (-1..1), 16384 samples each)
    // 6 are currently defined (sine, triangle, square, saw, analog saw, noise)
    // those pointers are fixed
    // (obsolete, avoid)
    PWaveT[10] WaveTables;

    // handy free buffers, guaranteed to be at least the size of the buffer to be rendered (float stereo)
    // those pointers are variable, please read & use while rendering only
    // those buffers are contiguous, so you can see TempBuffer[0] as a huge buffer
    PWAV32FS[4] TempBuffers;

    // reserved for future use
    int[30] Reserved;    // set to zero


    // *** functions ***

    extern(Windows) abstract
    {
        // messages (to the host) (Sender=plugin tag)
        intptr_t Dispatcher(TPluginTag Sender, intptr_t ID, intptr_t Index, intptr_t Value);

        // for the host to store changes
        void OnParamChanged(TPluginTag Sender, int Index, int Value);

        // for the host to display hints (call from GUI thread!)
        void OnHint(TPluginTag Sender, char *Text);

        // compute left & right levels using pan & volume info (OLD, OBSOLETE VERSION, USE ComputeLRVol INSTEAD)
        void ComputeLRVol_Old(ref float LVol, ref float RVol, int Pan, float Volume);

        // voice handling (Sender=voice tag)
        void Voice_Release(intptr_t Sender);
        void Voice_Kill(intptr_t Sender, BOOL KillHandle);
        int Voice_ProcessEvent(intptr_t Sender, intptr_t EventID, intptr_t EventValue, intptr_t Flags);

        // thread synchronisation / safety
        void LockMix_Old();  // will prevent any new voice creation & rendering
        void UnlockMix_Old();


        // delayed MIDI out message (see TMIDIOutMsg) (will be sent once the MIDI tick has reached the current mixer tick
        void MIDIOut_Delayed(TPluginTag Sender, intptr_t Msg);
        // direct MIDI out message
        void MIDIOut(TPluginTag Sender, intptr_t Msg);

        // adds a mono float buffer to a stereo float buffer, with left/right levels & ramping if needed
        // how it works: define 2 float params for each voice: LastLVol & LastRVol. Make them match LVol & RVol before the *first* rendering of that voice (unless ramping will occur from 0 to LVol at the beginning).
        // then, don't touch them anymore, just pass them to the function.
        // the level will ramp from the last ones (LastLVol) to the new ones (LVol) & will adjust LastLVol accordingly
        // LVol & RVol are the result of the ComputeLRVol function
        // for a quick & safe fade out, you can set LVol & RVol to zero, & kill the voice when both LastLVol & LastRVol will reach zero
        void AddWave_32FM_32FS_Ramp(void *SourceBuffer, void *DestBuffer, int Length, float LVol, float RVol, ref float LastLVol, ref float LastRVol);
        // same, but takes a stereo source
        // note that left & right channels are not mixed (not a true panning), but might be later
        void AddWave_32FS_32FS_Ramp(void *SourceBuffer, void *DestBuffer, int Length, float LVol, float RVol, ref float LastLVol, ref float LastRVol);

        // sample loading functions (FruityLoops 3.1.1 & over)
        // load a sample (creates one if necessary)
        // FileName must have room for 256 chars, since it gets written with the file that has been 'located'
        // only 16Bit 44Khz Stereo is supported right now, but fill the format correctly!
        // see FHLS_ShowDialog
        bool LoadSample(ref TSampleHandle Handle, char *FileName, PWaveFormatExtensible NeededFormat, int Flags);
        void * GetSampleData(TSampleHandle Handle, ref int Length);
        void CloseSample(TSampleHandle Handle);

        // time info
        // get the current mixing time, in ticks (integer result)
        // obsolete, use FHD_GetMixingTime & FHD_GetPlaybackTime
        int GetSongMixingTime();
        // get the current mixing time, in ticks (more accurate, with decimals)
        double GetSongMixingTime_A();
        // get the current playing time, in ticks (with decimals)
        double GetSongPlayingTime();

        // internal controller
        void OnControllerChanged(TPluginTag Sender, intptr_t Index, intptr_t Value);

        // get a pointer to one of the send buffers (see FPD_SetNumSends)
        // those pointers are variable, please read & use while processing only
        // the size of those buffers is the same as the size of the rendering buffer requested to be rendered
        void * GetSendBuffer(intptr_t Num);

        // ask for a message to be dispatched to itself when the current mixing tick will be played (to synchronize stuff) (see MsgIn)
        // the message is guaranteed to be dispatched, however it could be sent immediately if it couldn't be buffered (it's only buffered when playing)
        void PlugMsg_Delayed(TPluginTag Sender, intptr_t Msg);
        // remove a buffered message, so that it will never be dispatched
        void PlugMsg_Kill(TPluginTag Sender, intptr_t MSg);

        // get more details about a sample
        void GetSampleInfo(TSampleHandle Handle, PSampleInfo Info);

        // distortion (same as TS404) on a piece of mono or stereo buffer
        // DistType in 0..1, DistThres in 1..10
        void DistWave_32FM(int DistType, int DistThres, void *SourceBuffer, int Length, float DryVol, float WetVol, float Mul);

        // same as GetSendBuffer, but Num is an offset to the mixer track assigned to the generator (Num=0 will then return the current rendering buffer)
        // to be used by generators ONLY, & only while processing
        void *  GetMixBuffer(int Num);

        // get a pointer to the insert (add-only) buffer following the buffer a generator is currently processing in
        // Ofs is the offset to the current buffer, +1 means next insert track, -1 means previous one, 0 is forbidden
        // only valid during Gen_Render
        // protect using LockMix_Shared
        void *  GetInsBuffer(TPluginTag Sender, int Ofs);

        // ask the host to prompt the user for a piece of text (s has room for 256 chars)
        // set x & y to -1 to have the popup screen-centered
        // if 0 is returned, ignore the results
        // set c to -1 if you don't want the user to select a color
        BOOL  PromptEdit(int x, int y, char *SetCaption, char *s, ref int c);

        // deprecated, use SuspendOutput and ResumeOutput instead
        void  SuspendOutput_Old();
        void  ResumeOutput_Old();

        // get the region of a sample
        void  GetSampleRegion(TSampleHandle Handle, int RegionNum, PSampleRegion Region);

        // compute left & right levels using pan & volume info (USE THIS AFTER YOU DEFINED FPF_NewVoiceParams)
        void  ComputeLRVol(ref float LVol, ref float RVol, float Pan, float Volume);

        // use this instead of PlugHost.LockMix
        void  LockPlugin(TPluginTag Sender);
        void  UnlockPlugin(TPluginTag Sender);

        // multithread processing synchronisation / safety
        void  LockMix_Shared_Old();
        void  UnlockMix_Shared_Old();

        // multi-in/output (for generators & effects) (only valid during Gen/Eff_Render)
        // !!! Index starts at 1, to be compatible with GetInsBuffer (Index 0 would be Eff_Render's own buffer)
        void  GetInBuffer(TPluginTag Sender, intptr_t Index, PIOBuffer IBuffer);    // returns (read-only) input buffer Index (or Nil if not available).
        void  GetOutBuffer(TPluginTag Sender, intptr_t Index, PIOBuffer OBuffer);   // returns (add-only) output buffer Index (or Nil if not available). Use LockMix_Shared when adding to this buffer.


        alias TVoiceParams = void;
        // output voices (VFX "voice effects")
        TOutVoiceHandle  TriggerOutputVoice(TVoiceParams *VoiceParams, intptr_t SetIndex, intptr_t SetTag);  // (GM)
        void  OutputVoice_Release(TOutVoiceHandle Handle);  // (GM)
        void  OutputVoice_Kill(TOutVoiceHandle Handle);  // (GM)
        int  OutputVoice_ProcessEvent(TOutVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags);  // (GM)

        // ask the host to prompt the user for a piece of text, color, icon ... See PEO_ constants for SetOptions. Text should be null or a pointer to an allocated buffer with at least 255 characters!
        BOOL  PromptEdit_Ex(int x, int y, const char* SetCaption, char* Text, ref int Color1, ref int Color2, ref int IconIndex, int FontHeight, int SetOptions);

        // SuspendOutput removes the plugin from all processing lists, so Eff/Gen_Render and voice functions will no longer be called.
        // To be used around lengthy operations (instead of straightforward locking)
        void  SuspendOutput(TPluginTag Sender);
        void  ResumeOutput(TPluginTag Sender);
    }
}
