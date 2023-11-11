/**
FL Plugin interface.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flp.types;

nothrow @nogc:

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

/+

#ifdef __APPLE__
#define _stdcall __stdcall
#define BOOL int
#define HINSTANCE intptr_t
#define HMENU intptr_t
#define DWORD unsigned int
#define HWND intptr_t
#define HANDLE intptr_t
#define NULL 0
#define MAX_PATH 256
#define RTL_CRITICAL_SECTION intptr_t
typedef unsigned long ULONG;
typedef long HRESULT;
typedef unsigned long long ULARGE_INTEGER;
typedef long long LARGE_INTEGER;
#endif
+/

// plugin flags
const int FPF_Generator         =1;        // plugin is a generator (not effect)
const int FPF_RenderVoice       =1 << 1;   // generator will render voices separately (Voice_Render) (not used yet)
const int FPF_UseSampler        =1 << 2;   // 'hybrid' generator that will stream voices into the host sampler (Voice_Render)
const int FPF_GetChanCustomShape=1 << 3;   // generator will use the extra shape sample loaded in its parent channel (see FPD_ChanSampleChanged)
const int FPF_GetNoteInput      =1 << 4;   // plugin accepts note events (not used yet, but effects might also get note input later)
const int FPF_WantNewTick       =1 << 5;   // plugin will be notified before each mixed tick (& be able to control params (like a built-in MIDI controller) (see NewTick))
const int FPF_NoProcess         =1 << 6;   // plugin won't process buffers at all (FPF_WantNewTick, or special visual plugins (Fruity NoteBook))
const int FPF_NoWindow          =1 << 10;  // plugin will show in the channel settings window & not in its own floating window
const int FPF_Interfaceless     =1 << 11;  // plugin doesn't provide its own interface (not used yet)
const int FPF_TimeWarp          =1 << 13;  // supports timewarps, that is, can be told to change the playing position in a voice (direct from disk music tracks, ...) (not used yet)
const int FPF_MIDIOut           =1 << 14;  // plugin will send MIDI out messages (only those will be enabled when rendering to a MIDI file)
const int FPF_DemoVersion       =1 << 15;  // plugin is a trial version, & the host won't save its automation
const int FPF_CanSend           =1 << 16;  // plugin has access to the send tracks, so it can't be dropped into a send track or into the master
const int FPF_MsgOut            =1 << 17;  // plugin will send delayed messages to itself (will require the internal sync clock to be enabled)
const int FPF_HybridCanRelease  =1 << 18;  // plugin is a hybrid generator & can release its envelope by itself. If the host's volume envelope is disabled, then the sound will keep going when the voice is stopped, until the plugin has finished its own release
const int FPF_GetChanSample     =1 << 19;  // generator will use the sample loaded in its parent channel (see FPD_ChanSampleChanged)
const int FPF_WantFitTime       =1 << 20;  // fit to time selector will appear in channel settings window (see FPD_SetFitTime)
const int FPF_NewVoiceParams    =1 << 21;  // MUST BE USED - tell the host to use TVoiceParams instead of TVoiceParams_Old
const int FPF_Reserved1         =1 << 22;  // don't use (Delphi version specific)
const int FPF_CantSmartDisable  =1 << 23;  // plugin can't be smart disabled
const int FPF_WantSettingsBtn   =1 << 24;  // plugin wants a settings button on the titlebar (mainly for the wrapper)
const int FPF_CanStealKBFocus   =1 << 25;  // plugin can steal keyboard focus away from FL
const int FPF_VFX               =1 << 26;  // is VFX plugin
const int FPF_MacNeedsNSView 	=1 << 27;  // On Mac: This plugin requires a NSView parent

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
