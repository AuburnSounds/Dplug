/**
Dynamic bindings to the AudioUnit and AudioToolbox frameworks.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.carbon.audiounit;

// AudioUnit and AudioToolbox frameworks loader
// Not strictly in Carbon, this is technical debt

import core.stdc.config;

import dplug.core.sharedlib;
import dplug.core.nogc;
import derelict.carbon.corefoundation;
import derelict.carbon.coreaudio;
import derelict.carbon.coreservices;

version(OSX)
    enum libNames = "/System/Library/Frameworks/AudioUnit.framework/AudioUnit";
else
    enum libNames = "";


class DerelictAudioUnitLoader : SharedLibLoader
{
    public
    {
        this() nothrow @nogc
        {
            super(libNames);
        }

        override void loadSymbols() nothrow @nogc
        {
            bindFunc(cast(void**)&AudioUnitGetProperty, "AudioUnitGetProperty");
            bindFunc(cast(void**)&AudioUnitRender, "AudioUnitRender");
        }
    }
}


private __gshared DerelictAudioUnitLoader DerelictAudioUnit;

private __gshared loaderCounterAU = 0;

// Call this each time a novel owner uses these functions
// TODO: hold a mutex, because this isn't thread-safe
void acquireAudioUnitFunctions() nothrow @nogc
{
    if (DerelictAudioUnit is null)  // You only live once
    {
        DerelictAudioUnit = mallocNew!DerelictAudioUnitLoader();
        DerelictAudioUnit.load();
    }
}

// Call this each time a novel owner releases a Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
void releaseAudioUnitFunctions() nothrow @nogc
{
    /*if (--loaderCounterAU == 0)
    {
        DerelictAudioUnit.unload();
        DerelictAudioUnit.destroyFree();
    }*/
}


unittest
{
    version(OSX)
    {
        acquireAudioUnitFunctions();
        releaseAudioUnitFunctions();
    }
}


enum : int
{
    kAudioUnitRange                                    = 0x0000,
    kAudioUnitInitializeSelect                         = 0x0001,
    kAudioUnitUninitializeSelect                       = 0x0002,
    kAudioUnitGetPropertyInfoSelect                    = 0x0003,
    kAudioUnitGetPropertySelect                        = 0x0004,
    kAudioUnitSetPropertySelect                        = 0x0005,
    kAudioUnitAddPropertyListenerSelect                = 0x000A,
    kAudioUnitRemovePropertyListenerSelect             = 0x000B,
    kAudioUnitRemovePropertyListenerWithUserDataSelect = 0x0012,
    kAudioUnitAddRenderNotifySelect                    = 0x000F,
    kAudioUnitRemoveRenderNotifySelect                 = 0x0010,
    kAudioUnitGetParameterSelect                       = 0x0006,
    kAudioUnitSetParameterSelect                       = 0x0007,
    kAudioUnitScheduleParametersSelect                 = 0x0011,
    kAudioUnitRenderSelect                             = 0x000E,
    kAudioUnitResetSelect                              = 0x0009,
    kAudioUnitComplexRenderSelect                      = 0x0013,
    kAudioUnitProcessSelect                            = 0x0014,
    kAudioUnitProcessMultipleSelect                    = 0x0015
}

// AUComponent.h

alias AudioComponentInstance = void*;
alias AudioUnit = AudioComponentInstance;

alias AudioUnitPropertyID = uint;
alias AudioUnitScope = uint;
alias AudioUnitElement = uint;
alias AudioUnitParameterID = uint;
alias AudioUnitParameterValue = float;

extern(C) nothrow @nogc
{
    alias AURenderCallback = OSStatus function(void *                          inRefCon,
                                               AudioUnitRenderActionFlags *    ioActionFlags,
                                               const(AudioTimeStamp)*          inTimeStamp,
                                               UInt32                          inBusNumber,
                                               UInt32                          inNumberFrames,
                                               AudioBufferList *               ioData);

    alias AudioUnitPropertyListenerProc = void function(void *              inRefCon,
                                                        AudioUnit           inUnit,
                                                        AudioUnitPropertyID inID,
                                                        AudioUnitScope      inScope,
                                                        AudioUnitElement    inElement);
}

alias AudioUnitRenderActionFlags = uint;
enum : AudioUnitRenderActionFlags
{
    kAudioUnitRenderAction_PreRender            = (1 << 2),
    kAudioUnitRenderAction_PostRender           = (1 << 3),
    kAudioUnitRenderAction_OutputIsSilence      = (1 << 4),
    kAudioOfflineUnitRenderAction_Preflight     = (1 << 5),
    kAudioOfflineUnitRenderAction_Render        = (1 << 6),
    kAudioOfflineUnitRenderAction_Complete      = (1 << 7),
    kAudioUnitRenderAction_PostRenderError      = (1 << 8),
    kAudioUnitRenderAction_DoNotCheckRenderArgs = (1 << 9)
}

enum : OSStatus
{
    kAudioUnitErr_InvalidProperty           = -10879,
    kAudioUnitErr_InvalidParameter          = -10878,
    kAudioUnitErr_InvalidElement            = -10877,
    kAudioUnitErr_NoConnection              = -10876,
    kAudioUnitErr_FailedInitialization      = -10875,
    kAudioUnitErr_TooManyFramesToProcess    = -10874,
    kAudioUnitErr_InvalidFile               = -10871,
    kAudioUnitErr_UnknownFileType           = -10870,
    kAudioUnitErr_FileNotSpecified          = -10869,
    kAudioUnitErr_FormatNotSupported        = -10868,
    kAudioUnitErr_Uninitialized             = -10867,
    kAudioUnitErr_InvalidScope              = -10866,
    kAudioUnitErr_PropertyNotWritable       = -10865,
    kAudioUnitErr_CannotDoInCurrentContext  = -10863,
    kAudioUnitErr_InvalidPropertyValue      = -10851,
    kAudioUnitErr_PropertyNotInUse          = -10850,
    kAudioUnitErr_Initialized               = -10849,
    kAudioUnitErr_InvalidOfflineRender      = -10848,
    kAudioUnitErr_Unauthorized              = -10847,
    kAudioComponentErr_InstanceInvalidated  = -66749,
}

alias AUParameterEventType = uint;

enum : AUParameterEventType
{
    kParameterEvent_Immediate   = 1,
    kParameterEvent_Ramped      = 2
}

struct AudioUnitParameterEvent
{
    AudioUnitScope          scope_;
    AudioUnitElement        element;
    AudioUnitParameterID    parameter;

    AUParameterEventType    eventType;

    static union EventValues
    {
        static struct Ramp
        {
            SInt32                      startBufferOffset;
            UInt32                      durationInFrames;
            AudioUnitParameterValue     startValue;
            AudioUnitParameterValue     endValue;
        }                   ;
        Ramp ramp;

        static struct Immediate
        {
            UInt32                      bufferOffset;
            AudioUnitParameterValue     value;
        }
        Immediate immediate;

    }
    EventValues eventValues;
}

struct AudioUnitParameter
{
    AudioUnit               mAudioUnit;
    AudioUnitParameterID    mParameterID;
    AudioUnitScope          mScope;
    AudioUnitElement        mElement;
}

struct AudioUnitProperty
{
    AudioUnit               mAudioUnit;
    AudioUnitPropertyID     mPropertyID;
    AudioUnitScope          mScope;
    AudioUnitElement        mElement;
}

extern(C) nothrow @nogc
{
    alias AudioUnitGetParameterProc = OSStatus function(
                                void *                      inComponentStorage,
                                AudioUnitParameterID        inID,
                                AudioUnitScope              inScope,
                                AudioUnitElement            inElement,
                                AudioUnitParameterValue *   outValue);

    alias AudioUnitSetParameterProc = OSStatus function(
                                void *                      inComponentStorage,
                                AudioUnitParameterID        inID,
                                AudioUnitScope              inScope,
                                AudioUnitElement            inElement,
                                AudioUnitParameterValue     inValue,
                                UInt32                      inBufferOffsetInFrames);

    alias AudioUnitRenderProc = OSStatus function(
                                void *                          inComponentStorage,
                                AudioUnitRenderActionFlags *    ioActionFlags,
                                const(AudioTimeStamp)*          inTimeStamp,
                                UInt32                          inOutputBusNumber,
                                UInt32                          inNumberFrames,
                                AudioBufferList *               ioData);
}

__gshared
{
    AudioUnitRenderProc AudioUnitRender;
}

extern(C) nothrow @nogc
{
    alias AudioUnitGetPropertyProc = OSStatus function(
                                    AudioUnit               inUnit,
                                    AudioUnitPropertyID     inID,
                                    AudioUnitScope          inScope,
                                    AudioUnitElement        inElement,
                                    void *                  outData,
                                    UInt32 *                ioDataSize);
}

__gshared
{
    AudioUnitGetPropertyProc AudioUnitGetProperty;
}

// AudioUnitCarbonView.h

enum
{
    kAudioUnitCarbonViewRange                  = 0x0300,
    kAudioUnitCarbonViewCreateSelect           = 0x0301,
    kAudioUnitCarbonViewSetEventListenerSelect = 0x0302
}

enum
{
    kAudioUnitCarbonViewComponentType   = CCONST('a', 'u', 'v', 'w'),
    kAUCarbonViewSubType_Generic        = CCONST('g', 'n', 'r', 'c')
}

// AudioUnitProperties.h

enum : AudioUnitScope
{
    kAudioUnitScope_Global      = 0,
    kAudioUnitScope_Input       = 1,
    kAudioUnitScope_Output      = 2,
    kAudioUnitScope_Group       = 3,
    kAudioUnitScope_Part        = 4,
    kAudioUnitScope_Note        = 5,
    kAudioUnitScope_Layer       = 6,
    kAudioUnitScope_LayerItem   = 7
}

enum : AudioUnitPropertyID
{
    kAudioUnitProperty_ClassInfo                    = 0,
    kAudioUnitProperty_MakeConnection               = 1,
    kAudioUnitProperty_SampleRate                   = 2,
    kAudioUnitProperty_ParameterList                = 3,
    kAudioUnitProperty_ParameterInfo                = 4,
    kAudioUnitProperty_FastDispatch                 = 5,
    kAudioUnitProperty_CPULoad                      = 6,
    kAudioUnitProperty_StreamFormat                 = 8,
    kAudioUnitProperty_ElementCount                 = 11,
    kAudioUnitProperty_Latency                      = 12,
    kAudioUnitProperty_SupportedNumChannels         = 13,
    kAudioUnitProperty_MaximumFramesPerSlice        = 14,
    kAudioUnitProperty_ParameterValueStrings        = 16,
    kAudioUnitProperty_AudioChannelLayout           = 19,
    kAudioUnitProperty_TailTime                     = 20,
    kAudioUnitProperty_BypassEffect                 = 21,
    kAudioUnitProperty_LastRenderError              = 22,
    kAudioUnitProperty_SetRenderCallback            = 23,
    kAudioUnitProperty_FactoryPresets               = 24,
    kAudioUnitProperty_RenderQuality                = 26,
    kAudioUnitProperty_HostCallbacks                = 27,
    kAudioUnitProperty_InPlaceProcessing            = 29,
    kAudioUnitProperty_ElementName                  = 30,
    kAudioUnitProperty_SupportedChannelLayoutTags   = 32,
    kAudioUnitProperty_PresentPreset                = 36,
    kAudioUnitProperty_DependentParameters          = 45,
    kAudioUnitProperty_InputSamplesInOutput         = 49,
    kAudioUnitProperty_ShouldAllocateBuffer         = 51,
    kAudioUnitProperty_FrequencyResponse            = 52,
    kAudioUnitProperty_ParameterHistoryInfo         = 53,
    kAudioUnitProperty_NickName                     = 54,
    kAudioUnitProperty_OfflineRender                = 37,
    kAudioUnitProperty_ParameterIDName              = 34,
    kAudioUnitProperty_ParameterStringFromValue     = 33,
    kAudioUnitProperty_ParameterClumpName           = 35,
    kAudioUnitProperty_ParameterValueFromString     = 38,
    kAudioUnitProperty_ContextName                  = 25,
    kAudioUnitProperty_PresentationLatency          = 40,
    kAudioUnitProperty_ClassInfoFromDocument        = 50,
    kAudioUnitProperty_RequestViewController        = 56,
    kAudioUnitProperty_ParametersForOverview        = 57,
    kAudioUnitProperty_SetExternalBuffer            = 15,
    kAudioUnitProperty_GetUIComponentList           = 18,
    kAudioUnitProperty_CocoaUI                      = 31,
    kAudioUnitProperty_IconLocation                 = 39,
    kAudioUnitProperty_AUHostIdentifier             = 46,
    kAudioUnitProperty_MIDIOutputCallbackInfo       = 47,
    kAudioUnitProperty_MIDIOutputCallback           = 48,
}

enum : AudioUnitPropertyID
{
    kMusicDeviceProperty_InstrumentCount            = 1000,
    kMusicDeviceProperty_BankName                   = 1007,
    kMusicDeviceProperty_SoundBankURL               = 1100
}

static immutable string
    kAUPresetVersionKey       = "version",
    kAUPresetTypeKey          = "type",
    kAUPresetSubtypeKey       = "subtype",
    kAUPresetManufacturerKey  = "manufacturer",
    kAUPresetDataKey          = "data",
    kAUPresetNameKey          = "name",
    kAUPresetRenderQualityKey = "render-quality",
    kAUPresetCPULoadKey       = "cpu-load",
    kAUPresetElementNameKey   = "element-name",
    kAUPresetExternalFileRefs = "file-references",
    kAUPresetVSTDataKey       = "vstdata",
    kAUPresetVSTPresetKey     = "vstpreset",
    kAUPresetMASDataKey       = "masdata",
    kAUPresetPartKey          = "part";

version(BigEndian)
    struct AUNumVersion
    {
        UInt8               majorRev;
        UInt8               minorAndBugRev;
        UInt8               stage;
        UInt8               nonRelRev;
    }

version(LittleEndian)
    struct AUNumVersion
    {
        UInt8               nonRelRev;
        UInt8               stage;
        UInt8               minorAndBugRev;
        UInt8               majorRev;
    }

struct AUHostIdentifier
{
    CFStringRef         hostName;
    AUNumVersion        hostVersion;
}

struct AudioUnitConnection
{
    AudioUnit   sourceAudioUnit;
    UInt32      sourceOutputNumber;
    UInt32      destInputNumber;
}

struct AUChannelInfo
{
    SInt16      inChannels;
    SInt16      outChannels;
}

struct AURenderCallbackStruct
{
    AURenderCallback inputProc;
    void* inputProcRefCon;
}



struct AUPreset
{
    SInt32      presetNumber;
    CFStringRef presetName;
}

enum : AudioUnitPropertyID
{
    kAudioUnitProperty_SRCAlgorithm             = 9, // see kAudioUnitProperty_SampleRateConverterComplexity
    kAudioUnitProperty_MIDIControlMapping       = 17, // see ParameterMIDIMapping Properties
    kAudioUnitProperty_CurrentPreset            = 28, // see PresentPreset

    kAudioUnitProperty_ParameterValueName       = kAudioUnitProperty_ParameterStringFromValue,
    kAudioUnitProperty_BusCount                 = kAudioUnitProperty_ElementCount,
}


extern(C) nothrow @nogc
{
    alias HostCallback_GetBeatAndTempo = OSStatus function(void * inHostUserData,
                                                Float64 *   outCurrentBeat,
                                                Float64 *   outCurrentTempo);

    alias HostCallback_GetMusicalTimeLocation = OSStatus function(void *  inHostUserData,
                                                    UInt32 *        outDeltaSampleOffsetToNextBeat,
                                                    Float32 *       outTimeSig_Numerator,
                                                    UInt32 *        outTimeSig_Denominator,
                                                    Float64 *       outCurrentMeasureDownBeat);
    alias HostCallback_GetTransportState = OSStatus function(void *   inHostUserData,
                                            Boolean *           outIsPlaying,
                                            Boolean *           outTransportStateChanged,
                                            Float64 *           outCurrentSampleInTimeLine,
                                            Boolean *           outIsCycling,
                                            Float64 *           outCycleStartBeat,
                                            Float64 *           outCycleEndBeat);
    alias HostCallback_GetTransportState2 = OSStatus function(void * inHostUserData,
                                            Boolean *           outIsPlaying,
                                            Boolean *           outIsRecording,
                                            Boolean *           outTransportStateChanged,
                                            Float64 *           outCurrentSampleInTimeLine,
                                            Boolean *           outIsCycling,
                                            Float64 *           outCycleStartBeat,
                                            Float64 *           outCycleEndBeat);
}

struct HostCallbackInfo
{
    void *                                    hostUserData;
    HostCallback_GetBeatAndTempo              beatAndTempoProc;
    HostCallback_GetMusicalTimeLocation       musicalTimeLocationProc;
    HostCallback_GetTransportState            transportStateProc;
    HostCallback_GetTransportState2           transportStateProc2;
}

struct AudioUnitCocoaViewInfo
{
    CFURLRef    mCocoaAUViewBundleLocation;
    CFStringRef[1] mCocoaAUViewClass;
}

extern(C) nothrow @nogc
{
    alias AUMIDIOutputCallback = OSStatus function(void* userData,
                                                   const(AudioTimeStamp)* timeStamp,
                                                   UInt32 midiOutNum,
                                                   const(MIDIPacketList)* pktlist);
}

struct AUMIDIOutputCallbackStruct
{
    AUMIDIOutputCallback midiOutputCallback;
    void* userData;
}

struct AudioUnitParameterInfo
{
    char[52]                    name;
    CFStringRef                 unitName;
    UInt32                      clumpID;
    CFStringRef                 cfNameString;
    AudioUnitParameterUnit      unit;
    AudioUnitParameterValue     minValue;
    AudioUnitParameterValue     maxValue;
    AudioUnitParameterValue     defaultValue;
    AudioUnitParameterOptions   flags;
}

alias AudioUnitParameterUnit = UInt32;
enum : AudioUnitParameterUnit
{
    kAudioUnitParameterUnit_Generic             = 0,
    kAudioUnitParameterUnit_Indexed             = 1,
    kAudioUnitParameterUnit_Boolean             = 2,
    kAudioUnitParameterUnit_Percent             = 3,
    kAudioUnitParameterUnit_Seconds             = 4,
    kAudioUnitParameterUnit_SampleFrames        = 5,
    kAudioUnitParameterUnit_Phase               = 6,
    kAudioUnitParameterUnit_Rate                = 7,
    kAudioUnitParameterUnit_Hertz               = 8,
    kAudioUnitParameterUnit_Cents               = 9,
    kAudioUnitParameterUnit_RelativeSemiTones   = 10,
    kAudioUnitParameterUnit_MIDINoteNumber      = 11,
    kAudioUnitParameterUnit_MIDIController      = 12,
    kAudioUnitParameterUnit_Decibels            = 13,
    kAudioUnitParameterUnit_LinearGain          = 14,
    kAudioUnitParameterUnit_Degrees             = 15,
    kAudioUnitParameterUnit_EqualPowerCrossfade = 16,
    kAudioUnitParameterUnit_MixerFaderCurve1    = 17,
    kAudioUnitParameterUnit_Pan                 = 18,
    kAudioUnitParameterUnit_Meters              = 19,
    kAudioUnitParameterUnit_AbsoluteCents       = 20,
    kAudioUnitParameterUnit_Octaves             = 21,
    kAudioUnitParameterUnit_BPM                 = 22,
    kAudioUnitParameterUnit_Beats               = 23,
    kAudioUnitParameterUnit_Milliseconds        = 24,
    kAudioUnitParameterUnit_Ratio               = 25,
    kAudioUnitParameterUnit_CustomUnit          = 26
}

alias AudioUnitParameterOptions = UInt32;
enum : AudioUnitParameterOptions
{
    kAudioUnitParameterFlag_CFNameRelease       = (1UL << 4),

    kAudioUnitParameterFlag_OmitFromPresets     = (1UL << 13),
    kAudioUnitParameterFlag_PlotHistory         = (1UL << 14),
    kAudioUnitParameterFlag_MeterReadOnly       = (1UL << 15),

    // bit positions 18,17,16 are set aside for display scales. bit 19 is reserved.
    kAudioUnitParameterFlag_DisplayMask         = (7UL << 16) | (1UL << 22),
    kAudioUnitParameterFlag_DisplaySquareRoot   = (1UL << 16),
    kAudioUnitParameterFlag_DisplaySquared      = (2UL << 16),
    kAudioUnitParameterFlag_DisplayCubed        = (3UL << 16),
    kAudioUnitParameterFlag_DisplayCubeRoot     = (4UL << 16),
    kAudioUnitParameterFlag_DisplayExponential  = (5UL << 16),

    kAudioUnitParameterFlag_HasClump            = (1UL << 20),
    kAudioUnitParameterFlag_ValuesHaveStrings   = (1UL << 21),

    kAudioUnitParameterFlag_DisplayLogarithmic  = (1UL << 22),

    kAudioUnitParameterFlag_IsHighResolution    = (1UL << 23),
    // parameter is non-automatable
    kAudioUnitParameterFlag_NonRealTime         = (1UL << 24),
    kAudioUnitParameterFlag_CanRamp             = (1UL << 25),
    kAudioUnitParameterFlag_ExpertMode          = (1UL << 26),
    kAudioUnitParameterFlag_HasCFNameString     = (1UL << 27),
    kAudioUnitParameterFlag_IsGlobalMeta        = (1UL << 28),
    kAudioUnitParameterFlag_IsElementMeta       = (1UL << 29),
    kAudioUnitParameterFlag_IsReadable          = (1UL << 30),
    kAudioUnitParameterFlag_IsWritable          = (1UL << 31)
}

struct AudioUnitParameterNameInfo
{
    AudioUnitParameterID    inID;
    SInt32                  inDesiredLength;
    CFStringRef             outName;
}
alias AudioUnitParameterIDName = AudioUnitParameterNameInfo;

struct AudioUnitParameterStringFromValue
{
    AudioUnitParameterID                inParamID;
    const(AudioUnitParameterValue)*     inValue;
    CFStringRef                         outString;
}

struct AudioUnitParameterValueFromString
{
    AudioUnitParameterID        inParamID;
    CFStringRef                 inString;
    AudioUnitParameterValue     outValue;
}



// AudioToolbox framework

version(OSX)
    enum libNamesToolbox = "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox";
else
    enum libNamesToolbox = "";


class DerelictAudioToolboxLoader : SharedLibLoader
{
    public
    {
        nothrow @nogc:
        this()
        {
            super(libNamesToolbox);
        }

        override void loadSymbols()
        {
            bindFunc(cast(void**)&AUEventListenerNotify, "AUEventListenerNotify");
        }
    }
}


private __gshared DerelictAudioToolboxLoader DerelictAudioToolbox;

private __gshared loaderCounterATB = 0;

// Call this each time a novel owner uses these functions
// TODO: hold a mutex, because this isn't thread-safe
void acquireAudioToolboxFunctions() nothrow @nogc
{
    if (DerelictAudioToolbox is null)  // You only live once
    {
        DerelictAudioToolbox = mallocNew!DerelictAudioToolboxLoader();
        DerelictAudioToolbox.load();
    }
}

// Call this each time a novel owner releases a Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
void releaseAudioToolboxFunctions() nothrow @nogc
{
    /*if (--loaderCounterATB == 0)
    {
        DerelictAudioToolbox.unload();
        DerelictAudioToolbox.destroyFree();
    }*/
}

unittest
{
    version(OSX)
    {
        acquireAudioToolboxFunctions();
        releaseAudioToolboxFunctions();
    }
}


alias AudioUnitEventType = UInt32;
enum : AudioUnitEventType
{
    kAudioUnitEvent_ParameterValueChange        = 0,
    kAudioUnitEvent_BeginParameterChangeGesture = 1,
    kAudioUnitEvent_EndParameterChangeGesture   = 2,
    kAudioUnitEvent_PropertyChange              = 3
}

alias AUEventListenerRef = void*;

struct AudioUnitEvent
{
    AudioUnitEventType                  mEventType;
    union Argument
    {
        AudioUnitParameter  mParameter; // for parameter value change, begin and end gesture
        AudioUnitProperty   mProperty;  // for kAudioUnitEvent_PropertyChange
    }
    Argument mArgument;
}

extern(C) nothrow @nogc
{
    alias da_AUEventListenerNotify = OSStatus function(AUEventListenerRef inSendingListener, void* inSendingObject, const(AudioUnitEvent)* inEvent);
}

__gshared
{
    da_AUEventListenerNotify AUEventListenerNotify;
}

enum
{
    kMusicDeviceRange = 0x0100,
    kMusicDeviceMIDIEventSelect = 0x0101,
    kMusicDeviceSysExSelect = 0x0102,
    kMusicDevicePrepareInstrumentSelect = 0x0103,
    kMusicDeviceReleaseInstrumentSelect = 0x0104,
    kMusicDeviceStartNoteSelect = 0x0105,
    kMusicDeviceStopNoteSelect = 0x0106,
}

alias MusicDeviceInstrumentID = uint;
alias MusicDeviceGroupID = uint;
alias NoteInstanceID = uint;

struct MusicDeviceNoteParams
{
    UInt32 argCount;
    Float32 mPitch;
    Float32 mVelocity;
    //NoteParamsControlValue[1] mControls;               /* arbitrary length */
}

//
// AUDIO COMPONENT API
//
// AudioComponent.h


alias AudioComponentFlags = UInt32;
enum : AudioComponentFlags
{
    kAudioComponentFlag_Unsearchable = 1,  // available: OSX 10.7
    kAudioComponentFlag_SandboxSafe = 2    // available: OSX 10.8
}

struct AudioComponentDescription
{
    OSType componentType;
    OSType componentSubType;
    OSType componentManufacturer;
    UInt32 componentFlags;
    UInt32 componentFlagsMask;
}

alias AudioComponent = void*;

extern(C) nothrow
{
    alias AudioComponentMethod = OSStatus function(void *self,...);
}

struct AudioComponentPlugInInterface
{
    extern(C) nothrow OSStatus function(void *self, AudioComponentInstance mInstance) Open;
    extern(C) nothrow OSStatus function(void *self) Close;
    extern(C) nothrow AudioComponentMethod function(SInt16 selector) Lookup;
    void*                reserved;
}

extern(C) nothrow
{
    alias AudioComponentFactoryFunction = AudioComponentPlugInInterface* function(const(AudioComponentDescription)* inDesc);
}


// <CoreMIDI/MIDIServices.h>

alias MIDITimeStamp = ulong;

struct MIDIPacket
{
    MIDITimeStamp       timeStamp;
    UInt16              length;
    byte[256]           data;
}
static assert(MIDIPacket.sizeof == 8 + 2 + 6 + 256); // verified with c++ Godbolt

const(MIDIPacket)* MIDIPacketNext(const(MIDIPacket)* pkt)
{
    version(ARM)
    {
        ptrdiff_t mask = ~3;
        size_t p = cast(size_t)(pkt.data.ptr + pkt.length);
        p = (p + 3) & mask;
        return cast(const(MIDIPacket)*)p;
    }
    else version(AArch64)
    {
        ptrdiff_t mask = ~3;
        size_t p = cast(size_t)(pkt.data.ptr + pkt.length);
        p = (p + 3) & mask;
        return cast(const(MIDIPacket)*)p;
    }
    else
    {
        return cast(const(MIDIPacket)*)(pkt.data.ptr + pkt.length);
    }
}

struct MIDIPacketList
{
    UInt32              numPackets;
    MIDIPacket[1]           packet;
}
static assert(MIDIPacketList.sizeof == 4 + 4 + MIDIPacket.sizeof); // verified with C++ Godbolt
