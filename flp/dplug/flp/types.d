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
deprecated alias HANDLE = void*;
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

}
