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
alias ULONG = uint;
alias HRESULT = c_long;
deprecated alias ULARGE_INTEGER = ulong;
deprecated alias LARGE_INTEGER = long;

// plugin flags
enum int FPF_Generator         = 1;        // plugin is a generator (not effect)
enum int FPF_RenderVoice       = 1 << 1;   // generator will render voices separately (Voice_Render) (not used yet)
enum int FPF_UseSampler        = 1 << 2;   // 'hybrid' generator that will stream voices into the host sampler (Voice_Render)
enum int FPF_GetChanCustomShape= 1 << 3;   // generator will use the extra shape sample loaded in its parent channel (see FPD_ChanSampleChanged)
enum int FPF_GetNoteInput      = 1 << 4;   // plugin accepts note events (not used yet, but effects might also get note input later)(EDIT: was implemented apparently)
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

// host dispatcher IDs
enum int FHD_ParamMenu         =0;     // the popup menu for each control (Index=param index, Value=popup item index (see FHP_EditEvents))
enum int FHD_GetParamMenuFlags =1;     // [OBSOLETE, see FHD_GetParamMenuEntry] before the popup menu is shown, you must ask the host to tell if items are checked or disabled (Index=param index, Value=popup item index, Result=flags (see FHP_Disabled))
enum int FHD_EditorResized     =2;     // to notify the host that the editor (EditorHandle) has been resized
enum int FHD_NamesChanged      =3;     // to notify the host that names (GetName function) have changed, with the type of names in Value (see the FPN_ constants)
enum int FHD_ActivateMIDI      =4;     // makes the host enable its MIDI output, useful when a MIDI out plugin is created (but not useful for plugin wrappers)
enum int FHD_WantMIDIInput     =5;     // plugin wants to be notified about MIDI messages (for processing or filtering) (switch in Value)
enum int FHD_WantMIDITick      =6;     // plugin wants to receive MIDITick events, allowing MIDI out plugins (not used yet)
enum int FHD_LocatePlugin      =7;     // ask the host to find a plugin, pass the simple filename in Value, full path is returned as Result (both PAnsiChar). Set Index to 1 if you want host to show a warning if plugin could not be found.
enum int FHD_KillAutomation    =8;     // ask the host to kill the automation linked to the plugin, for params # between Index & Value (included) (can be used for a trial version of the plugin)
enum int FHD_SetNumPresets     =9;     // tell the host how many (Value) internal presets the plugin supports (mainly for wrapper)
enum int FHD_SetNewName        =10;    // sets a new short name for the parent (PChar in Value)
enum int FHD_VSTiIdle          =11;    // used by the VSTi wrapper, because the dumb VSTGUI needs idling for his knobs
enum int FHD_SelectChanSample  =12;    // ask the parent to open a selector for its channel sample (see FPF_UseChanSample)
enum int FHD_WantIdle          =13;    // plugin wants to receive the idle message (enabled by default) (Value=0 for disabled, 1 for enabled when UI is visible, 2 for always enabled)
enum int FHD_LocateDataFile    =14;    // ask the host to search for a file in its search paths, pass the simple filename in Value, full path is returned as Result (both PChar) (Result doesn't live long, please copy it asap)
enum int FHD_ShowPlugSelector  =15;    // ask the host to show the plugin selector (Index: see SPSF flags)
enum int FHD_TicksToTime       =16;    // translate tick time (Value) into Bar:Step:Tick (PSongTime in Index) (warning: it's *not* Bar:Beat:Tick)
enum int FHD_AddNotesToPR      =17;    // add a note to the piano roll, PNotesParams in Value
enum int FHD_GetParamMenuEntry =18;    // before the popup menu is shown, you must fill it with the entries set by the host (Index=param index, Value=popup item index (starting from 0), Result=PParamMenuEntry, or null pointer if no more entry)
enum int FHD_MsgBox            =19;    // make fruity show a message box (PChar in Index [formatted as 'Title|Message'], flags in Value (MB_OkCancel, MB_IconWarning, etc.), result in IDOk, IDCancel format (as in TApplication.MessageBox)
enum int FHD_NoteOn            =20;    // preview note on (semitone in Index low word, color in index high word (0=default), velocity in Value)
enum int FHD_NoteOff           =21;    // preview note off (semitone in Index, color in index high word, velocity in Value (-1=default otherwise 0..127))
enum int FHD_OnHint_Direct     =22;    // same as OnHint, but show it immediately (to show a progress while you're doing something) (PChar in Value)
enum int FHD_SetNewColor       =23;    // sets a new color for the parent (color in Value) (see FHD_SetNewName);
enum int FHD_GetInstance       =24;    // (Windows) returns the module instance of the host (could be an exe or a DLL, so not the process itself)
enum int FHD_KillIntCtrl       =25;    // ask the host to kill anything linked to an internal controller, for # between Index & Value (included) (used when undeclaring internal controllers)
enum int FHD_CheckProdCode     =26;    // reserved
enum int FHD_SetNumParams      =27;    // override the # of parameters (for plugins that have a different set of parameters per instance) (number of parameters in Value)
enum int FHD_PackDataFile      =28;    // ask the host to pack an absolute filename into a local filemane, pass the simple filename in Value, packed path is returned as Result (both PChar) (Result doesn't live long, please copy it asap)
enum int FHD_GetPath           =29;    // ask the host for a path specified by Index (see GP_ constants) (returned as Result)
enum int FHD_SetLatency        =30;    // set plugin latency, if any (samples in Value)
enum int FHD_CallDownloader    =31;    // call the presets downloader (optional plugin name PAnsiChar in Value)
enum int FHD_EditSample		=32;	// edits sample in Edison (PChar in Value, Index=1 means an existing Edison can be re-used)
enum int FHD_SetThreadSafe     =33;    // plugin is thread-safe, doing its own thread-sync using LockMix_Shared (switch in Value)
enum int FHD_SmartDisable      =34;    // plugin asks FL to exit or enter smart disabling (if currently active), mainly for generators when they get MIDI input (switch in Value)
enum int FHD_SetUID            =35;    // sets a unique identifying string for this plugin. This will be used to save/restore custom data related to this plugin. Handy for wrapper plugins. (PChar in Value)
enum int FHD_GetMixingTime     =36;    // get mixer time, Index is the time format required (see GT_... constants). Value is a pointer to a TFPTime, which is filled with an optional offset in samples
enum int FHD_GetPlaybackTime   =37;    // get playback time, same as above
enum int FHD_GetSelTime        =38;    // get selection time in t & t2, same as above. Returns 0 if no selection (t & t2 are then filled with full song length).
enum int FHD_GetTimeMul        =39;    // get current tempo multiplicator, that's not part of the song but used for fast-forward
enum int FHD_Captionize        =40;    // captionize the plugin (useful when dragging) (captionized in Value)
enum int FHD_SendSysEx         =41;    // send a SysEx string (pointer to array in Value, the first integer being the length of the string, the rest being the string), through port Index, immediately (do not abuse)
enum int FHD_LoadAudioClip     =42;    // send an audio file to the playlist as an audio clip, starting at the playlist selection. Options in Index (see LAC_ constants). FileName as PAnsiChar in Value.
enum int FHD_LoadInChannel     =43;    // send a file to the selected channel(s) (mainly for Edison), FileName as PChar in Value
enum int FHD_ShowInBrowser     =44;    // locates the file in the browser & jumps to it (Index is one of SIB_ constants, PAnsiChar filename in Value)
enum int FHD_DebugLogMsg       =45;    // adds message to the debug log (PChar in Value)
enum int FHD_GetMainFormHandle =46;    // gets the handle of the main form (HWND in Value, 0 if none)
enum int FHD_GetProjDataPath   =47;    // [OBSOLETE - use FHD_GetPath instead] ask the host where the project data is, to store project data (returned as Result)
enum int FHD_SetDirty          =48;    // mark project as dirty (not required for automatable parameters, only for tweaks the host can't be aware of)
enum int FHD_AddToRecent       =49;    // add file to recent files (PChar in Value)
enum int FHD_GetNumInOut       =50;    // ask the host how many inputs (Index=0) are routed to this effect (see GetInBuffer), or how many outputs (Index=1) this effect is routed to (see GetOutBuffer)
enum int FHD_GetInName         =51;    // ask the host the name of the input Index (!!! first = 1), in Value as a PNameColor, Result=0 if failed (Index out of range)
enum int FHD_GetOutName        =52;    // ask the host the name of the ouput Index (!!! first = 1), in Value as a PNameColor, Result=0 if failed (Index out of range)
enum int FHD_ShowEditor        =53;    // make host bring plugin's editor (visibility in Value, -1 to toggle)
enum int FHD_FloatAutomation   = 54;   // (for the plugin wrapper only) ask the host to turn 0..FromMIDI_Max automation into 0..1 float, for params # between Index & Value (included)
enum int FHD_ShowSettings      =55;    // called when the settings button on the titlebar should be updated switched. On/off in Value (1=active). See FPF_WantSettingsBtn
enum int FHD_NoteOnOff         =56;    // generators only! note on/off (semitone in Index low word, color in index high word, NOT recorded in bit 30, velocity in Value (<=0 = note off))
enum int FHD_ShowPicker        =57;    // show picker (mode [0=plugins, 1=project] in Index, categories [gen=0/FX=1/both=-1/Patcher (includes VFX)=-2] in Value)
enum int FHD_GetIdleOverflow   =58;    // ask the host for the # of extra frames Idle should process, generally 0 if no overflow/frameskip occured
enum int FHD_ModalIdle         =59;    // used by FL plugins, when idling from a modal window, mainly for the smoothness hack
enum int FHD_RenderProject     =60;    // prompt the rendering dialog in song mode
enum int FHD_GetProjectInfo    =61;    // get project title, author, comments, URL, naked filename (Index), (returned as Result as a *PWideChar*)
enum int FHD_ForceDetached     =62;    // used by Wrapper in OSX to force the plugin form to be detached
enum int FHD_StartDrag         =63;    // sent by Patcher when starting dragging a preset
enum int FHD_EndDrag           =64;    // sent by Patcher when finished dragging a preset
enum int FHD_PreviewKey        =65;    // chance for host to handle keyboard messages, Index=flags in lower 16 bits (see KUD constants) and virtual key in second 16 bits, Value=KeyData from WM_KeyUp or WM_KeyDown message (0 if not available), returns 1 if handled and 0 if not
enum int FHD_RenderWindowBitmap=66;    // used by ZgeViz
enum int FHD_UpdateStealKBFocus=67;    // the plugin will steal kb input or not (Value is 1 or 0)
//=68;    // [OBSOLETE]
enum int FHD_GetPluginMenuMode =69;    // returns the view mode of the favorite plugin menus in FL: 0=categories 1=tree 2=flat
enum int FHD_OpenTool          =70;    // open application in System\Tools folder. Index=tool to start (see OTI_ControlCreator), Value=PAnsiChar with command line params
enum int FHD_GetPathManager	=71;	// returns IPathManager instance (pointer)
enum int FHD_RegisterSideInput =72;	// let the host know that you intend to use a sidechained input, so latency can be calculated. Index=input index (first=1), Value=see RSIO_ constants
enum int FHD_RegisterSideOutput=73;	// let the host know that you intend to use a sidechained output, so latency can be calculated. Index=output index (depends on use of GetInsBuffer or GetOutBuffer), Value=see RSIO_ constants

enum int FHD_ReportError		=74; 	// report error during plugin load (will show combined dialog for all missing plugins after project is loaded or MsgBox in case we are adding plugin to project)
enum int FHD_ShowStandardParamMenu=75; // ask FL to pop up a parameter menu, so the plugin doesn't have to implement it itself. Index is the parameter index.
enum int FHD_GetContextInfo	=76; 	// get information about various things. Index is the information type (see CI_ constants), Value and result depend on the type
enum int FHD_SetContextInfo	=77; 	// change some piece of context information. Index is the information type (see CI_ constants), Value and result depend on the type
enum int FHD_GetExternalMedia	=78;    // set Flags (bits) as index, for example : EMD_SearchImages or EMD_DownloadFile to search and download images
enum int FHD_Transport         =79;    // allows the plugin to control FL through some of the messages in GenericTransport. Index=message, Value=release/switch/hold value. Currently only FPT_Play and FPT_Stop are supported. Returns -1 if can't be handled, 0 if not handled, 1 if handled by focused plugin, 2 if handled by focused form, 4 if handled by menu, 5 if delayed, 8 if handled globally.
enum int FHD_DownloadMissing   =80;    // notify FL about missing data pack
enum int FHD_DownloadFinished  =81;    // notify FL that a pack download is finished
enum int FHD_DebugBuild        =82;    // tell FL to show a [DEBUG] warning in the plugin window caption. Value is 0 (release) or 1 (debug)
enum int FHD_PickVoiceColor    =83;    // Show the piano roll's color picker. Index = screen co-ordinates with x in first 2 bytes and y in next 2 bytes, Value = current color number (not an RGB value). Will call FPD_ColorWasPicked when the user selects a color.
enum int FHD_GetColorRGBValue  =84;    // Get the RGB value for a color in a palette. Index is the color palette (see CP_ constants for available palettes). Value is the index in the palette. If Value is -1, this returns the count of colors in the palette.
enum int FHD_ShowException     =85;    // Show application exception. Index is Exception.Message string. Value is Stack-trace string.
enum int FHD_GetTranslationMoFile =86; // Get the current translation object (for Plugins)
enum int FHD_PresetSelected    =87;    // tell the host internal preset is changed


enum int FPN_Param             =0;     // retrieve name of param Index
enum int FPN_ParamValue        =1;     // retrieve text label of param Index for value Value (used in event editor)
enum int FPN_Semitone          =2;     // retrieve name of note Index (used in piano roll), for color (=MIDI channel) Value
enum int FPN_Patch             =3;     // retrieve name of patch Index (not used yet)
enum int FPN_VoiceLevel        =4;     // retrieve name of per-voice param Index (default is filter cutoff (0) & resonance (1)) (optional)
enum int FPN_VoiceLevelHint    =5;     // longer description for per-voice param (works like FPN_VoiceLevels)
enum int FPN_Preset            =6;     // for plugins that support internal presets (mainly for the wrapper plugin), retrieve the name for program Index
enum int FPN_OutCtrl           =7;     // for plugins that output controllers, retrieve the name of output controller Index
enum int FPN_VoiceColor        =8;     // retrieve name of per-voice color (MIDI channel) Index
enum int FPN_OutVoice          =9;     // for plugins that output voices, retrieve the name of output voice Index




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

// Same as Delphi type.
struct TPoint
{
    int x, y;
}

// Same as Delphi type.
struct TRect
{
    int x1, y1;
    int x2, y2;
}

alias PFruityPlugInfo = TFruityPlugInfo*;



alias intptr_t = size_t;
alias TVoiceHandle = intptr_t;
alias TOutVoiceHandle = intptr_t;

// sample handle
alias TSampleHandle = intptr_t;

extern(C++) class IStream 
{
public:
nothrow:
@nogc:
    extern(System) abstract
    {
        void QueryInterface();
        ULONG AddRef();
        ULONG Release();
        HRESULT Read(void *pv, ULONG cb, ULONG *pcbRead);
        HRESULT Write(const void *pv, ULONG cb, ULONG *pcbWritten);

        // There are more methods, but not useful for us
    }
}


alias BOOL = int;

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
    extern(System) abstract
    {
        void DestroyObject();  // (G)
        intptr_t Dispatcher(intptr_t ID, intptr_t Index, intptr_t Value);  // (GM)
        void Idle_Public();  // (G) (used to be Idle())
        void SaveRestoreState(IStream Stream, BOOL Save);  // (G)

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
        TVoiceHandle TriggerVoice(TVoiceParams* VoiceParams, intptr_t SetTag);  // (GM)
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

    extern(System) abstract
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

// NEW VERSION (all floats), USE THESE
struct TLevelParams 
{
    float Pan;    // panning (-1..1)
    float Vol;    // volume/velocity (0.0 = -inf dB .. 1.0 = 0 dB) - note: can go above 1.0!
    float Pitch;  // pitch (in cents) (semitone=Pitch/100)
    float FCut;   // filter cutoff (0..1)
    float FRes;   // filter Q (0..1)
}

struct TVoiceParams
{
    TLevelParams InitLevels;
    TLevelParams FinalLevels;
}

struct TFPTime
{
    double t, t2;
}