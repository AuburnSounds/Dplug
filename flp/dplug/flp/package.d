module dplug.flp;

// Fruity Loops Plug-in format.

version(FLP):

import dplug.core.nogc;

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

alias TPluginTag = intptr_t;
alias PFruityPlugInfo = void*; // TODO
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

alias TFruityPlugHost = void*; // TODO

/+
extern(C++) class TFruityHost 
{
public:
nothrow:
@nogc:




}+/

 
// In reality a FLP export those 4 functions
//
// 4    0 001ECF08 CreatePlugInstance
// 3    1 00054BF8 TMethodImplementationIntercept >= those 3 added by Delphi for some Delphi runtime RTTI reason, probably not useful
// 2    2 0000E104 __dbk_fcall_wrapper
// 1    3 002095AC dbkFCallWrapperAddr



/**
* Main entry point for LV2 plugins.
*/
// Note: it's supposed to be stdcall in Delphi, however
template FLPEntryPoint(alias ClientClass)
{
    static immutable enum create_plugin_instance =
        "export extern(Windows) void* CreatePlugInstance(void* Host, TPluginTag Tag) nothrow @nogc" ~
        "{" ~
        "    return CreatePlugInstance_templated!" ~ ClientClass.stringof ~ "(Host, Tag);" ~
        "}\n" ~
/+ Delphi RTTI functions, very likely unneeded
        "export extern(C) void* TMethodImplementationIntercept() nothrow @nogc" ~
        "{" ~
        "    import dplug.core;" ~
        "    debugLog(\"TMethodImplementationIntercept\n\");" ~
        "    return null;" ~
        "}\n" ~

        "export extern(C) void* __dbk_fcall_wrapper() nothrow @nogc" ~
        "{" ~
        "    import dplug.core;" ~
        "    debugLog(\"__dbk_fcall_wrapper\n\");" ~
        "    return null;" ~
        "}\n" ~

        "export extern(C) void* dbkFCallWrapperAddr() nothrow @nogc" ~        
        "{" ~
        "    import dplug.core;" ~
        "    debugLog(\"dbkFCallWrapperAddr\n\");" ~
        "    return null;" ~ +/
     //   "}\n" ~ +/
        "";

    const char[] FLPEntryPoint = create_plugin_instance;
}

void* CreatePlugInstance_templated(ClientClass)(void* Host, TPluginTag Tag)
{
  //  TFruityPlugHost pHost = cast(TFruityPlugHost)Host;
    debugLog("Instanced!!!\n");
    return null;    
}
