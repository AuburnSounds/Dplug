//------------------------------------------------------------------------
// Project     : VST SDK
//
// Category    : Interfaces
// Filename    : pluginterfaces/vst/ivstaudioprocessor.h
//               pluginterfaces/vst/ivstparameterchanges.h
//               pluginterfaces/vst/ivstprocessorcontext.h
//               pluginterfaces/vst/ivstevents.h
//               pluginterfaces/vst/ivstnoteexpression.h
//               pluginterfaces/vst/ivsthostapplication.h
//
// Created by  : Steinberg, 10/2005
// Description : VST Audio Processing Interfaces
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------
module dplug.vst3.ivstaudioprocessor;

import dplug.vst3.ftypes;


immutable string kVstAudioEffectClass = "Audio Module Class";

struct PlugType
{
    static immutable:

    string kFxAnalyzer           = "Fx|Analyzer";    ///< Scope, FFT-Display, Loudness Processing...
    string kFxDelay              = "Fx|Delay";       ///< Delay, Multi-tap Delay, Ping-Pong Delay...
    string kFxDistortion         = "Fx|Distortion";  ///< Amp Simulator, Sub-Harmonic, SoftClipper...
    string kFxDynamics           = "Fx|Dynamics";    ///< Compressor, Expander, Gate, Limiter, Maximizer, Tape Simulator, EnvelopeShaper...
    string kFxEQ                 = "Fx|EQ";          ///< Equalization, Graphical EQ...
    string kFxFilter             = "Fx|Filter";      ///< WahWah, ToneBooster, Specific Filter,...
    string kFx                   = "Fx";             ///< others type (not categorized)
    string kFxInstrument         = "Fx|Instrument";  ///< Fx which could be loaded as Instrument too
    string kFxInstrumentExternal = "Fx|Instrument|External"; ///< Fx which could be loaded as Instrument too and is external (wrapped Hardware)
    string kFxSpatial            = "Fx|Spatial";     ///< MonoToStereo, StereoEnhancer,...
    string kFxGenerator          = "Fx|Generator";   ///< Tone Generator, Noise Generator...
    string kFxMastering          = "Fx|Mastering";   ///< Dither, Noise Shaping,...
    string kFxModulation         = "Fx|Modulation";  ///< Phaser, Flanger, Chorus, Tremolo, Vibrato, AutoPan, Rotary, Cloner...
    string kFxPitchShift         = "Fx|Pitch Shift"; ///< Pitch Processing, Pitch Correction, Vocal Tuning...
    string kFxRestoration        = "Fx|Restoration"; ///< Denoiser, Declicker,...
    string kFxReverb             = "Fx|Reverb";      ///< Reverberation, Room Simulation, Convolution Reverb...
    string kFxSurround           = "Fx|Surround";    ///< dedicated to surround processing: LFE Splitter, Bass Manager...
    string kFxTools              = "Fx|Tools";       ///< Volume, Mixer, Tuner...
    string kFxNetwork            = "Fx|Network";     ///< using Network

    string kInstrument           = "Instrument";         ///< Effect used as instrument (sound generator), not as insert
    string kInstrumentDrum       = "Instrument|Drum";    ///< Instrument for Drum sounds
    string kInstrumentSampler    = "Instrument|Sampler"; ///< Instrument based on Samples
    string kInstrumentSynth      = "Instrument|Synth";   ///< Instrument based on Synthesis
    string kInstrumentSynthSampler = "Instrument|Synth|Sampler"; ///< Instrument based on Synthesis and Samples
    string kInstrumentExternal   = "Instrument|External";///< External Instrument (wrapped Hardware)

    string kSpatial              = "Spatial";        ///< used for SurroundPanner
    string kSpatialFx            = "Spatial|Fx";     ///< used for SurroundPanner and as insert effect
    string kOnlyRealTime         = "OnlyRT";         ///< indicates that it supports only realtime process call, no processing faster than realtime
    string kOnlyOfflineProcess   = "OnlyOfflineProcess"; ///< used for Plug-in offline processing  (will not work as normal insert Plug-in)
    string kNoOfflineProcess     = "NoOfflineProcess";   ///< will be NOT used for Plug-in offline processing (will work as normal insert Plug-in)
    string kUpDownMix            = "Up-Downmix";     ///< used for Mixconverter/Up-Mixer/Down-Mixer
    string kAnalyzer             = "Analyzer";       ///< Meter, Scope, FFT-Display, not selectable as insert plugin
    string kAmbisonics           = "Ambisonics";     ///< used for Ambisonics channel (FX or Panner/Mixconverter/Up-Mixer/Down-Mixer when combined with other category)

    string kMono                 = "Mono";           ///< used for Mono only Plug-in [optional]
    string kStereo               = "Stereo";         ///< used for Stereo only Plug-in [optional]
    string kSurround             = "Surround";       ///< used for Surround only Plug-in [optional]
}


alias ComponentFlags = int;
enum : ComponentFlags
{
    kDistributable          = 1 << 0,   ///< Component can be run on remote computer
    kSimpleModeSupported    = 1 << 1    ///< Component supports simple IO mode (or works in simple mode anyway) see \ref vst3IoMode
}


// Symbolic sample size.
alias SymbolicSampleSizes = int;
enum : SymbolicSampleSizes
{
    kSample32,      ///< 32-bit precision
    kSample64       ///< 64-bit precision
}

/** Processing mode informs the Plug-in about the context and at which frequency the process call is called.
VST3 defines 3 modes:
- kRealtime: each process call is called at a realtime frequency (defined by [numSamples of ProcessData] / samplerate).
             The Plug-in should always try to process as fast as possible in order to let enough time slice to other Plug-ins.
- kPrefetch: each process call could be called at a variable frequency (jitter, slower / faster than realtime),
             the Plug-in should process at the same quality level than realtime, Plug-in must not slow down to realtime
             (e.g. disk streaming)!
             The host should avoid to process in kPrefetch mode such sampler based Plug-in.
- kOffline:  each process call could be faster than realtime or slower, higher quality than realtime could be used.
             Plug-ins using disk streaming should be sure that they have enough time in the process call for streaming,
             if needed by slowing down to realtime or slower.
.
Note about Process Modes switching:
    -Switching between kRealtime and kPrefetch process modes are done in realtime thread without need of calling
     IAudioProcessor::setupProcessing, the Plug-in should check in process call the member processMode of ProcessData
     in order to know in which mode it is processed.
    -Switching between kRealtime (or kPrefetch) and kOffline requires that the host calls IAudioProcessor::setupProcessing
     in order to inform the Plug-in about this mode change. */
alias ProcessModes = int;
enum : ProcessModes
{
    kRealtime,      ///< realtime processing
    kPrefetch,      ///< prefetch processing
    kOffline        ///< offline processing
}

/** kNoTail
 *
 * to be returned by getTailSamples when no tail is wanted
 \see IAudioProcessor::getTailSamples */
enum uint kNoTail = 0;

/** kInfiniteTail
 *
 * to be returned by getTailSamples when infinite tail is wanted
 \see IAudioProcessor::getTailSamples */
enum uint kInfiniteTail = uint.max;

/** Audio processing setup.
\see IAudioProcessor::setupProcessing */
struct ProcessSetup
{
    int32 processMode;          ///< \ref ProcessModes
    int32 symbolicSampleSize;   ///< \ref SymbolicSampleSizes
    int32 maxSamplesPerBlock;   ///< maximum number of samples per audio block
    SampleRate sampleRate;      ///< sample rate
}

mixin SMTG_TYPE_SIZE_CHECK!(ProcessSetup, 24, 20, 24);

/** Processing buffers of an audio bus.
This structure contains the processing buffer for each channel of an audio bus.
- The number of channels (numChannels) must always match the current bus arrangement.
  It could be set to value '0' when the host wants to flush the parameters (when the Plug-in is not processed).
- The size of the channel buffer array must always match the number of channels. So the host
  must always supply an array for the channel buffers, regardless if the
  bus is active or not. However, if an audio bus is currently inactive, the actual sample
  buffer addresses are safe to be null.
- The silence flag is set when every sample of the according buffer has the value '0'. It is
  intended to be used as help for optimizations allowing a Plug-in to reduce processing activities.
  But even if this flag is set for a channel, the channel buffers must still point to valid memory!
  This flag is optional. A host is free to support it or not.
.
\see ProcessData */
struct AudioBusBuffers
{
    int32 numChannels = 0;      ///< number of audio channels in bus
    uint64 silenceFlags = 0;    ///< Bitset of silence state per channel
    union
    {
        Sample32** channelBuffers32 = null;    ///< sample buffers to process with 32-bit precision
        Sample64** channelBuffers64;    ///< sample buffers to process with 64-bit precision
    }
}

mixin SMTG_TYPE_SIZE_CHECK!(AudioBusBuffers, 24, 16, 24);

/** Any data needed in audio processing.
    The host prepares AudioBusBuffers for each input/output bus,
    regardless of the bus activation state. Bus buffer indices always match
    with bus indices used in IComponent::getBusInfo of media type kAudio.
\see AudioBusBuffers, IParameterChanges, IEventList, ProcessContext */
struct ProcessData
{
    int32 processMode = 0;          ///< processing mode - value of \ref ProcessModes
    int32 symbolicSampleSize = kSample32;   ///< sample size - value of \ref SymbolicSampleSizes
    int32 numSamples = 0;           ///< number of samples to process
    int32 numInputs = 0;            ///< number of audio input buses
    int32 numOutputs = 0;           ///< number of audio output buses
    AudioBusBuffers* inputs = null;  ///< buffers of input buses
    AudioBusBuffers* outputs = null; ///< buffers of output buses

    IParameterChanges inputParameterChanges = null;   ///< incoming parameter changes for this block
    IParameterChanges outputParameterChanges = null;  ///< outgoing parameter changes for this block (optional)
    IEventList inputEvents = null;                ///< incoming events for this block (optional)
    IEventList outputEvents = null;               ///< outgoing events for this block (optional)
    ProcessContext* processContext = null;         ///< processing context (optional, but most welcome)
}

mixin SMTG_TYPE_SIZE_CHECK!(ProcessData, 80, 48, 48);

/** Audio Processing Interface.
This interface must always be supported by audio processing Plug-ins. */
interface IAudioProcessor: FUnknown
{
public:
nothrow:
@nogc:

    /** Try to set (from host) a predefined arrangement for inputs and outputs.
        The host should always deliver the same number of input and output buses than the Plug-in needs 
        (see \ref IComponent::getBusCount).
        The Plug-in returns kResultFalse if wanted arrangements are not supported.
        If the Plug-in accepts these arrangements, it should modify its buses to match the new arrangements
        (asked by the host with IComponent::getInfo () or IAudioProcessor::getBusArrangement ()) and then return kResultTrue.
        If the Plug-in does not accept these arrangements, but can adapt its current arrangements (according to the wanted ones),
        it should modify its buses arrangements and return kResultFalse. */
    tresult setBusArrangements (SpeakerArrangement* inputs, int32 numIns,  SpeakerArrangement* outputs, int32 numOuts);

    /** Gets the bus arrangement for a given direction (input/output) and index.
        Note: IComponent::getInfo () and IAudioProcessor::getBusArrangement () should be always return the same 
        information about the buses arrangements. */
    tresult getBusArrangement (BusDirection dir, int32 index, ref SpeakerArrangement arr);

    /** Asks if a given sample size is supported see \ref SymbolicSampleSizes. */
    tresult canProcessSampleSize (int32 symbolicSampleSize);

    /** Gets the current Latency in samples.
        The returned value defines the group delay or the latency of the Plug-in. For example, if the Plug-in internally needs
        to look in advance (like compressors) 512 samples then this Plug-in should report 512 as latency.
        If during the use of the Plug-in this latency change, the Plug-in has to inform the host by
        using IComponentHandler::restartComponent (kLatencyChanged), this could lead to audio playback interruption
        because the host has to recompute its internal mixer delay compensation.
        Note that for player live recording this latency should be zero or small. */
    uint32 getLatencySamples ();

    /** Called in disable state (not active) before processing will begin. */
    tresult setupProcessing (ref ProcessSetup setup);

    /** Informs the Plug-in about the processing state. This will be called before any process calls start with true and after with false.
        Note that setProcessing (false) may be called after setProcessing (true) without any process calls.
        In this call the Plug-in should do only light operation (no memory allocation or big setup reconfiguration), 
        this could be used to reset some buffers (like Delay line or Reverb). */
    tresult setProcessing (TBool state);

    /** The Process call, where all information (parameter changes, event, audio buffer) are passed. */
    tresult process (ref ProcessData data);

    /** Gets tail size in samples. For example, if the Plug-in is a Reverb Plug-in and it knows that
        the maximum length of the Reverb is 2sec, then it has to return in getTailSamples() 
        (in VST2 it was getGetTailSize ()): 2*sampleRate.
        This information could be used by host for offline processing, process optimization and 
        downmix (avoiding signal cut (clicks)).
        It should return:
         - kNoTail when no tail
         - x * sampleRate when x Sec tail.
         - kInfiniteTail when infinite tail. */
    uint32 getTailSamples ();

    __gshared immutable TUID iid = INLINE_UID(0x42043F99, 0xB7DA453C, 0xA569E79D, 0x9AAEC33D);
}


// ivstparameterchanges.h

//----------------------------------------------------------------------
/** Queue of changes for a specific parameter.
\ingroup vstIHost vst300
- [host imp]
- [released: 3.0.0]

The change queue can be interpreted as segment of an automation curve. For each
processing block a segment with the size of the block is transmitted to the processor.
The curve is expressed as sampling points of a linear approximation of
the original automation curve. If the original already is a linear curve it can
be transmitted precisely. A non-linear curve has to be converted to a linear
approximation by the host. Every point of the value queue defines a linear
section of the curve as a straight line from the previous point of a block to
the new one. So the Plug-in can calculate the value of the curve for any sample
position in the block.

<b>Implicit Points:</b> \n
In each processing block the section of the curve for each parameter is transmitted.
In order to reduce the amount of points, the point at block position 0 can be omitted.
- If the curve has a slope of 0 over a period of multiple blocks, only one point is
transmitted for the block where the constant curve section starts. The queue for the following
blocks will be empty as long as the curve slope is 0.
- If the curve has a constant slope other than 0 over the period of several blocks, only
the value for the last sample of the block is transmitted. In this case the last valid point
is at block position -1. The processor can calculate the value for each sample in the block
by using a linear interpolation:
\code
double x1 = -1; // position of last point related to current buffer
double y1 = currentParameterValue; // last transmitted value

int32 pointTime = 0;
ParamValue pointValue = 0;
IParamValueQueue::getPoint (0, pointTime, pointValue);

double x2 = pointTime;
double y2 = pointValue;

double slope = (y2 - y1) / (x2 - x1);
double offset = y1 - (slope * x1);

double curveValue = (slope * bufferTime) + offset; // bufferTime is any position in buffer
\endcode

<b>Jumps:</b> \n
A jump in the automation curve has to be transmitted as two points: one with the
old value and one with the new value at the next sample position.

\image html "automation.jpg"
\see IParameterChanges, ProcessData
*/
interface IParamValueQueue: FUnknown
{
public:
nothrow:
@nogc:
    /** Returns its associated ID. */
    ParamID getParameterId ();

    /** Returns count of points in the queue. */
    int32 getPointCount ();

    /** Gets the value and offset at a given index. */
    tresult getPoint (int32 index, ref int32 sampleOffset /*out*/, ref ParamValue value /*out*/);

    /** Adds a new value at the end of the queue, its index is returned. */
    tresult addPoint (int32 sampleOffset, ParamValue value, ref int32 index /*out*/);

    __gshared immutable TUID iid = INLINE_UID(0x01263A18, 0xED074F6F, 0x98C9D356, 0x4686F9BA);
}

//----------------------------------------------------------------------
/** All parameter changes of a processing block.
\ingroup vstIHost vst300
- [host imp]
- [released: 3.0.0]

This interface is used to transmit any changes that shall be applied to parameters
in the current processing block. A change can be caused by GUI interaction as
well as automation. They are transmitted as a list of queues (IParamValueQueue)
containing only queues for parameters that actually did change.
\see IParamValueQueue, ProcessData */
//----------------------------------------------------------------------
interface IParameterChanges: FUnknown
{
public:
nothrow:
@nogc:
    /** Returns count of Parameter changes in the list. */
    int32 getParameterCount () ;

    /** Returns the queue at a given index. */
    IParamValueQueue getParameterData (int32 index);

    /** Adds a new parameter queue with a given ID at the end of the list,
    returns it and its index in the parameter changes list. */
    IParamValueQueue addParameterData (ref const(ParamID) id, ref int32 index /*out*/);

    __gshared immutable TUID iid = INLINE_UID(0xA4779663, 0x0BB64A56, 0xB44384A8, 0x466FEB9D);
}

// ivstprocesscontext.h

/** Audio processing context.
For each processing block the host provides timing information and
musical parameters that can change over time. For a host that supports jumps
(like cycle) it is possible to split up a processing block into multiple parts in
order to provide a correct project time inside of every block, but this behaviour
is not mandatory. Since the timing will be correct at the beginning of the next block
again, a host that is dependent on a fixed processing block size can choose to neglect
this problem.
\see IAudioProcessor, ProcessData*/
struct ProcessContext
{
    /** Transport state & other flags */
    alias StatesAndFlags = int;
    enum : StatesAndFlags
    {
        kPlaying          = 1 << 1,     ///< currently playing
        kCycleActive      = 1 << 2,     ///< cycle is active
        kRecording        = 1 << 3,     ///< currently recording

        kSystemTimeValid  = 1 << 8,     ///< systemTime contains valid information
        kContTimeValid    = 1 << 17,    ///< continousTimeSamples contains valid information

        kProjectTimeMusicValid = 1 << 9,///< projectTimeMusic contains valid information
        kBarPositionValid = 1 << 11,    ///< barPositionMusic contains valid information
        kCycleValid       = 1 << 12,    ///< cycleStartMusic and barPositionMusic contain valid information

        kTempoValid       = 1 << 10,    ///< tempo contains valid information
        kTimeSigValid     = 1 << 13,    ///< timeSigNumerator and timeSigDenominator contain valid information
        kChordValid       = 1 << 18,    ///< chord contains valid information

        kSmpteValid       = 1 << 14,    ///< smpteOffset and frameRate contain valid information
        kClockValid       = 1 << 15     ///< samplesToNextClock valid
    }

    uint32 state;                   ///< a combination of the values from \ref StatesAndFlags

    double sampleRate;              ///< current sample rate (always valid)
    TSamples projectTimeSamples;    ///< project time in samples (always valid)

    int64 systemTime;               ///< system time in nanoseconds (optional)
    TSamples continousTimeSamples;  ///< project time, without loop (optional)

    TQuarterNotes projectTimeMusic; ///< musical position in quarter notes (1.0 equals 1 quarter note)
    TQuarterNotes barPositionMusic; ///< last bar start position, in quarter notes
    TQuarterNotes cycleStartMusic;  ///< cycle start in quarter notes
    TQuarterNotes cycleEndMusic;    ///< cycle end in quarter notes

    double tempo;                   ///< tempo in BPM (Beats Per Minute)
    int32 timeSigNumerator;         ///< time signature numerator (e.g. 3 for 3/4)
    int32 timeSigDenominator;       ///< time signature denominator (e.g. 4 for 3/4)

    Chord chord;                    ///< musical info

    int32 smpteOffsetSubframes;     ///< SMPTE (sync) offset in subframes (1/80 of frame)
    FrameRate frameRate;            ///< frame rate

    int32 samplesToNextClock;       ///< MIDI Clock Resolution (24 Per Quarter Note), can be negative (nearest)
}

mixin SMTG_TYPE_SIZE_CHECK!(ProcessContext, 112, 104, 112);

struct FrameRate
{
    enum FrameRateFlags
    {
        kPullDownRate = 1 << 0, ///< for ex. HDTV: 23.976 fps with 24 as frame rate
        kDropRate     = 1 << 1  ///< for ex. 29.97 fps drop with 30 as frame rate
    };
    uint32 framesPerSecond;     ///< frame rate
    uint32 flags;               ///< flags #FrameRateFlags
}

mixin SMTG_TYPE_SIZE_CHECK!(FrameRate, 8, 8, 8);

/** Description of a chord.
A chord is described with a key note, a root note and the
\copydoc chordMask
\see ProcessContext*/

struct Chord
{
    uint8 keyNote;      ///< key note in chord
    uint8 rootNote;     ///< lowest note in chord

    /** Bitmask of a chord.
        1st bit set: minor second; 2nd bit set: major second, and so on. \n
        There is \b no bit for the keynote (root of the chord) because it is inherently always present. \n
        Examples:
        - XXXX 0000 0100 1000 (= 0x0048) -> major chord\n
        - XXXX 0000 0100 0100 (= 0x0044) -> minor chord\n
        - XXXX 0010 0100 0100 (= 0x0244) -> minor chord with minor seventh  */
    int16 chordMask;

    enum Masks {
        kChordMask = 0x0FFF,    ///< mask for chordMask
        kReservedMask = 0xF000  ///< reserved for future use
    }
}

mixin SMTG_TYPE_SIZE_CHECK!(Chord, 4, 4, 4);

/** Note-on event specific data. Used in \ref Event (union)*/
struct NoteOnEvent
{
    short channel;          ///< channel index in event bus
    short pitch;            ///< range [0, 127] = [C-2, G8] with A3=440Hz
    float tuning;           ///< 1.f = +1 cent, -1.f = -1 cent
    float velocity;         ///< range [0.0, 1.0]
    int length;           ///< in sample frames (optional, Note Off has to follow in any case!)
    int noteId;           ///< note identifier (if not available then -1)
}

mixin SMTG_TYPE_SIZE_CHECK!(NoteOnEvent, 20, 20, 20);

/** Note-off event specific data. Used in \ref Event (union)*/
struct NoteOffEvent
{
    int16 channel;          ///< channel index in event bus
    int16 pitch;            ///< range [0, 127] = [C-2, G8] with A3=440Hz
    float velocity;         ///< range [0.0, 1.0]
    int32 noteId;           ///< associated noteOn identifier (if not available then -1)
    float tuning;           ///< 1.f = +1 cent, -1.f = -1 cent
}

mixin SMTG_TYPE_SIZE_CHECK!(NoteOffEvent, 16, 16, 16);

/** Data event specific data. Used in \ref Event (union)*/
struct DataEvent
{
    uint32 size;            ///< size in bytes of the data block bytes
    uint32 type;            ///< type of this data block (see \ref DataTypes)
    const uint8* bytes;     ///< pointer to the data block

    /** Value for DataEvent::type */
    enum DataTypes
    {
        kMidiSysEx = 0      ///< for MIDI system exclusive message
    }
}

mixin SMTG_TYPE_SIZE_CHECK!(DataEvent, 16, 12, 12);

/** PolyPressure event specific data. Used in \ref Event (union)*/
struct PolyPressureEvent
{
    int16 channel;          ///< channel index in event bus
    int16 pitch;            ///< range [0, 127] = [C-2, G8] with A3=440Hz
    float pressure;         ///< range [0.0, 1.0]
    int32 noteId;           ///< event should be applied to the noteId (if not -1)
}

mixin SMTG_TYPE_SIZE_CHECK!(PolyPressureEvent, 12, 12, 12);

/** Chord event specific data. Used in \ref Event (union)*/
struct ChordEvent
{
    int16 root;             ///< range [0, 127] = [C-2, G8] with A3=440Hz
    int16 bassNote;         ///< range [0, 127] = [C-2, G8] with A3=440Hz
    int16 mask;             ///< root is bit 0
    uint16 textLen;         ///< the number of characters (TChar) between the beginning of text and the terminating
    ///< null character (without including the terminating null character itself)
    const TChar* text;      ///< UTF-16, null terminated Hosts Chord Name
}

mixin SMTG_TYPE_SIZE_CHECK!(ChordEvent, 16, 12, 12);

/** Scale event specific data. Used in \ref Event (union)*/
struct ScaleEvent
{
    int16 root;             ///< range [0, 127] = root Note/Transpose Factor
    int16 mask;             ///< Bit 0 =  C,  Bit 1 = C#, ... (0x5ab5 = Major Scale)
    uint16 textLen;         ///< the number of characters (TChar) between the beginning of text and the terminating
    ///< null character (without including the terminating null character itself)
    const TChar* text;      ///< UTF-16, null terminated, Hosts Scale Name
}

mixin SMTG_TYPE_SIZE_CHECK!(ScaleEvent, 16, 10, 12);

/** Event */
struct Event
{
align(1):
    int32 busIndex;             ///< event bus index
    int32 sampleOffset;         ///< sample frames related to the current block start sample position
    TQuarterNotes ppqPosition;  ///< position in project
    uint16 flags;               ///< combination of \ref EventFlags

    /** Event Flags - used for Event::flags */
    enum EventFlags
    {
        kIsLive = 1 << 0,           ///< indicates that the event is played live (directly from keyboard)

        kUserReserved1 = 1 << 14,   ///< reserved for user (for internal use)
        kUserReserved2 = 1 << 15    ///< reserved for user (for internal use)
    }

    /**  Event Types - used for Event::type */
    enum EventTypes
    {
        kNoteOnEvent = 0,           ///< is \ref NoteOnEvent
        kNoteOffEvent,              ///< is \ref NoteOffEvent
        kDataEvent,                 ///< is \ref DataEvent
        kPolyPressureEvent,         ///< is \ref PolyPressureEvent
        kNoteExpressionValueEvent,  ///< is \ref NoteExpressionValueEvent
        kNoteExpressionTextEvent,   ///< is \ref NoteExpressionTextEvent
        kChordEvent,                ///< is \ref ChordEvent
        kScaleEvent                 ///< is \ref ScaleEvent
    }

    static if (size_t.sizeof == 8)
        ubyte[2] padding0;

    uint16 type;                ///< a value from \ref EventTypes
    union
    {
        NoteOnEvent noteOn;                             ///< type == kNoteOnEvent
        NoteOffEvent noteOff;                           ///< type == kNoteOffEvent
        DataEvent data;                                 ///< type == kDataEvent
        PolyPressureEvent polyPressure;                 ///< type == kPolyPressureEvent
        NoteExpressionValueEvent noteExpressionValue;   ///< type == kNoteExpressionValueEvent
        NoteExpressionTextEvent noteExpressionText;     ///< type == kNoteExpressionTextEvent
        ChordEvent chord;                               ///< type == kChordEvent
        ScaleEvent scale;                               ///< type == kScaleEvent
    }

    static if (size_t.sizeof == 8)
        ubyte[2] padding1;
}

//pragma(msg.
mixin SMTG_TYPE_SIZE_CHECK!(Event, 48, 40, 40);


        /** List of events to process.
\ingroup vstIHost vst300
- [host imp]
- [released: 3.0.0]

\see ProcessData, Event */
interface IEventList : FUnknown
{
public:
nothrow:
@nogc:
    /** Returns the count of events. */
    int32 getEventCount ();

    /** Gets parameter by index. */
    tresult getEvent (int32 index, ref Event e /*out*/);

    /** Adds a new event. */
    tresult addEvent (ref Event e /*in*/);

    __gshared immutable TUID iid = INLINE_UID(0x3A2C4214, 0x346349FE, 0xB2C4F397, 0xB9695A44);
}


alias NoteExpressionTypeID = uint;
alias NoteExpressionValue = double;

struct NoteExpressionValueEvent
{
    NoteExpressionTypeID typeId;    ///< see \ref NoteExpressionTypeID
    int32 noteId;                   ///< associated note identifier to apply the change

    NoteExpressionValue value;      ///< normalized value [0.0, 1.0].
}

mixin SMTG_TYPE_SIZE_CHECK!(NoteExpressionValueEvent, 16, 16, 16);

struct NoteExpressionTextEvent
{
    NoteExpressionTypeID typeId;    ///< see \ref NoteExpressionTypeID (kTextTypeID or kPhoneticTypeID)
    int32 noteId;                   ///< associated note identifier to apply the change

    uint32 textLen;                 ///< the number of characters (TChar) between the beginning of text and the terminating
    ///< null character (without including the terminating null character itself)

    const TChar* text;              ///< UTF-16, null terminated
}

mixin SMTG_TYPE_SIZE_CHECK!(NoteExpressionTextEvent, 24, 16, 16);


/** Basic Host Callback Interface.
\ingroup vstIHost vst300
- [host imp]
- [passed as 'context' in to IPluginBase::initialize () ]
- [released: 3.0.0]

Basic VST host application interface. */
interface IHostApplication: FUnknown
{
public:
nothrow:
@nogc:
    /** Gets host application name. */
    tresult getName (String128* name);

    /** Creates host object (e.g. Vst::IMessage). */
    tresult createInstance (TUID cid, TUID _iid, void** obj);

    __gshared immutable TUID iid = INLINE_UID(0x58E595CC, 0xDB2D4969, 0x8B6AAF8C, 0x36A664E5);
}
