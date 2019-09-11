/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2016 Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
/**
   Audio Unit plug-in client.
*/
module dplug.au.client;

import core.stdc.stdio;
import core.stdc.config;
import core.stdc.string;

import std.string;
import std.conv;

import derelict.carbon;

import dplug.core.vec;
import dplug.core.nogc;
import dplug.core.lockedqueue;
import dplug.core.runtime;
import dplug.core.sync;
import dplug.core.fpcontrol;
import dplug.core.thread;

import dplug.client.client;
import dplug.client.daw;
import dplug.client.midi;
import dplug.client.preset;
import dplug.client.params;
import dplug.client.graphics;

import dplug.au.dfxutil;
import dplug.au.cocoaviewfactory;
import dplug.au.audiocomponentdispatch;


//version = logDispatcher;

// Difference with IPlug
// - no support for parameters group
// - no support for multi-output instruments
// - no support for UI resize

// FUTURE: thread safety isn't very fine-grained, and there is 3 mutex lock in the audio thread


template AUEntryPoint(alias ClientClass)
{
    // The entry point names must be kept in sync with names in the .rsrc

    const char[] AUEntryPoint =
    "import derelict.carbon;" ~
    "export extern(C) ComponentResult dplugAUEntryPoint(ComponentParameters* params, void* pPlug) nothrow  @nogc" ~
    "{" ~
        "return audioUnitEntryPoint!" ~ ClientClass.stringof ~ "(params, pPlug);" ~
    "}" ~
    "export extern(C) void* dplugAUComponentFactoryFunction(void* inDesc) nothrow  @nogc"  ~ // type-punned here to avoid the derelict.carbon import
    "{" ~
        "return audioUnitComponentFactory!" ~ ClientClass.stringof ~ "(inDesc);" ~
    "}"
    ;
}

// LP64 => "long and pointers are 64-bit"
static if (size_t.sizeof == 8 && c_long.sizeof == 8)
    private enum __LP64__ = 1;
else
    private enum __LP64__ = 0;



private T getCompParam(T, int Idx, int Num)(ComponentParameters* params) pure nothrow @nogc
{
    c_long* p = params.params.ptr;

    static if (__LP64__)
        return *cast(T*)(&p[Num - Idx]);
    else
        return *cast(T*)(&p[Idx]);
}

package void acquireAUFunctions() nothrow @nogc
{
    acquireCoreFoundationFunctions();
    acquireCoreServicesFunctions();
    acquireAudioUnitFunctions();
    acquireAudioToolboxFunctions();
}

package void releaseAUFunctions() nothrow @nogc
{
    releaseCoreFoundationFunctions();
    releaseCoreServicesFunctions();
    releaseAudioUnitFunctions();
    releaseAudioToolboxFunctions();
}

ComponentResult audioUnitEntryPoint(alias ClientClass)(ComponentParameters* params, void* pPlug) nothrow @nogc
{
    int select = params.what;

    // Special case for the audio case that doesn't need to initialize runtime
    // and can't support attaching the thread (it's not interruptible)
    bool isAudioThread = (select == kAudioUnitRenderSelect);
    if (isAudioThread)
    {
        AUClient auClient = cast(AUClient)pPlug;
        return auClient.dispatcher(select, params);
    }

    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    if (select == kComponentOpenSelect)
    {
        acquireAUFunctions();

        // Create client and AUClient
        ClientClass client = mallocNew!ClientClass();
        ComponentInstance instance = params.getCompParam!(ComponentInstance, 0, 1);
        AUClient plugin = mallocNew!AUClient(client, instance);
        SetComponentInstanceStorage( instance, cast(Handle)(cast(void*)plugin) );
        return noErr;
    }

    AUClient auClient = cast(AUClient)pPlug;
    return auClient.dispatcher(select, params);
}

enum AUInputType
{
    notConnected = 0,
    directFastProc,
    directNoFastProc,
    renderCallback
}

/// AU client wrapper
class AUClient : IHostCommand
{
public:
nothrow:
@nogc:

    this(Client client, ComponentInstance componentInstance)
    {
        _client = client;
        _componentInstance = componentInstance; // null if Audio Component API

        int queueSize = 256;
        _messageQueue = makeLockedQueue!AudioThreadMessage(queueSize);

        _maxInputs = _client.maxInputs();
        _maxOutputs = _client.maxOutputs();

        _inputScratchBuffer = mallocSlice!(Vec!float)(_maxInputs);
        _outputScratchBuffer = mallocSlice!(Vec!float)(_maxOutputs);

        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffer[i] = makeVec!float(0, 64);

        for (int i = 0; i < _maxOutputs; ++i)
            _outputScratchBuffer[i] = makeVec!float(0, 64);

        _inputPointers = mallocSlice!(float*)(_maxInputs);
        _outputPointers = mallocSlice!(float*)(_maxOutputs);

        _inputPointersNoGap = mallocSlice!(float*)(_maxInputs);
        _outputPointersNoGap = mallocSlice!(float*)(_maxOutputs);

        // Create input buses
        int numInputBuses = (_maxInputs + 1) / 2;
        _inBuses = mallocSlice!BusChannels(numInputBuses);
        _inBusConnections = mallocSlice!InputBusConnection(numInputBuses);
        foreach(i; 0..numInputBuses)
        {
            int channels = _maxInputs - i * 2;
            if (channels > 2)
                channels = 2;
            assert(channels == 1 || channels == 2);
            _inBuses[i].connected = false;
            _inBuses[i].numHostChannels = -1;
            _inBuses[i].numPlugChannels = channels;
            _inBuses[i].plugChannelStartIdx = i * 2;
            snprintf(_inBuses[i].label.ptr, _inBuses[i].label.length, "input #%d", i);
        }

        // Create output buses

        int numOutputBuses = (_maxOutputs + 1) / 2;
        _outBuses = mallocSlice!BusChannels(numOutputBuses);
        foreach(i; 0..numOutputBuses)
        {
            int channels = _maxOutputs - i * 2;
            if (channels > 2)
                channels = 2;
            assert(channels == 1 || channels == 2);
            _outBuses[i].connected = false;
            _outBuses[i].numHostChannels = -1;
            _outBuses[i].numPlugChannels = channels;
            _outBuses[i].plugChannelStartIdx = i * 2;
            snprintf(_outBuses[i].label.ptr, _outBuses[i].label.length, "output #%d", i);
        }

        assessInputConnections();

        // Implements IHostCommand itself
        client.setHostCommand(this);

        _globalMutex = makeMutex();
        _renderNotifyMutex = makeMutex();

        _propertyListeners = makeVec!PropertyListener();
        _renderNotify = makeVec!AURenderCallbackStruct();
    }

    ~this()
    {
        _client.destroyFree();

        _messageQueue.destroy();

        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffer[i].destroy();
        _inputScratchBuffer.freeSlice();

        for (int i = 0; i < _maxOutputs; ++i)
            _outputScratchBuffer[i].destroy();
        _outputScratchBuffer.freeSlice();

        _inputPointers.freeSlice();
        _outputPointers.freeSlice();
        _inputPointersNoGap.freeSlice();
        _outputPointersNoGap.freeSlice();

        _inBuses.freeSlice();
        _inBusConnections.freeSlice();
        _outBuses.freeSlice();
    }

private:
    ComponentInstance _componentInstance; // null if Audio Component API
    Client _client;

    HostCallbackInfo _hostCallbacks;

    // Ugly protection for everything (for now)
    UncheckedMutex _globalMutex;

    LockedQueue!AudioThreadMessage _messageQueue;

    int _maxInputs, _maxOutputs;
    float _sampleRate = 44100.0f;
    int _maxFrames = 1024;

    // From audio thread POV
    bool _lastBypassed = false;
    int _lastMaxFrames = 0;
    float _lastSamplerate = 0;
    int _lastUsedInputs = 0;
    int _lastUsedOutputs = 0;

    double _lastRenderTimestamp = double.nan;

    // When true, buffers gets hard bypassed
    bool _hardBypassed = false;

    bool _active = false;

    bool _isUIOpenedAlready = false;

    Vec!float[] _inputScratchBuffer;  // input buffer, one per possible input
    Vec!float[] _outputScratchBuffer; // input buffer, one per output

    float*[] _inputPointers;  // where processAudio will take its audio input, one per possible input
    float*[] _outputPointers; // where processAudio will output audio, one per possible output

    float*[] _inputPointersNoGap;  // same array, but flatten and modified in-place
    float*[] _outputPointersNoGap; // same array, but flatten and modified in-place


    //
    // Property listeners
    //
    static struct PropertyListener
    {
        AudioUnitPropertyID mPropID;
        AudioUnitPropertyListenerProc mListenerProc;
        void* mProcArgs;
    }
    Vec!PropertyListener _propertyListeners;

    enum MaxIOChannels = 128;
    static struct BufferList
    {
        int mNumberBuffers;
        AudioBuffer[MaxIOChannels] mBuffers;
    }

    // Every stereo pair of plugin input or output is a bus.
    // Buses can have zero host channels if the host hasn't connected the bus at all,
    // one host channel if the plugin supports mono and the host has supplied a mono stream,
    // or two host channels if the host has supplied a stereo stream.
    static struct BusChannels
    {
        bool connected;
        int numHostChannels;
        int numPlugChannels;
        int plugChannelStartIdx;
        char[16] label; // pretty name
        AudioChannelLayoutTag[1] tagsBuffer;

        AudioChannelLayoutTag[] getSupportedChannelLayoutTags() nothrow @nogc
        {
            // a bit rigid right now, could be useful to support mono systematically?
            if (numPlugChannels == 1)
            {
                tagsBuffer[0] = kAudioChannelLayoutTag_Mono;

            }
            else if (numPlugChannels == 2)
            {
                tagsBuffer[0] = kAudioChannelLayoutTag_Stereo;
            }
            else
            {
                tagsBuffer[0] = kAudioChannelLayoutTag_Unknown | numPlugChannels;
            }
            return tagsBuffer[0..1];
        }
    }

    BusChannels[] _inBuses;
    BusChannels[] _outBuses;

    BusChannels* getBus(AudioUnitScope scope_, AudioUnitElement busIdx) nothrow @nogc
    {
        if (scope_ == kAudioUnitScope_Input && busIdx < _inBuses.length)
            return &_inBuses[busIdx];
        else if (scope_ == kAudioUnitScope_Output && busIdx < _outBuses.length)
            return &_outBuses[busIdx];
        // Global bus is an alias for output bus zero.
        if (scope_ == kAudioUnitScope_Global && _outBuses.length)
            return &_outBuses[busIdx];
        return null;
    }

    static struct InputBusConnection
    {
        void* upstreamObj = null;
        AudioUnitRenderProc upstreamRenderProc = null;

        AudioUnit upstreamUnit = null;
        int upstreamBusIdx = 0;

        AURenderCallbackStruct upstreamRenderCallback = AURenderCallbackStruct(null, null);

        bool isConnected() pure const nothrow @nogc
        {
            return getInputType() != AUInputType.notConnected;
        }

        AUInputType getInputType() pure const nothrow @nogc
        {
            // AU supports 3 ways to get input from the host (or whoever is upstream).
            if (upstreamRenderProc != upstreamRenderProc && upstreamObj != null)
            {
                // 1: direct input connection with fast render proc (and buffers) supplied by the upstream unit.
                return AUInputType.directFastProc;
            }
            else if (upstreamUnit != null)
            {
                // 2: direct input connection with no render proc, buffers supplied by the upstream unit.
                return AUInputType.directNoFastProc;
            }
            else if (upstreamRenderCallback.inputProc)
            {
                // 3: no direct connection, render callback, buffers supplied by us.
                return AUInputType.renderCallback;
            }
            else
            {
                return AUInputType.notConnected;
            }
        }

        ComponentResult callUpstreamRender(AudioUnitRenderActionFlags* flags,
                                           const(AudioTimeStamp)* pTimestamp,
                                           uint nFrames,
                                           AudioBufferList* pOutBufList,
                                           int inputBusIdx) nothrow @nogc
        {
            switch (getInputType()) with (AUInputType)
            {
                case directFastProc:
                {
                    return upstreamRenderProc(upstreamObj, flags, pTimestamp, upstreamBusIdx, nFrames, pOutBufList);
                }

                case directNoFastProc:
                {
                    return AudioUnitRender(upstreamUnit, flags, pTimestamp, upstreamBusIdx, nFrames, pOutBufList);
                }

                case renderCallback:
                {
                    return callRenderCallback(upstreamRenderCallback, flags, pTimestamp, inputBusIdx, nFrames, pOutBufList);
                }
                default:
                    return noErr;
            }
        }
    }

    InputBusConnection[] _inBusConnections;


    UncheckedMutex _renderNotifyMutex;
    Vec!AURenderCallbackStruct _renderNotify;


    // <scratch-buffers>

    /// Resize scratch buffers according to maximum block size.
    void resizeScratchBuffers(int nFrames) nothrow @nogc
    {
        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffer[i].resize(nFrames);

        for (int i = 0; i < _maxOutputs; ++i)
            _outputScratchBuffer[i].resize(nFrames);

    }

    // </scratch-buffers>

    //
    // DISPATCHER
    //
    final ComponentResult dispatcher(int select, ComponentParameters* params) nothrow
    {
        if (select == kComponentCloseSelect) // -2
        {
            destroyFree(cast(void*)this); // free all resources except the runtime
            releaseAUFunctions();
            return noErr;
        }

        version(logDispatcher) if (select != 14) printf("select %d\n", select);

        switch(select)
        {
            case kComponentVersionSelect: // -4, S
            {
                return _client.getPublicVersion().toAUVersion;
            }

            case kComponentCanDoSelect: // -3, S
            {
                switch (params.params[0])
                {
                    case kAudioUnitInitializeSelect:
                    case kAudioUnitUninitializeSelect:

                    case kAudioUnitGetParameterSelect:
                    case kAudioUnitSetParameterSelect:
                    case kAudioUnitScheduleParametersSelect:

                    case kAudioUnitGetPropertySelect:
                    case kAudioUnitSetPropertySelect:
                    case kAudioUnitGetPropertyInfoSelect:

                    case kAudioUnitResetSelect:
                    case kAudioUnitRenderSelect:

                    case kAudioUnitAddPropertyListenerSelect:
                    case kAudioUnitRemovePropertyListenerSelect:
                    case kAudioUnitRemovePropertyListenerWithUserDataSelect:

                    case kAudioUnitAddRenderNotifySelect:
                    case kAudioUnitRemoveRenderNotifySelect:
                        return 1;

                    // TODO for Audio Component API, are synth supported by ACAPI?
                    case kMusicDeviceMIDIEventSelect:
                    case kMusicDeviceSysExSelect:
                    case kMusicDeviceStartNoteSelect:
                    case kMusicDeviceStopNoteSelect:
                    case kMusicDevicePrepareInstrumentSelect:
                    case kMusicDeviceReleaseInstrumentSelect:
                        return _client.receivesMIDI() ? 1 : 0;

                    default:
                        return 0;
                }
            }

            case kAudioUnitInitializeSelect: // 1, S
            {
                return DoInitialize();
            }

            case kAudioUnitUninitializeSelect: // 2, S
            {
                return DoUninitialize();
            }

            case kAudioUnitGetPropertyInfoSelect: // 3
            {
                AudioUnitPropertyID propID = params.getCompParam!(AudioUnitPropertyID, 4, 5);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 3, 5);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 2, 5);
                UInt32* pDataSize = params.getCompParam!(UInt32*, 1, 5);
                Boolean* pWriteable = params.getCompParam!(Boolean*, 0, 5);
                return DoGetPropertyInfo(propID, scope_, element, pDataSize, pWriteable);
            }

            case kAudioUnitGetPropertySelect: // 4
            {
                AudioUnitPropertyID propID = params.getCompParam!(AudioUnitPropertyID, 4, 5);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 3, 5);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 2, 5);
                void* pData = params.getCompParam!(void*, 1, 5);
                UInt32* pDataSize = params.getCompParam!(UInt32*, 0, 5);
                return DoGetProperty(propID, scope_, element, pData, pDataSize);
            }

            case kAudioUnitSetPropertySelect: // 5
            {
                AudioUnitPropertyID propID = params.getCompParam!(AudioUnitPropertyID, 4, 5);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 3, 5);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 2, 5);
                const(void)* pData = params.getCompParam!(const(void)*, 1, 5);
                UInt32* pDataSize = params.getCompParam!(UInt32*, 0, 5);
                return DoSetProperty(propID, scope_, element, pData, pDataSize);
            }

            case kAudioUnitGetParameterSelect: // 6
            {
                AudioUnitParameterID paramID = params.getCompParam!(AudioUnitParameterID, 3, 4);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 2, 4);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 1, 4);
                AudioUnitParameterValue* pValue = params.getCompParam!(AudioUnitParameterValue*, 0, 4);
                return DoGetParameter(paramID, scope_, element, pValue);
            }

            case kAudioUnitSetParameterSelect: // 7
            {
                AudioUnitParameterID paramID = params.getCompParam!(AudioUnitParameterID, 4, 5);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 3, 5);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 2, 5);
                AudioUnitParameterValue value = params.getCompParam!(AudioUnitParameterValue, 1, 5);
                UInt32 offset = params.getCompParam!(UInt32, 0, 5);
                return DoSetParameter(paramID, scope_, element, value, offset);
            }

            case kAudioUnitResetSelect: // 9
            {
                AudioUnitScope scope_;
                AudioUnitElement elem;
                return DoReset(scope_, elem);
            }

            case kAudioUnitAddPropertyListenerSelect: // 10
            {
                AudioUnitPropertyID mPropID = params.getCompParam!(AudioUnitPropertyID, 2, 3);
                AudioUnitPropertyListenerProc mListenerProc = params.getCompParam!(AudioUnitPropertyListenerProc, 1, 3);
                void* mProcArgs = params.getCompParam!(void*, 0, 3);
                return DoAddPropertyListener(mPropID, mListenerProc, mProcArgs);

            }

            case kAudioUnitRemovePropertyListenerSelect: // 11
            {
                AudioUnitPropertyID propID = params.getCompParam!(AudioUnitPropertyID, 1, 2);
                AudioUnitPropertyListenerProc proc = params.getCompParam!(AudioUnitPropertyListenerProc, 0, 2);
                return DoRemovePropertyListener(propID, proc);
            }

            case kAudioUnitRenderSelect: // 14
            {
                AudioUnitRenderActionFlags* pFlags = params.getCompParam!(AudioUnitRenderActionFlags*, 4, 5)();
                AudioTimeStamp* pTimestamp = params.getCompParam!(AudioTimeStamp*, 3, 5)();
                uint outputBusIdx = params.getCompParam!(uint, 2, 5)();
                uint nFrames = params.getCompParam!(uint, 1, 5)();
                AudioBufferList* pOutBufList = params.getCompParam!(AudioBufferList*, 0, 5)();
                return DoRender(pFlags, pTimestamp, outputBusIdx, nFrames, pOutBufList);
            }

            case kAudioUnitAddRenderNotifySelect: // 15
            {
                AURenderCallback inputProc = params.getCompParam!(AURenderCallback, 1, 2);
                void* inputProcRefCon = params.getCompParam!(void*, 0, 2);
                return DoAddRenderNotify(inputProc, inputProcRefCon);
            }

            case kAudioUnitRemoveRenderNotifySelect: // 16
            {
                AURenderCallback inputProc = params.getCompParam!(AURenderCallback, 1, 2);
                void* inputProcRefCon = params.getCompParam!(void*, 0, 2);
                return DoRemoveRenderNotify(inputProc, inputProcRefCon);
            }

            case kAudioUnitScheduleParametersSelect: // 17
            {
                AudioUnitParameterEvent* pEvent = params.getCompParam!(AudioUnitParameterEvent*, 1, 2);
                uint nEvents = params.getCompParam!(uint, 0, 2);
                return DoScheduleParameters(pEvent, nEvents);
            }

            case kAudioUnitRemovePropertyListenerWithUserDataSelect: // 18
            {
                AudioUnitPropertyID propID = params.getCompParam!(AudioUnitPropertyID, 2, 3);
                AudioUnitPropertyListenerProc proc = params.getCompParam!(AudioUnitPropertyListenerProc, 1, 3);
                void* userData = params.getCompParam!(void*, 0, 3);
                return DoRemovePropertyListenerWithUserData(propID, proc, userData);
            }

            case kMusicDeviceMIDIEventSelect: // 0x0101
            {
                if (!_client.receivesMIDI)
                    return kAudioUnitErr_InvalidProperty;

                int offset = params.getCompParam!(uint, 0, 4);
                ubyte status = cast(ubyte)( params.getCompParam!(uint, 3, 4) );
                ubyte data1 = cast(ubyte)( params.getCompParam!(uint, 2, 4) );
                ubyte data2 = cast(ubyte)( params.getCompParam!(uint, 1, 4) );
                MidiMessage m =  MidiMessage(offset, status, data1, data2);
                _messageQueue.pushBack(makeMidiThreadMessage(m));
                return noErr;
            }

            case kMusicDeviceSysExSelect: // 0x0102
            {
                // MAYDO Not supported yet
                if (!_client.receivesMIDI)
                    return kAudioUnitErr_InvalidProperty;
                return noErr;
            }

            case kMusicDevicePrepareInstrumentSelect: // 0x0103
            {
                if (!_client.receivesMIDI)
                    return kAudioUnitErr_InvalidProperty;
                return noErr;
            }

            case kMusicDeviceReleaseInstrumentSelect: // 0x0104
            {
                if (!_client.receivesMIDI)
                    return kAudioUnitErr_InvalidProperty;
                return noErr;
            }

            case kMusicDeviceStartNoteSelect: // 0x0105
            {
                if (!_client.receivesMIDI)
                    return kAudioUnitErr_InvalidProperty;

                NoteInstanceID* pNoteID = params.getCompParam!(NoteInstanceID*, 2, 5);
                uint offset = params.getCompParam!(uint, 1, 5);
                MusicDeviceNoteParams* pNoteParams = params.getCompParam!(MusicDeviceNoteParams*, 0, 5);
                int noteNumber = cast(int) pNoteParams.mPitch;
                if (noteNumber < 0) noteNumber = 0;
                if (noteNumber > 127) noteNumber = 127;

                int velocity = cast(int) pNoteParams.mVelocity;
                if (velocity < 0) velocity = 0;
                if (velocity > 127) velocity = 127;

                // Note from IPlug: noteID is supposed to be some incremented unique ID,
                // but we're just storing note number in it.
                *pNoteID = noteNumber;

                int channel = 0; // always using channel 0
                MidiMessage m = makeMidiMessageNoteOn(offset, channel, noteNumber, velocity);
                _messageQueue.pushBack(makeMidiThreadMessage(m));
                return noErr;
            }

            case kMusicDeviceStopNoteSelect: // 0x0106
            {
                if (!_client.receivesMIDI)
                    return kAudioUnitErr_InvalidProperty;

                NoteInstanceID noteID = params.getCompParam!(NoteInstanceID, 1, 3);
                uint offset = params.getCompParam!(uint, 0, 3);
                int channel = 0; // always using channel 0
                MidiMessage m = makeMidiMessageNoteOff(offset, channel, noteID);
                _messageQueue.pushBack(makeMidiThreadMessage(m));
                return noErr;
            }

            default:
                return badComponentSelector;
        }
    }

    // individual select actions, to be reused for the Audio Component API

package:

    final OSStatus DoInitialize()
    {
        // Audio processing was switched on.
        _globalMutex.lock();
        scope(exit) _globalMutex.unlock();
        _active = true;

        // We may end up with invalid I/O config at this point (Issue #385).
        // Because validity check were made while _active was false.
        // Check that the connected I/O is actually legal.
        int nIn = numHostChannelsConnected(_inBuses);
        int nOut = numHostChannelsConnected(_outBuses);
        if (!_client.isLegalIO(nIn, nOut))
            return kAudioUnitErr_FailedInitialization;

        return noErr;
    }

    final OSStatus DoUninitialize()
    {
        _globalMutex.lock();
        scope(exit) _globalMutex.unlock();
        _active = false;
        // Nothing to do here
        return noErr;
    }

    final OSStatus DoGetPropertyInfo(AudioUnitPropertyID prop,
                                    AudioUnitScope scope_,
                                    AudioUnitElement elem,
                                    UInt32* pOutDataSize,
                                    Boolean* pOutWritable)
    {
        UInt32 dataSize = 0;
        if (!pOutDataSize)
            pOutDataSize = &dataSize;

        Boolean writeable;
        if (!pOutWritable)
            pOutWritable = &writeable;

        *pOutWritable = false;
        _globalMutex.lock();
        scope(exit) _globalMutex.unlock();
        return getProperty(prop, scope_, elem, pOutDataSize, pOutWritable, null);
    }

    final OSStatus DoGetProperty(AudioUnitPropertyID inID,
                                 AudioUnitScope inScope,
                                 AudioUnitElement inElement,
                                 void* pOutData,
                                 UInt32* pIODataSize)
    {
        UInt32 dataSize = 0;
        if (!pIODataSize)
            pIODataSize = &dataSize;
        Boolean writeable = false;
        _globalMutex.lock();
        scope(exit) _globalMutex.unlock();
        return getProperty(inID, inScope, inElement, pIODataSize, &writeable, pOutData);
    }

    final OSStatus DoSetProperty(AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, const void* pInData, UInt32* pInDataSize)
    {
        _globalMutex.lock();
        scope(exit) _globalMutex.unlock();
        return setProperty(inID, inScope, inElement, pInDataSize, pInData);
    }

    final OSStatus DoAddPropertyListener(AudioUnitPropertyID prop, AudioUnitPropertyListenerProc proc, void* pUserData)
    {
        PropertyListener listener;
        listener.mPropID = prop;
        listener.mListenerProc = proc;
        listener.mProcArgs = pUserData;

        _globalMutex.lock();
        scope(exit) _globalMutex.unlock();
        int n = cast(int)(_propertyListeners.length);
        for (int i = 0; i < n; ++i)
        {
            PropertyListener pListener = _propertyListeners[i];
            if (listener.mPropID == pListener.mPropID && listener.mListenerProc == pListener.mListenerProc)
            {
                return noErr; // already in
            }
        }
        _propertyListeners.pushBack(listener);
        return noErr;
    }

    final OSStatus DoRemovePropertyListener(AudioUnitPropertyID prop, AudioUnitPropertyListenerProc proc)
    {
        PropertyListener listener;
        listener.mPropID = prop;
        listener.mListenerProc = proc;
        _globalMutex.lock();
        scope(exit) _globalMutex.unlock();
        int n = cast(int)(_propertyListeners.length);
        for (int i = 0; i < n; ++i)
        {
            PropertyListener pListener = _propertyListeners[i];
            if (listener.mPropID == pListener.mPropID
                && listener.mListenerProc == pListener.mListenerProc)
            {
                _propertyListeners.removeAndReplaceByLastElement(i);
                break;
            }
        }
        return noErr;
    }

    final OSStatus DoRemovePropertyListenerWithUserData(AudioUnitPropertyID prop, AudioUnitPropertyListenerProc proc, void* pUserData)
    {
        PropertyListener listener;
        listener.mPropID = prop;
        listener.mListenerProc = proc;
        listener.mProcArgs = pUserData;
        _globalMutex.lock();
        scope(exit) _globalMutex.unlock();
        int n = cast(int)(_propertyListeners.length);
        for (int i = 0; i < n; ++i)
        {
            PropertyListener pListener = _propertyListeners[i];
            if (listener.mPropID == pListener.mPropID
                && listener.mListenerProc == pListener.mListenerProc
                && listener.mProcArgs == pListener.mProcArgs)
            {
                _propertyListeners.removeAndReplaceByLastElement(i);
                break;
            }
        }
        return noErr;
    }

    final OSStatus DoAddRenderNotify(AURenderCallback proc, void* pUserData)
    {
        AURenderCallbackStruct acs;
        acs.inputProc = proc;
        acs.inputProcRefCon = pUserData;
        _renderNotifyMutex.lock();
        scope(exit) _renderNotifyMutex.unlock();
        _renderNotify.pushBack(acs);
        return noErr;
    }

    final OSStatus DoRemoveRenderNotify(AURenderCallback proc, void* pUserData)
    {
        AURenderCallbackStruct acs;
        acs.inputProc = proc;
        acs.inputProcRefCon = pUserData;

        _renderNotifyMutex.lock();
        scope(exit) _renderNotifyMutex.unlock();

        int iElem = _renderNotify.indexOf(acs);
        if (iElem != -1)
            _renderNotify.removeAndReplaceByLastElement(iElem);

        return noErr;
    }

    final OSStatus DoGetParameter(AudioUnitParameterID param, AudioUnitScope scope_, AudioUnitElement elem, AudioUnitParameterValue *value)
    {
        if (!_client.isValidParamIndex(param))
            return kAudioUnitErr_InvalidParameter;
        *value = _client.param(param).getForHost();
        return noErr;
    }

    final OSStatus DoSetParameter(AudioUnitParameterID param, AudioUnitScope scope_, AudioUnitElement elem, AudioUnitParameterValue value, UInt32 bufferOffset)
    {
        // Note: buffer offset is ignored...
        if (!_client.isValidParamIndex(param))
            return kAudioUnitErr_InvalidParameter;
        _client.setParameterFromHost(param, value);
        return noErr;
    }

    final OSStatus DoScheduleParameters(const AudioUnitParameterEvent *pEvent, UInt32 nEvents)
    {
        foreach(ref pE; pEvent[0..nEvents])
        {
            if (pE.eventType == kParameterEvent_Immediate)
            {
                ComponentResult r = DoSetParameter(pE.parameter, pE.scope_, pE.element,
                                                   pE.eventValues.immediate.value,
                                                   pE.eventValues.immediate.bufferOffset);
                if (r != noErr)
                    return r;
            }
        }
        return noErr;
    }

    final OSStatus DoRender(AudioUnitRenderActionFlags* pIOActionFlags,
                            const AudioTimeStamp* pInTimeStamp,
                            UInt32 inOutputBusNumber,
                            UInt32 inNumberFrames,
                            AudioBufferList* pIOData)
    {
        return render(pIOActionFlags, pInTimeStamp, inOutputBusNumber, inNumberFrames, pIOData);
    }

    final OSStatus DoReset(AudioUnitScope scope_, AudioUnitElement elem)
    {
        _messageQueue.pushBack(makeResetStateMessage());
        return noErr;
    }

    final OSStatus DoMIDIEvent(UInt32 inStatus, UInt32 inData1, UInt32 inData2, UInt32 inOffsetSampleFrame)
    {
        printf("DoMIDIEvent\n"); // TODO
        assert(false);
    }

    final OSStatus DoSysEx(const UInt8* pInData, UInt32 inLength)
    {
        printf("DoSysEx\n"); // TODO
        assert(false);
    }

private:
    //
    // </DISPATCHER>
    //

    //
    // GET PROPERTY
    //
    ComponentResult getProperty(AudioUnitPropertyID propID, AudioUnitScope scope_, AudioUnitElement element,
                                UInt32* pDataSize, Boolean* pWriteable, void* pData) nothrow
    {
        version(logDispatcher)
        {
            if (pData)
                printf("GET property %d\n", propID);
            else
                printf("GETINFO property %d\n", propID);
        }

        switch(propID)
        {

            case kAudioUnitProperty_ClassInfo: // 0
            {
                *pDataSize = CFPropertyListRef.sizeof;
                *pWriteable = true;
                if (pData)
                {
                    CFPropertyListRef* pList = cast(CFPropertyListRef*) pData;
                    return readState(pList);
                }
                return noErr;
            }

            case kAudioUnitProperty_MakeConnection: // 1
            {
                if (!isInputOrGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                *pDataSize = cast(uint)AudioUnitConnection.sizeof;
                *pWriteable = true;
                return noErr;
            }

            case kAudioUnitProperty_SampleRate: // 2
            {
                *pDataSize = 8;
                *pWriteable = true;
                if (pData)
                    *(cast(Float64*) pData) = _sampleRate;
                return noErr;
            }

            case kAudioUnitProperty_ParameterList: // 3
            {
                int numParams = cast(int)( _client.params().length );
                int n = (scope_ == kAudioUnitScope_Global) ? numParams : 0;
                *pDataSize = cast(uint)(n * AudioUnitParameterID.sizeof);
                if (pData && n)
                {
                    AudioUnitParameterID* pParamID = cast(AudioUnitParameterID*) pData;
                    for (int i = 0; i < n; ++i, ++pParamID)
                       *pParamID = cast(AudioUnitParameterID) i;
                }
                return noErr;
            }

            case kAudioUnitProperty_ParameterInfo: // 4
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                if (!_client.isValidParamIndex(element))
                    return kAudioUnitErr_InvalidElement;

                *pDataSize = AudioUnitParameterInfo.sizeof;
                if (pData)
                {
                    AudioUnitParameterInfo* pInfo = cast(AudioUnitParameterInfo*)pData;
                    *pInfo = AudioUnitParameterInfo.init;

                    // every parameter in dplug:
                    //  - is readable
                    //  - is writeable (automatable)
                    //  - has a name, that must be CFRelease'd
                    pInfo.flags = kAudioUnitParameterFlag_CFNameRelease |
                                  kAudioUnitParameterFlag_HasCFNameString |
                                  kAudioUnitParameterFlag_IsReadable |
                                  kAudioUnitParameterFlag_IsWritable;

                    Parameter p = _client.param(element);
                    pInfo.cfNameString = toCFString(p.name);
                    stringNCopy(pInfo.name.ptr, 52, p.name);

                    /*if (auto intParam = cast(IntegerParameter)p)
                    {
                        pInfo.unit = kAudioUnitParameterUnit_Indexed;
                        pInfo.minValue = intParam.minValue;
                        pInfo.maxValue = intParam.maxValue;
                        pInfo.defaultValue = intParam.defaultValue;
                    }
                    else if (auto boolParam = cast(BoolParameter)p)
                    {
                        pInfo.minValue = 0;
                        pInfo.maxValue = 1;
                        pInfo.defaultValue = boolParam.getNormalizedDefault();
                        pInfo.unit = kAudioUnitParameterUnit_Boolean;
                    }
                    else*/
                    {
                        // Generic label
                        assert(p.label !is null);
                        /*if (p.label != "")
                        {
                            pInfo.unitName = toCFString(p.label);
                            pInfo.unit = kAudioUnitParameterUnit_CustomUnit;
                        }
                        else
                        {
                            pInfo.unit = kAudioUnitParameterUnit_Generic;
                        }*/

                        // Should FloatParameter be mapped?
                        pInfo.unit = kAudioUnitParameterUnit_Generic;
                        pInfo.minValue = 0.0f;
                        pInfo.maxValue = 1.0f;
                        pInfo.defaultValue = p.getNormalizedDefault();
                    }
                    pInfo.clumpID = 0; // parameter groups not supported yet
                }
                return noErr;
            }

            case kAudioUnitProperty_FastDispatch: // 5
            {
                if (isAudioComponentAPI)
                    return kAudioUnitErr_InvalidElement;
                switch (element)
                {
                    case kAudioUnitGetParameterSelect:
                        *pDataSize = AudioUnitGetParameterProc.sizeof;
                        if (pData)
                            *(cast(AudioUnitGetParameterProc*) pData) = &getParamProc;
                        return noErr;

                    case kAudioUnitSetParameterSelect:
                        *pDataSize = AudioUnitSetParameterProc.sizeof;
                        if (pData)
                            *(cast(AudioUnitSetParameterProc*) pData) = &setParamProc;
                        return noErr;

                    case kAudioUnitRenderSelect:
                        *pDataSize = AudioUnitRenderProc.sizeof;
                        if (pData)
                            *(cast(AudioUnitRenderProc*) pData) = &renderProc;
                        return noErr;

                    default:
                        return kAudioUnitErr_InvalidElement;
                }
            }

            case kAudioUnitProperty_StreamFormat: // 8,
            {
                BusChannels* pBus = getBus(scope_, element);
                if (!pBus)
                    return kAudioUnitErr_InvalidElement;

                *pDataSize = AudioStreamBasicDescription.sizeof;
                *pWriteable = true;
                if (pData)
                {
                    int nChannels = pBus.numHostChannels;  // Report how many channels the host has connected.
                    if (nChannels < 0)    // Unless the host hasn't connected any yet, in which case report the default.
                        nChannels = pBus.numPlugChannels;
                    AudioStreamBasicDescription* pASBD = cast(AudioStreamBasicDescription*) pData;

                    pASBD.mSampleRate = _sampleRate;
                    pASBD.mFormatID = kAudioFormatLinearPCM;
                    pASBD.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
                    pASBD.mFramesPerPacket = 1;
                    pASBD.mChannelsPerFrame = nChannels;
                    pASBD.mBitsPerChannel = 8 * AudioSampleType.sizeof;
                    pASBD.mReserved = 0;
                    int bytesPerSample = cast(int)(AudioSampleType.sizeof);
                    pASBD.mBytesPerPacket = bytesPerSample;
                    pASBD.mBytesPerFrame = bytesPerSample;
                }
                return noErr;
            }

            case kAudioUnitProperty_ElementCount: // 11
            {
                *pDataSize = uint.sizeof;
                if (pData)
                {
                    uint n = 0;
                    if (scope_ == kAudioUnitScope_Input)
                        n = cast(uint)_inBuses.length;
                    else if (scope_ == kAudioUnitScope_Output)
                        n = cast(uint)_outBuses.length;
                    else if (scope_ == kAudioUnitScope_Global)
                        n = 1;
                    *(cast(uint*) pData) = n;
                }
                return noErr;
            }

            case kAudioUnitProperty_Latency: // 12
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                *pDataSize = double.sizeof;
                if (pData)
                {
                    double latencySecs = cast(double)(_client.latencySamples(_sampleRate)) / _sampleRate;
                    *(cast(Float64*) pData) = latencySecs;
                }
                return noErr;
            }

            case kAudioUnitProperty_SupportedNumChannels: // 13
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;

                LegalIO[] legalIOs = _client.legalIOs();
                *pDataSize = cast(uint)( legalIOs.length * AUChannelInfo.sizeof );

                if (pData)
                {
                    AUChannelInfo* pChInfo = cast(AUChannelInfo*) pData;
                    foreach(size_t i, ref legalIO; legalIOs)
                    {
                        pChInfo[i].inChannels = cast(short)legalIO.numInputChannels;
                        pChInfo[i].outChannels = cast(short)legalIO.numOutputChannels;
                    }
                }
                return noErr;
            }

            case kAudioUnitProperty_MaximumFramesPerSlice: // 14
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                *pDataSize = uint.sizeof;
                *pWriteable = true;
                if (pData)
                {
                    *(cast(UInt32*) pData) = _maxFrames;
                }
                return noErr;
            }

            case kAudioUnitProperty_ParameterValueStrings: // 16
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                if (!_client.isValidParamIndex(element))
                    return kAudioUnitErr_InvalidElement;

                if (auto intParam = cast(IntegerParameter)_client.param(element))
                {
                    *pDataSize = CFArrayRef.sizeof;
                    if (pData)
                    {
                        int numValues = intParam.numValues();
                        CFMutableArrayRef nameArray = CFArrayCreateMutable(kCFAllocatorDefault, numValues, &kCFTypeArrayCallBacks);

                        if (auto enumParam = cast(EnumParameter)intParam)
                        {
                            for (int i = 0; i < numValues; ++i)
                                CFArrayAppendValue(nameArray, toCFString(enumParam.getValueString(i)));
                        }
                        else
                        {
                            for (int i = 0; i < numValues; ++i)
                                CFArrayAppendValue(nameArray, convertIntToCFString(intParam.minValue + i));
                        }

                        *(cast(CFArrayRef*) pData) = nameArray;
                    }
                    return noErr;
                }
                else
                {
                    *pDataSize = 0;
                    return kAudioUnitErr_InvalidProperty;
                }
            }

            case kAudioUnitProperty_AudioChannelLayout:
            {
                return kAudioUnitErr_InvalidProperty; // MAYDO IPlug says "this seems wrong but works"
            }

            case kAudioUnitProperty_TailTime: // 20
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;

                double tailSize = _client.tailSizeInSeconds();

                *pWriteable = false;
                *pDataSize = Float64.sizeof;

                if (pData)
                {
                    *(cast(Float64*) pData) = cast(double) tailSize;
                }
                return noErr;
            }

            case kAudioUnitProperty_BypassEffect: // 21
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                *pWriteable = true; // always implement a bypass option, whether hard or soft
                *pDataSize = UInt32.sizeof;
                if (pData)
                {
                    bool bypassIsEnabled = (_hardBypassed ? 1 : 0);
                    *(cast(UInt32*) pData) = bypassIsEnabled;
                }
                return noErr;
            }

            case kAudioUnitProperty_LastRenderError:  // 22
            {
                if(!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                *pDataSize = OSStatus.sizeof;
                *pWriteable = false;
                if (pData)
                    *(cast(OSStatus*) pData) = noErr;
                return noErr;
            }

            case kAudioUnitProperty_SetRenderCallback: // 23
            {
                // Not sure why it's not writing anything
                if(!isInputOrGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                if (element >= _inBuses.length)
                    return kAudioUnitErr_InvalidElement;
                *pDataSize = AURenderCallbackStruct.sizeof;
                *pWriteable = true;
                return noErr;
            }

            case kAudioUnitProperty_FactoryPresets: // 24
            {
                *pDataSize = CFArrayRef.sizeof;
                if (pData)
                {
                    auto presetBank = _client.presetBank();
                    int numPresets = presetBank.numPresets();

                    auto callbacks = getCFAUPresetArrayCallBacks();
                    CFMutableArrayRef allPresets = CFArrayCreateMutable(kCFAllocatorDefault, numPresets, &callbacks);

                    if (allPresets == null)
                        return coreFoundationUnknownErr;

                    for (int presetIndex = 0; presetIndex < numPresets; ++presetIndex)
                    {
                        const(char)[] name = presetBank.preset(presetIndex).name;
                        CFStrLocal presetName = CFStrLocal.fromString(name);

                        CFAUPresetRef newPreset = CFAUPresetCreate(kCFAllocatorDefault, presetIndex, presetName);
                        if (newPreset != null)
                        {
                            CFArrayAppendValue(allPresets, newPreset);
                            CFAUPresetRelease(newPreset);
                        }
                    }

                    *(cast(CFMutableArrayRef*) pData) = allPresets;
                  }
                  return noErr;
            }

            case kAudioUnitProperty_HostCallbacks: // 27
            {
                if(!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                *pDataSize = HostCallbackInfo.sizeof;
                *pWriteable = true;
                return noErr;
            }

            case kAudioUnitProperty_ElementName: // 30
            {
                *pDataSize = cast(uint)(CFStringRef.sizeof);
                *pWriteable = false;
                if (!isInputOrOutputScope(scope_))
                    return kAudioUnitErr_InvalidScope;
                BusChannels* pBus = getBus(scope_, element);
                if (!pBus)
                    return kAudioUnitErr_InvalidElement;

                if (pData)
                {
                    *cast(CFStringRef *)pData = toCFString(pBus.label);
                }

                return noErr;
            }

            case kAudioUnitProperty_CocoaUI: // 31
            {
                if ( _client.hasGUI() )
                {
                    *pDataSize = AudioUnitCocoaViewInfo.sizeof;
                    if (pData)
                    {
                        const(char)[] factoryClassName = registerCocoaViewFactory(); // TODO: call unregisterCocoaViewFactory somewhere
                        CFBundleRef pBundle = CFBundleGetMainBundle();
                        CFURLRef url = CFBundleCopyBundleURL(pBundle);
                        AudioUnitCocoaViewInfo* pViewInfo = cast(AudioUnitCocoaViewInfo*) pData;
                        pViewInfo.mCocoaAUViewBundleLocation = url;
                        pViewInfo.mCocoaAUViewClass[0] = toCFString(factoryClassName);
                    }
                    return noErr;
                }
                else
                    return kAudioUnitErr_InvalidProperty;
            }

            case kAudioUnitProperty_SupportedChannelLayoutTags:
            {
                if (isInputOrOutputScope(scope_))
                  return kAudioUnitErr_InvalidScope;

                BusChannels* bus = getBus(scope_, element);
                if (!bus)
                    return kAudioUnitErr_InvalidElement;

                AudioChannelLayoutTag[] tags = bus.getSupportedChannelLayoutTags();

                if (!pData) // GetPropertyInfo
                {
                    *pDataSize = cast(int)(tags.length * AudioChannelLayoutTag.sizeof);
                    *pWriteable = true;
                }
                else
                {
                    AudioChannelLayoutTag* ptags = cast(AudioChannelLayoutTag*)pData;
                    ptags[0..tags.length] = tags[];
                }
                return noErr;
            }

            case kAudioUnitProperty_ParameterIDName: // 34
            {
                *pDataSize = AudioUnitParameterIDName.sizeof;
                if (pData && scope_ == kAudioUnitScope_Global)
                {
                    AudioUnitParameterIDName* pIDName = cast(AudioUnitParameterIDName*) pData;
                    Parameter parameter = _client.param(pIDName.inID);

                    size_t desiredLength = parameter.name.length;
                    if (pIDName.inDesiredLength != -1)
                    {
                        desiredLength = pIDName.inDesiredLength;
                        if (desiredLength > parameter.name.length)
                            desiredLength = parameter.name.length;
                    }

                    pIDName.outName = toCFString(parameter.name[0..desiredLength]);
                }
                return noErr;
            }

            case kAudioUnitProperty_ParameterClumpName: // 35
            {
                *pDataSize = AudioUnitParameterNameInfo.sizeof;
                if (pData && scope_ == kAudioUnitScope_Global)
                {
                    AudioUnitParameterNameInfo* parameterNameInfo = cast(AudioUnitParameterNameInfo *) pData;
                    int clumpId = parameterNameInfo.inID;
                    if (clumpId < 1)
                        return kAudioUnitErr_PropertyNotInUse;

                    // Parameter groups not supported yet, always return the same string
                    parameterNameInfo.outName = toCFString("All params");
                }
                return noErr;
            }

            case kAudioUnitProperty_CurrentPreset: // 28
            case kAudioUnitProperty_PresentPreset: // 36
            {
                *pDataSize = AUPreset.sizeof;
                *pWriteable = true;
                if (pData)
                {
                    auto bank = _client.presetBank();
                    Preset preset = bank.currentPreset();
                    AUPreset* pAUPreset = cast(AUPreset*) pData;
                    pAUPreset.presetNumber = bank.currentPresetIndex();
                    pAUPreset.presetName = toCFString(preset.name);
                }
                return noErr;
            }

            case kAudioUnitProperty_ParameterStringFromValue: // 33
            {
                *pDataSize = AudioUnitParameterStringFromValue.sizeof;
                if (pData && scope_ == kAudioUnitScope_Global)
                {
                    AudioUnitParameterStringFromValue* pSFV = cast(AudioUnitParameterStringFromValue*) pData;
                    Parameter parameter = _client.param(pSFV.inParamID);

                    char[128] buffer;
                    parameter.stringFromNormalizedValue(*pSFV.inValue, buffer.ptr, buffer.length);
                    size_t len = strlen(buffer.ptr);
                    pSFV.outString = toCFString(buffer[0..len]);
                }
                return noErr;
            }

            case kAudioUnitProperty_ParameterValueFromString: // 38
            {
                *pDataSize = AudioUnitParameterValueFromString.sizeof;
                if (pData)
                {
                    AudioUnitParameterValueFromString* pVFS = cast(AudioUnitParameterValueFromString*) pData;
                    if (scope_ == kAudioUnitScope_Global)
                    {
                        Parameter parameter = _client.param(pVFS.inParamID);
                        string paramString = mallocStringFromCFString(pVFS.inString);
                        scope(exit) paramString.freeSlice();
                        double doubleValue;
                        if (parameter.normalizedValueFromString(paramString, doubleValue))
                            pVFS.outValue = doubleValue;
                        else
                            return kAudioUnitErr_InvalidProperty;
                    }
                }
                return noErr;
            }

            case kMusicDeviceProperty_InstrumentCount:
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;

                if (_client.isSynth())
                {
                    *pDataSize = UInt32.sizeof;
                    if (pData)
                        *(cast(UInt32*) pData) = 0; // mono-timbral
                    return noErr;
                }
                else
                    return kAudioUnitErr_InvalidProperty;
            }

            default:
                return kAudioUnitErr_InvalidProperty;
        }
    }

    final bool isAudioComponentAPI()
    {
        return _componentInstance is null;
    }

    final bool isComponentManagerAPI()
    {
        return _componentInstance !is null;
    }

    ComponentResult setProperty(AudioUnitPropertyID propID, AudioUnitScope scope_, AudioUnitElement element,
                                UInt32* pDataSize, const(void)* pData) nothrow
    {
        // inform listeners
        // TODO ACAPI
        foreach (ref listener; _propertyListeners)
            if (listener.mPropID == propID)
                listener.mListenerProc(listener.mProcArgs, _componentInstance, propID, scope_, 0); // always zero?

        version(logDispatcher) printf("SET property %d\n", propID);

        switch(propID)
        {
            case kAudioUnitProperty_ClassInfo:
                return writeState(*(cast(CFPropertyListRef*) pData));

            case kAudioUnitProperty_MakeConnection: // 1
            {
                if (!isInputOrGlobalScope(scope_))
                    return kAudioUnitErr_InvalidScope;

                AudioUnitConnection* pAUC = cast(AudioUnitConnection*) pData;
                if (pAUC.destInputNumber >= _inBusConnections.length)
                    return kAudioUnitErr_InvalidElement;

                InputBusConnection* pInBusConn = &_inBusConnections[pAUC.destInputNumber];
                *pInBusConn = InputBusConnection.init;

                bool negotiatedOK = true;
                if (pAUC.sourceAudioUnit)
                {
                    // Open connection.
                    AudioStreamBasicDescription srcASBD;
                    uint size = cast(uint)(srcASBD.sizeof);

                    // Ask whoever is sending us audio what the format is.
                    negotiatedOK = (AudioUnitGetProperty(pAUC.sourceAudioUnit, kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Output, pAUC.sourceOutputNumber, &srcASBD, &size) == noErr);

                    negotiatedOK &= (setProperty(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
                                                 pAUC.destInputNumber, &size, &srcASBD) == noErr);

                    if (negotiatedOK)
                    {
                        pInBusConn.upstreamUnit = pAUC.sourceAudioUnit;
                        pInBusConn.upstreamBusIdx = pAUC.sourceOutputNumber;

                        // Will the upstream unit give us a fast render proc for input?
                        enum bool enableFastProc = true;

                        static if (enableFastProc)
                        {
                            AudioUnitRenderProc srcRenderProc;
                            size = AudioUnitRenderProc.sizeof;
                            if (AudioUnitGetProperty(pAUC.sourceAudioUnit, kAudioUnitProperty_FastDispatch, kAudioUnitScope_Global, kAudioUnitRenderSelect,
                                                   &srcRenderProc, &size) == noErr)
                            {
                                // Yes, we got a fast render proc, and we also need to store the pointer to the upstream audio unit object.
                                pInBusConn.upstreamRenderProc = srcRenderProc;
                                pInBusConn.upstreamObj = GetComponentInstanceStorage(pAUC.sourceAudioUnit);
                            }
                            // Else no fast render proc, so leave the input bus connection struct's upstream render proc and upstream object empty,
                            // and we will need to make a component call through the component manager to get input data.
                        }
                    }
                    // Else this is a call to close the connection, which we effectively did by clearing the InputBusConnection struct,
                    // which counts as a successful negotiation.
                }
                assessInputConnections();
                return negotiatedOK ? noErr : kAudioUnitErr_InvalidProperty;
            }

            case kAudioUnitProperty_SampleRate: // 2
            {
                _sampleRate = *(cast(Float64*)pData);
                _messageQueue.pushBack(makeResetStateMessage());
                return noErr;
            }

            case kAudioUnitProperty_StreamFormat: // 8
            {
                AudioStreamBasicDescription* pASBD = cast(AudioStreamBasicDescription*) pData;
                int nHostChannels = pASBD.mChannelsPerFrame;
                BusChannels* pBus = getBus(scope_, element);
                if (!pBus)
                    return kAudioUnitErr_InvalidElement;

                pBus.numHostChannels = 0;
                // The connection is OK if the plugin expects the same number of channels as the host is attempting to connect,
                // or if the plugin supports mono channels (meaning it's flexible about how many inputs to expect)
                // and the plugin supports at least as many channels as the host is attempting to connect.
                bool moreThanOneChannel = (nHostChannels > 0);
                bool isLegalIO = checkLegalIO(scope_, element, nHostChannels) == noErr;
                bool compatibleFormat = (pASBD.mFormatID == kAudioFormatLinearPCM) && (pASBD.mFormatFlags & kAudioFormatFlagsNativeFloatPacked);
                bool connectionOK = moreThanOneChannel && isLegalIO && compatibleFormat;

                // Interleaved not supported here

                if (connectionOK)
                {
                    pBus.numHostChannels = nHostChannels;

                    // Eventually change sample rate
                    if (pASBD.mSampleRate > 0.0)
                    {
                        _sampleRate = pASBD.mSampleRate;
                        _messageQueue.pushBack(makeResetStateMessage());
                    }
                }
                return (connectionOK ? noErr : kAudioUnitErr_InvalidProperty);
            }

            case kAudioUnitProperty_MaximumFramesPerSlice: // 14
            {
                _maxFrames = *(cast(uint*)pData);
                _messageQueue.pushBack(makeResetStateMessage());
                return noErr;
            }

            case kAudioUnitProperty_BypassEffect: // 21
            {
                // using hard bypass
                _hardBypassed = (*(cast(UInt32*) pData) != 0);
                _messageQueue.pushBack(makeResetStateMessage());
                return noErr;
            }

            case kAudioUnitProperty_SetRenderCallback: // 23
            {
                if (!isInputScope(scope_))
                    return kAudioUnitErr_InvalidScope;

                if (element >= _inBusConnections.length)
                    return kAudioUnitErr_InvalidElement;

                InputBusConnection* pInBusConn = &_inBusConnections[element];
                *pInBusConn = InputBusConnection.init;
                AURenderCallbackStruct* pCS = cast(AURenderCallbackStruct*) pData;
                if (pCS.inputProc != null)
                    pInBusConn.upstreamRenderCallback = *pCS;
                assessInputConnections();
                return noErr;
            }

            case kAudioUnitProperty_HostCallbacks: // 27
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitScope_Global;
                _hostCallbacks = *(cast(HostCallbackInfo*)pData);
                return noErr;
            }

            case kAudioUnitProperty_CurrentPreset: // 28
            case kAudioUnitProperty_PresentPreset: // 36
            {
                AUPreset* auPreset = cast(AUPreset*)pData;
                int presetIndex = auPreset.presetNumber;


                PresetBank bank = _client.presetBank();
                if (bank.isValidPresetIndex(presetIndex))
                {
                    bank.loadPresetFromHost(presetIndex);
                }
                else if (auPreset.presetName != null)
                {
                    string presetName = mallocStringFromCFString(auPreset.presetName);
                    scope(exit) presetName.freeSlice();
                    bank.addNewDefaultPresetFromHost(presetName);
                }
                return noErr;
            }

            case kAudioUnitProperty_OfflineRender:
                return noErr; // 37

            case kAudioUnitProperty_AUHostIdentifier:            // 46,
            {
                AUHostIdentifier* pHostID = cast(AUHostIdentifier*) pData;
                string dawName = mallocStringFromCFString(pHostID.hostName);
                _daw = identifyDAW(dawName.ptr); // dawName is guaranteed zero-terminated
                dawName.freeSlice();
                return noErr;
            }

            default:
                return kAudioUnitErr_InvalidProperty; // NO-OP, or unsupported
        }
    }

    // From connection information, transmit to client
    void assessInputConnections() nothrow
    {
        foreach (i; 0.._inBuses.length )
        {
            BusChannels* pInBus = &_inBuses[i];
            InputBusConnection* pInBusConn = &_inBusConnections[i];

            pInBus.connected = pInBusConn.isConnected();

            int startChannelIdx = pInBus.plugChannelStartIdx;
            if (pInBus.connected)
            {
                // There's an input connection, so we need to tell the plug to expect however many channels
                // are in the negotiated host stream format.
                if (pInBus.numHostChannels < 0)
                {
                    // The host set up a connection without specifying how many channels in the stream.
                    // Assume the host will send all the channels the plugin asks for, and hope for the best.
                    pInBus.numHostChannels = pInBus.numPlugChannels;
                }
            }
        }

        _messageQueue.pushBack(makeResetStateMessage());
    }

    ComponentResult checkLegalIO(AudioUnitScope scope_, int busIdx, int nChannels) nothrow
    {
        import core.stdc.stdio;

        if (scope_ == kAudioUnitScope_Input)
        {
            int nIn = numHostChannelsConnected(_inBuses, busIdx);
            if (nIn < 0) nIn = 0;
            int nOut = _active ? numHostChannelsConnected(_outBuses) : -1;
            ComponentResult res = _client.isLegalIO(nIn + nChannels, nOut) ? noErr : kAudioUnitErr_InvalidScope;
            return res;
        }
        else if (scope_ == kAudioUnitScope_Output)
        {
            int nIn = _active ? numHostChannelsConnected(_inBuses) : -1;
            int nOut = numHostChannelsConnected(_outBuses, busIdx);
            if (nOut < 0) nOut = 0;
            ComponentResult res = _client.isLegalIO(nIn, nOut + nChannels) ? noErr : kAudioUnitErr_InvalidScope;
            return res;
        }
        else
            return kAudioUnitErr_InvalidScope;
    }

    static int numHostChannelsConnected(BusChannels[] pBuses, int excludeIdx = -1) pure nothrow @nogc
    {
        bool init = false;
        int nCh = 0;
        int n = cast(int)pBuses.length;

        for (int i = 0; i < n; ++i)
        {
            if (i != excludeIdx) // -1 => no bus excluded
            {
                int nHostChannels = pBuses[i].numHostChannels;
                if (nHostChannels >= 0)
                {
                    nCh += nHostChannels;
                    init = true;
                }
            }
        }

        if (init)
            return nCh;
        else
            return -1;
    }

    final AudioThreadMessage makeResetStateMessage() pure const nothrow @nogc
    {
        return AudioThreadMessage(AudioThreadMessage.Type.resetState, _maxFrames, _sampleRate, _hardBypassed);
    }

    // Note: this logic is duplicated in several places in dplug-build
    final int componentType()
    {
        if (_client.isSynth)
            return CCONST('a', 'u', 'm', 'u');
        else if (_client.receivesMIDI)
            return CCONST('a', 'u', 'm', 'f');
        else
            return CCONST('a', 'u', 'f', 'x');
    }

    final int componentSubType()
    {
        char[4] pid = _client.getPluginUniqueID();
        return CCONST(pid[0], pid[1], pid[2], pid[3]);
    }

    final int componentManufacturer()
    {
        char[4] vid = _client.getVendorUniqueID();
        return CCONST(vid[0], vid[1], vid[2], vid[3]);
    }

    // Serialize state
    final ComponentResult readState(CFPropertyListRef* ppPropList) nothrow
    {
        int cType = componentType(),
            cSubType = componentSubType,
            cManufacturer = componentManufacturer();

        CFMutableDictionaryRef pDict = CFDictionaryCreateMutable(null, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        int version_ = _client.getPublicVersion().toAUVersion;
        putNumberInDict(pDict, kAUPresetVersionKey, &version_, kCFNumberSInt32Type);

        putNumberInDict(pDict, kAUPresetTypeKey, &cType, kCFNumberSInt32Type);
        putNumberInDict(pDict, kAUPresetSubtypeKey, &cSubType, kCFNumberSInt32Type);
        putNumberInDict(pDict, kAUPresetManufacturerKey, &cManufacturer, kCFNumberSInt32Type);
        auto presetBank = _client.presetBank();
        putStrInDict(pDict, kAUPresetNameKey, presetBank.currentPreset().name);
        ubyte[] state = presetBank.getStateChunkFromCurrentState();
        putDataInDict(pDict, kAUPresetDataKey, state);
        *ppPropList = pDict;
        return noErr;
    }

    final ComponentResult writeState(CFPropertyListRef ppPropList) nothrow @nogc
    {
        int cType = componentType(),
        cSubType = componentSubType,
        cManufacturer = componentManufacturer();

        int version_, type, subtype, mfr;
        string presetName;

        CFMutableDictionaryRef pDict = cast(CFMutableDictionaryRef)ppPropList;

        if (!getNumberFromDict(pDict, kAUPresetVersionKey, &version_, kCFNumberSInt32Type) ||
            !getNumberFromDict(pDict, kAUPresetTypeKey, &type, kCFNumberSInt32Type) ||
            !getNumberFromDict(pDict, kAUPresetSubtypeKey, &subtype, kCFNumberSInt32Type) ||
            !getNumberFromDict(pDict, kAUPresetManufacturerKey, &mfr, kCFNumberSInt32Type) ||
            !getStrFromDict(pDict, kAUPresetNameKey, presetName) ||
              type != cType ||
              subtype != cSubType ||
              mfr != cManufacturer)
        {
            return kAudioUnitErr_InvalidPropertyValue;
        }

        scope(exit) presetName.freeSlice();

        ubyte[] chunk;
        if (!getDataFromDict(pDict, kAUPresetDataKey, chunk))
        {
            return kAudioUnitErr_InvalidPropertyValue;
        }

        scope(exit) chunk.freeSlice();

        try
        {
            auto presetBank = _client.presetBank();
            presetBank.loadStateChunk(chunk);
        }
        catch(Exception e)
        {
            e.destroyFree();
            return kAudioUnitErr_InvalidPropertyValue;
        }
        return noErr;
    }


    //
    // Render procedure
    //

    final ComponentResult render(AudioUnitRenderActionFlags* pFlags,
                                 const(AudioTimeStamp)* pTimestamp,
                                 uint outputBusIdx,
                                 uint nFrames,
                                 AudioBufferList* pOutBufList) nothrow @nogc
    {
        // GarageBand will happily send NULL pFlags, do not use it

        // Non-existing bus
        if (outputBusIdx > _outBuses.length)
            return kAudioUnitErr_InvalidElement;

        // Invalid timestamp
        if (!(pTimestamp.mFlags & kAudioTimeStampSampleTimeValid))
            return kAudioUnitErr_InvalidPropertyValue;

        // process messages to get newer number of input, samplerate or frame number
        void processMessages(ref float newSamplerate, ref int newMaxFrames, ref bool newBypassed) nothrow @nogc
        {
            // Only the last reset state message is meaningful, so we unwrap them

            AudioThreadMessage msg = void;

            while(_messageQueue.tryPopFront(msg))
            {
                final switch(msg.type) with (AudioThreadMessage.Type)
                {
                    case resetState:
                        // Note: number of input/ouputs is discarded from the message
                        newMaxFrames = msg.maxFrames;
                        newSamplerate = msg.samplerate;
                        newBypassed = msg.bypassed;
                        break;

                    case midi:
                        _client.enqueueMIDIFromHost(msg.midiMessage);

                }
            }
        }
        float newSamplerate = _lastSamplerate;
        int newMaxFrames = _lastMaxFrames;
        processMessages(newSamplerate, newMaxFrames, _lastBypassed);

        // Must fail when given too much frames
        if (nFrames > newMaxFrames)
            return kAudioUnitErr_TooManyFramesToProcess;

        // We'll need scratch buffers to render upstream
        if (newMaxFrames != _lastMaxFrames)
            resizeScratchBuffers(newMaxFrames);


        {
            _renderNotifyMutex.lock();
            scope(exit) _renderNotifyMutex.unlock();

            // pre-render
            if (_renderNotify.length)
            {
                foreach(ref renderCallbackStruct; _renderNotify)
                {
                    AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PreRender;
                    callRenderCallback(renderCallbackStruct, &flags, pTimestamp, outputBusIdx, nFrames, pOutBufList);
                }
            }
        }

        double renderTimestamp = pTimestamp.mSampleTime;

        bool isNewTimestamp = (renderTimestamp != _lastRenderTimestamp);

        // On a novel timestamp, we render upstream (pull) and process audio.
        // Else, just copy the results.
        // We always provide buffers to upstream unit
        int lastConnectedOutputBus = -1;
        {
            // Lock input and output buses
            _globalMutex.lock();
            scope(exit) _globalMutex.unlock();

            if (isNewTimestamp)
            {
                BufferList bufList;
                AudioBufferList* pInBufList = cast(AudioBufferList*) &bufList;

                // Clear inputPointers and fill it:
                //  - with null for unconnected channels
                //  - with a pointer to scratch for connected channels
                _inputPointers[] = null;

                // call render for each upstream units
                foreach(size_t inputBusIdx, ref pInBus; _inBuses)
                {
                    InputBusConnection* pInBusConn = &_inBusConnections[inputBusIdx];

                    if (pInBus.connected)
                    {
                        pInBufList.mNumberBuffers = pInBus.numHostChannels;

                        for (int b = 0; b < pInBufList.mNumberBuffers; ++b)
                        {
                            AudioBuffer* pBuffer = &(pInBufList.mBuffers.ptr[b]);
                            int whichScratch = pInBus.plugChannelStartIdx + b;
                            float* buffer = _inputScratchBuffer[whichScratch].ptr;
                            pBuffer.mData = buffer;
                            pBuffer.mNumberChannels = 1;
                            pBuffer.mDataByteSize = cast(uint)(nFrames * AudioSampleType.sizeof);
                        }
                        AudioUnitRenderActionFlags flags = 0;
                        ComponentResult r = pInBusConn.callUpstreamRender(&flags, pTimestamp, nFrames, pInBufList, cast(int)inputBusIdx);
                        if (r != noErr)
                            return r;   // Something went wrong upstream.

                        // Get back input data pointer, that may have been modified by upstream
                        for (int b = 0; b < pInBufList.mNumberBuffers; ++b)
                        {
                            AudioBuffer* pBuffer = &(pInBufList.mBuffers.ptr[b]);
                            int whichScratch = pInBus.plugChannelStartIdx + b;
                            _inputPointers[whichScratch] = cast(float*)(pBuffer.mData);
                        }
                    }
                }

                _lastRenderTimestamp = renderTimestamp;
            }
            BusChannels* pOutBus = &_outBuses[outputBusIdx];

            // if this bus is not connected OR the number of buffers that the host has given are not equal to the number the bus expects
            // then consider it connected
            if (!(pOutBus.connected) || pOutBus.numHostChannels != pOutBufList.mNumberBuffers)
            {
                pOutBus.connected = true;
            }

            foreach(outBus; _outBuses)
            {
                if(!outBus.connected)
                    break;
                else
                    lastConnectedOutputBus++;
            }

            // assign _outputPointers
            for (int i = 0; i < pOutBufList.mNumberBuffers; ++i)
            {
                int chIdx = pOutBus.plugChannelStartIdx + i;

                AudioSampleType* pData = cast(AudioSampleType*)( pOutBufList.mBuffers.ptr[i].mData );
                if (pData == null)
                {
                    // No output buffers given, we use scratch buffers instead
                    pData = _outputScratchBuffer[chIdx].ptr;
                    pOutBufList.mBuffers.ptr[i].mData = pData;
                }

                _outputPointers[chIdx] = pData;
            }
        }


        if (outputBusIdx == lastConnectedOutputBus)
        {
            // Here we can finally know the real number of input and outputs connected, but not before.
            // We also flatten the pointer arrays
            int newUsedInputs = 0;
            foreach(inputPointer; _inputPointers[])
                if (inputPointer != null)
                    _inputPointersNoGap[newUsedInputs++] = inputPointer;

            int newUsedOutputs = 0;
            foreach(outputPointer; _outputPointers[])
                if (outputPointer != null)
                    _outputPointersNoGap[newUsedOutputs++] = outputPointer;

            // Call client.reset if we do need to call it, and only once.
            bool needReset = (newMaxFrames != _lastMaxFrames || newUsedInputs != _lastUsedInputs ||
                              newUsedOutputs != _lastUsedOutputs || newSamplerate != _lastSamplerate);


            // in case upstream has changed flags
            FPControl fpControl;
            fpControl.initialize();

            if (needReset)
            {
                _client.resetFromHost(newSamplerate, newMaxFrames, newUsedInputs, newUsedOutputs);
                _lastMaxFrames = newMaxFrames;
                _lastSamplerate = newSamplerate;
                _lastUsedInputs = newUsedInputs;
                _lastUsedOutputs = newUsedOutputs;
            }

            if (_lastBypassed)
            {
                // TODO: should delay by latency when bypassed
                int minIO = newUsedInputs;
                if (minIO > newUsedOutputs)
                    minIO = newUsedOutputs;

                for (int i = 0; i < minIO; ++i)
                    _outputPointersNoGap[i][0..nFrames] = _inputPointersNoGap[i][0..nFrames];

                for (int i = minIO; i < newUsedOutputs; ++i)
                    _outputPointersNoGap[i][0..nFrames] = 0;
            }
            else
            {
                TimeInfo timeInfo = getTimeInfo();

                _client.processAudioFromHost(_inputPointersNoGap[0..newUsedInputs],
                                             _outputPointersNoGap[0..newUsedOutputs],
                                             nFrames,
                                             timeInfo);
            }
        }

        // post-render
        if (_renderNotify.length)
        {
            _renderNotifyMutex.lock();
            scope(exit) _renderNotifyMutex.unlock();

            foreach(ref renderCallbackStruct; _renderNotify)
            {
                AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PostRender;
                callRenderCallback(renderCallbackStruct, &flags, pTimestamp, outputBusIdx, nFrames, pOutBufList);
            }
        }

        return noErr;
    }

    // IHostCommand
    public
    {
        final void sendAUEvent(AudioUnitEventType type, ComponentInstance ci, int paramIndex) nothrow @nogc
        {
            AudioUnitEvent auEvent;
            auEvent.mEventType = type;
            auEvent.mArgument.mParameter.mAudioUnit = ci;
            auEvent.mArgument.mParameter.mParameterID = paramIndex;
            auEvent.mArgument.mParameter.mScope = kAudioUnitScope_Global;
            auEvent.mArgument.mParameter.mElement = 0;
            AUEventListenerNotify(null, null, &auEvent);
        }

        override void beginParamEdit(int paramIndex)
        {
            // TODO ACAPI
            sendAUEvent(kAudioUnitEvent_BeginParameterChangeGesture, _componentInstance, paramIndex);
        }

        override void paramAutomate(int paramIndex, float value)
        {
            // TODO ACAPI
            sendAUEvent(kAudioUnitEvent_ParameterValueChange, _componentInstance, paramIndex);
        }

        override void endParamEdit(int paramIndex)
        {
            // TODO ACAPI
            sendAUEvent(kAudioUnitEvent_EndParameterChangeGesture, _componentInstance, paramIndex);
        }

        override bool requestResize(int width, int height)
        {
            return false; // FUTURE implement for AU
        }

        DAW _daw = DAW.Unknown;

        override DAW getDAW()
        {
            return _daw;
        }
    }

    // Host callbacks
    final TimeInfo getTimeInfo() nothrow @nogc
    {
        TimeInfo result;

        auto hostCallbacks = _hostCallbacks;

        if (hostCallbacks.transportStateProc)
        {
            double samplePos = 0.0, loopStartBeat, loopEndBeat;
            Boolean playing, changed, looping;
            hostCallbacks.transportStateProc(hostCallbacks.hostUserData, &playing, &changed, &samplePos,
                                             &looping, &loopStartBeat, &loopEndBeat);
            result.timeInSamples = cast(long)(samplePos + 0.5);
            result.hostIsPlaying = (playing  != 0);
        }

        if (hostCallbacks.beatAndTempoProc)
        {
            double currentBeat = 0.0, tempo = 0.0;
            hostCallbacks.beatAndTempoProc(hostCallbacks.hostUserData, &currentBeat, &tempo);
            if (tempo > 0.0)
                result.tempo = tempo;
        }
        return result;
    }

    package void* openGUIAndReturnCocoaView()
    {
        if (!_client.hasGUI())
            return null;

        if (_isUIOpenedAlready)
            _client.closeGUI();

        _isUIOpenedAlready = true;

        return _client.openGUI(null, null, GraphicsBackend.cocoa);
    }
}


private:

// Helpers for scope
static bool isGlobalScope(AudioUnitScope scope_) pure nothrow @nogc
{
    return (scope_ == kAudioUnitScope_Global);
}

static bool isInputScope(AudioUnitScope scope_) pure nothrow @nogc
{
    return (scope_ == kAudioUnitScope_Input);
}

static bool isOutputScope(AudioUnitScope scope_) pure nothrow @nogc
{
    return (scope_ == kAudioUnitScope_Output);
}

static bool isInputOrGlobalScope(AudioUnitScope scope_) pure nothrow @nogc
{
    return (scope_ == kAudioUnitScope_Input || scope_ == kAudioUnitScope_Global);
}

static bool isInputOrOutputScope(AudioUnitScope scope_) pure nothrow @nogc
{
    return (scope_ == kAudioUnitScope_Input || scope_ == kAudioUnitScope_Output);
}

/// Calls a render callback
static ComponentResult callRenderCallback(ref AURenderCallbackStruct pCB, AudioUnitRenderActionFlags* pFlags, const(AudioTimeStamp)* pTimestamp,
                       UInt32 inputBusIdx, UInt32 nFrames, AudioBufferList* pOutBufList) nothrow @nogc
{
    return pCB.inputProc(pCB.inputProcRefCon, pFlags, pTimestamp, inputBusIdx, nFrames, pOutBufList);
}


extern(C) ComponentResult getParamProc(void* pPlug,
                             AudioUnitParameterID paramID,
                             AudioUnitScope scope_,
                             AudioUnitElement element,
                             AudioUnitParameterValue* pValue) nothrow @nogc
{
    AUClient _this = cast(AUClient)pPlug;
    return _this.DoGetParameter(paramID, scope_, element, pValue);
}

extern(C) ComponentResult setParamProc(void* pPlug,
                             AudioUnitParameterID paramID,
                             AudioUnitScope scope_,
                             AudioUnitElement element,
                             AudioUnitParameterValue value,
                             UInt32 offsetFrames) nothrow @nogc
{
    AUClient _this = cast(AUClient)pPlug;
    return _this.DoSetParameter(paramID, scope_, element, value, offsetFrames);
}

extern(C) ComponentResult renderProc(void* pPlug,
                                     AudioUnitRenderActionFlags* pFlags,
                                     const(AudioTimeStamp)* pTimestamp,
                                     uint outputBusIdx,
                                     uint nFrames,
                                     AudioBufferList* pOutBufList) nothrow @nogc
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    AUClient _this = cast(AUClient)pPlug;
    return _this.render(pFlags, pTimestamp, outputBusIdx, nFrames, pOutBufList);
}


//
// MessageQueue
//


/// A message for the audio thread.
/// Intended to be passed from a non critical thread to the audio thread.
struct AudioThreadMessage
{
    enum Type
    {
        resetState, // reset plugin state, set samplerate and buffer size (samplerate = fParam, buffersize in frames = iParam)
        midi
    }

    this(Type type_, int maxFrames_, float samplerate_, bool bypassed_) pure const nothrow @nogc
    {
        type = type_;
        maxFrames = maxFrames_;
        samplerate = samplerate_;
        bypassed = bypassed_;
    }

    Type type;
    int maxFrames;
    float samplerate;
    bool bypassed;
    MidiMessage midiMessage;
}

AudioThreadMessage makeMidiThreadMessage(MidiMessage midiMessage) pure nothrow @nogc
{
    AudioThreadMessage msg;
    msg.type = AudioThreadMessage.Type.midi;
    msg.midiMessage = midiMessage;
    return msg;
}

/** Four Character Constant (for AEffect->uniqueID) */
private int CCONST(int a, int b, int c, int d) pure nothrow @nogc
{
    return (a << 24) | (b << 16) | (c << 8) | (d << 0);
}
