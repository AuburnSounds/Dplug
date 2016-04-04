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
module dplug.au.client;

import core.stdc.stdio;
import core.stdc.config;

import std.string;

import derelict.carbon;
import gfm.core;
import dplug.core;

import dplug.client.client;
import dplug.client.messagequeue;


template AUEntryPoint(alias ClientClass)
{
    // The entry point names must be kept in sync with names in the .rsrc

    const char[] AUEntryPoint =
    "import derelict.carbon;"
    "extern(C) nothrow ComponentResult dplugAUEntryPoint(ComponentParameters* params, void* pPlug)"
    "{"
        "return audioUnitEntryPoint!" ~ ClientClass.stringof ~ "(params, pPlug);"
    "}"
    "extern(C) nothrow ComponentResult dplugAUCarbonViewEntryPoint(ComponentParameters* params, void* pView)"
    "{"
        "return audioUnitCarbonViewEntry!" ~ ClientClass.stringof ~ "(params, pView);"
    "}";
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

void attachToRuntimeIfNeeded()
{
    import core.thread;
    import dplug.client.dllmain;
    runtimeInitWorkaround15060();
    thread_attachThis();
}

nothrow ComponentResult audioUnitEntryPoint(alias ClientClass)(ComponentParameters* params, void* pPlug)
{
    try
    {
        attachToRuntimeIfNeeded();
        int select = params.what;

        if (select == kComponentOpenSelect)
        {
            DerelictCoreServices.load();
            DerelictAudioUnit.load();

            // Create client and AUClient
            auto client = new ClientClass();
            ComponentInstance instance = params.getCompParam!(ComponentInstance, 0, 1);
            AUClient plugin = mallocEmplace!AUClient(client, instance);
            SetComponentInstanceStorage( instance, cast(Handle)(cast(void*)plugin) );
            return noErr;
        }

     //   writeln("dispatch");

        AUClient auClient = cast(AUClient)pPlug;
        assert(auClient !is null);

        return auClient.dispatcher(select, params);
    }
    catch (Throwable e)
    {
        moreInfoForDebug(e);
        unrecoverableError();
        return noErr;
    }
}

nothrow ComponentResult audioUnitCarbonViewEntry(alias ClientClass)(ComponentParameters* params, void* pView)
{
    debug printf("TODO audioUnitCarbonViewEntry\n");

    // TODO
    return 0;
}

enum AUInputType
{
    notConnected = 0,
    directFastProc,
    directNoFastProc,
    renderCallback
}

/// AU client wrapper
class AUClient
{
public:

    this(Client client, ComponentInstance componentInstance)
    {
        _client = client;
        _componentInstance = componentInstance;

        int queueSize = 256;
        _messageQueue = new AudioThreadQueue(queueSize);

        _maxInputs = _client.maxInputs();
        _maxOutputs = _client.maxOutputs();
        _numParams = cast(int)(client.params().length);

        // dummmy values
        _sampleRate = 44100.0f;
        _maxFrames = 128;
        _maxFramesInProcess = _client.maxFramesInProcess();
        _bypassed = false;

        _usedInputs = _maxInputs;
        _usedOutputs = _maxOutputs;

        // Create input buses
        int numInputBuses = (_maxInputs + 1) / 2;
        _inBuses.length = numInputBuses;
        _inBusConnections.length = numInputBuses;
        foreach(i; 0..numInputBuses)
        {
            int channels = std.algorithm.min(2, numInputBuses - i * 2);
            assert(channels == 1 || channels == 2);
            _inBuses[i].connected = false;
            _inBuses[i].numHostChannels = -1;
            _inBuses[i].numPlugChannels = channels;
            _inBuses[i].plugChannelStartIdx = i * 2;
            _inBuses[i].label = format("input #%d", i);
        }

        // Create output buses

        int numOutputBuses = (_maxInputs + 1) / 2;
        _outBuses.length = numOutputBuses;
        foreach(i; 0..numOutputBuses)
        {
            int channels = std.algorithm.min(2, numOutputBuses - i * 2);
            assert(channels == 1 || channels == 2);
            _outBuses[i].connected = false;
            _outBuses[i].numHostChannels = -1;
            _outBuses[i].numPlugChannels = channels;
            _outBuses[i].plugChannelStartIdx = i * 2;
            _outBuses[i].label = format("output #%d", i);
        }

        _messageQueue.pushBack(makeResetStateMessage(AudioThreadMessage.Type.resetState));

        assessInputConnections();
    }

    ~this()
    {
        debug ensureNotInGC("dplug.au.AUClient");
        _client.destroy();
    }

private:
    ComponentInstance _componentInstance;
    Client _client;
    AudioThreadQueue _messageQueue;

    int _maxInputs, _maxOutputs;
    int _usedInputs, _usedOutputs;
    int _numParams;
    float _sampleRate;
    int _maxFrames;
    int _maxFramesInProcess;

    // When true, buffers gets bypassed
    // TODO: implement bypass
    bool _bypassed;

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
        string label; // pretty name
    }

    BusChannels[] _inBuses;
    BusChannels[] _outBuses;

    BusChannels* getBus(AudioUnitScope scope_, AudioUnitElement busIdx)
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

    struct InputBusConnection
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
    }

    InputBusConnection[] _inBusConnections;


    AURenderCallbackStruct[] _renderNotify;


    //
    // DISPATCHER
    //
    ComponentResult dispatcher(int select, ComponentParameters* params)
    {
        // IPlug locks here.
        // Do we need to do the same?

        switch(select)
        {
            case kComponentVersionSelect: // -4
            {
                int versionMMPR = _client.getPluginVersion();
                int major = versionMMPR / 1000;
                versionMMPR %= 1000;
                int minor = versionMMPR / 100;
                versionMMPR %= 100;
                int patch = versionMMPR / 10;

                // rev not included
                return (major << 16) | (minor << 8) | patch;
            }

            case kComponentCanDoSelect: // -3
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

                    /*
                    case kAudioUnitAddPropertyListenerSelect:
                    case kAudioUnitRemovePropertyListenerSelect:
*/
                    case kAudioUnitAddRenderNotifySelect:
                    case kAudioUnitRemoveRenderNotifySelect:
                        return 1;

                    default:
                        return 0;
                }
            }

            case kComponentCloseSelect: // -2
            {
                this.destroy(); // free all resources except this and the runtime
                return noErr;
            }

            case kAudioUnitInitializeSelect: // 1
            {
                // TODO: should reset parameter values?

                // Audio processing was switched on.
                _messageQueue.pushBack(makeResetStateMessage(AudioThreadMessage.Type.resetState));
                return noErr;
            }

            case kAudioUnitUninitializeSelect: // 2
            {
                // Nothing to do here
                return noErr;
            }

            case kAudioUnitGetPropertyInfoSelect: // 3
            {
                AudioUnitPropertyID propID = params.getCompParam!(AudioUnitPropertyID, 4, 5);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 3, 5);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 2, 5);
                UInt32* pDataSize = params.getCompParam!(UInt32*, 1, 5);
                Boolean* pWriteable = params.getCompParam!(Boolean*, 0, 5);

                UInt32 dataSize = 0;
                if (!pDataSize)
                    pDataSize = &dataSize;

                Boolean writeable;
                if (!pWriteable)
                    pWriteable = &writeable;

                *pWriteable = false;
                return getProperty(propID, scope_, element, pDataSize, pWriteable, null);
            }

            case kAudioUnitGetPropertySelect: // 4
            {
                AudioUnitPropertyID propID = params.getCompParam!(AudioUnitPropertyID, 4, 5);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 3, 5);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 2, 5);
                void* pData = params.getCompParam!(void*, 1, 5);
                UInt32* pDataSize = params.getCompParam!(UInt32*, 0, 5);

                UInt32 dataSize = 0;
                if (!pDataSize)
                    pDataSize = &dataSize;

                Boolean writeable = false;
                return getProperty(propID, scope_, element, pDataSize, &writeable, pData);
            }

            case kAudioUnitSetPropertySelect: // 5
            {
                AudioUnitPropertyID propID = params.getCompParam!(AudioUnitPropertyID, 4, 5);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 3, 5);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 2, 5);
                const(void)* pData = params.getCompParam!(const(void)*, 1, 5);
                UInt32* pDataSize = params.getCompParam!(UInt32*, 0, 5);
                return setProperty(propID, scope_, element, pDataSize, pData);
            }

            case kAudioUnitAddPropertyListenerSelect: // 6
                printf("TODO kAudioUnitAddPropertyListenerSelect\n");
                // TODO
                return badComponentSelector;

            case kAudioUnitRemovePropertyListenerSelect: // 7
                printf("TODO kAudioUnitRemovePropertyListenerSelect\n");
                // TODO
                return badComponentSelector;

            case kAudioUnitRemovePropertyListenerWithUserDataSelect: // 8
                printf("TODO kAudioUnitRemovePropertyListenerWithUserDataSelect\n");
                // TODO
                return badComponentSelector;

            case kAudioUnitAddRenderNotifySelect: // 9
            {
                AURenderCallbackStruct acs;
                acs.inputProc = params.getCompParam!(AURenderCallback, 1, 2);
                acs.inputProcRefCon = params.getCompParam!(void*, 0, 2);
                _renderNotify ~= acs;
                return noErr;
            }

            case kAudioUnitRemoveRenderNotifySelect: // 10
            {
                static auto removeElement(R, N)(R haystack, N needle)
                {
                    import std.algorithm : countUntil, remove;
                    auto index = haystack.countUntil(needle);
                    return (index != -1) ? haystack.remove(index) : haystack;
                }

                AURenderCallbackStruct acs;
                acs.inputProc = params.getCompParam!(AURenderCallback, 1, 2);
                acs.inputProcRefCon = params.getCompParam!(void*, 0, 2);
                _renderNotify = removeElement(_renderNotify, acs);

                return noErr;
            }

            case kAudioUnitGetParameterSelect: // 11
            {
                AudioUnitParameterID paramID = params.getCompParam!(AudioUnitParameterID, 3, 4);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 2, 4);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 1, 4);
                AudioUnitParameterValue* pValue = params.getCompParam!(AudioUnitParameterValue*, 0, 4);
                return getParamProc(cast(void*)this, paramID, scope_, element, pValue);
            }

            case kAudioUnitSetParameterSelect: // 12
            {
                AudioUnitParameterID paramID = params.getCompParam!(AudioUnitParameterID, 4, 5);
                AudioUnitScope scope_ = params.getCompParam!(AudioUnitScope, 3, 5);
                AudioUnitElement element = params.getCompParam!(AudioUnitElement, 2, 5);
                AudioUnitParameterValue value = params.getCompParam!(AudioUnitParameterValue, 1, 5);
                UInt32 offset = params.getCompParam!(UInt32, 0, 5);
                return setParamProc(cast(void*)this, paramID, scope_, element, value, offset);
            }

            case kAudioUnitScheduleParametersSelect: // 13
            {
                AudioUnitParameterEvent* pEvent = params.getCompParam!(AudioUnitParameterEvent*, 1, 2);
                uint nEvents = params.getCompParam!(uint, 0, 2);

                foreach(ref pE; pEvent[0..nEvents])
                {
                    if (pE.eventType == kParameterEvent_Immediate)
                    {
                        ComponentResult r = setParamProc(cast(void*)this, pE.parameter, pE.scope_, pE.element,
                                                         pE.eventValues.immediate.value,
                                                         pE.eventValues.immediate.bufferOffset);
                        if (r != noErr)
                            return r;
                    }
                }
                return noErr;
            }

            case kAudioUnitRenderSelect: // 14
            {
                AudioUnitRenderActionFlags* pFlags = params.getCompParam!(AudioUnitRenderActionFlags*, 4, 5)();
                AudioTimeStamp* pTimestamp = params.getCompParam!(AudioTimeStamp*, 3, 5)();
                uint outputBusIdx = params.getCompParam!(uint, 2, 5)();
                uint nFrames = params.getCompParam!(uint, 1, 5)();
                AudioBufferList* pBufferList = params.getCompParam!(AudioBufferList*, 0, 5)();
                return renderProc(cast(void*)this, pFlags, pTimestamp, outputBusIdx, nFrames, pBufferList);
            }

            case kAudioUnitResetSelect: // 15
            {
                _messageQueue.pushBack(makeResetStateMessage(AudioThreadMessage.Type.resetState));
                return noErr;
            }

            default:
                return badComponentSelector;
        }
    }

    static bool isGlobalScope(AudioUnitScope scope_) pure nothrow @nogc
    {
        return (scope_ == kAudioUnitScope_Global);
    }

    static bool isInputScope(AudioUnitScope scope_) pure nothrow @nogc
    {
        return (scope_ == kAudioUnitScope_Input);
    }

    static bool isInputOrGlobalScope(AudioUnitScope scope_) pure nothrow @nogc
    {
        return (scope_ == kAudioUnitScope_Input || scope_ == kAudioUnitScope_Global);
    }

    //
    // GET PROPERTY
    //
    ComponentResult getProperty(AudioUnitPropertyID propID, AudioUnitScope scope_, AudioUnitElement element,
                                UInt32* pDataSize, Boolean* pWriteable, void* pData)
    {
        //debug printf("GET property %d\n", propID);

        switch(propID)
        {

            case kAudioUnitProperty_ClassInfo: // 0
            {
                *pDataSize = CFPropertyListRef.sizeof;
                *pWriteable = true;
                if (pData)
                {
                    CFPropertyListRef* pList = cast(CFPropertyListRef*) pData;
                    // TODO get state in that list
                    printf("TODO kAudioUnitProperty_ClassInfo get plugin state\n");
                }
                return noErr;
            }

            case kAudioUnitProperty_MakeConnection: // 1
            {
                if (!isInputOrGlobalScope(scope_))
                    return kAudioUnitErr_InvalidProperty;
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
                printf("TODO kAudioUnitProperty_ParameterList\n");
                // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_ParameterInfo: // 4
                printf("TODO kAudioUnitProperty_ParameterInfo\n");
                // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_FastDispatch: // 5
            {
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
                        *pDataSize = AudioUnitSetParameterProc.sizeof;
                        if (pData)
                            *(cast(AudioUnitRenderProc*) pData) = &renderProc;
                        return noErr;

                    default:
                        return kAudioUnitErr_InvalidElement;
                }
            }

            case kAudioUnitProperty_StreamFormat: // 8
                printf("TODO kAudioUnitProperty_StreamFormat\n");
                return kAudioUnitErr_InvalidProperty;

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
                    return kAudioUnitErr_InvalidProperty;
                *pDataSize = double.sizeof;
                if (pData)
                {
                    double latencySecs = cast(double)(_client.latencySamples()) / _sampleRate;
                    *(cast(Float64*) pData) = latencySecs;
                }
                return noErr;
            }

            case kAudioUnitProperty_SupportedNumChannels: // 13
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidProperty;

                LegalIO[] legalIOs = _client.legalIOs();
                *pDataSize = cast(uint)( legalIOs.length * AUChannelInfo.sizeof );

                if (pData)
                {
                    AUChannelInfo* pChInfo = cast(AUChannelInfo*) pData;
                    foreach(int i, ref legalIO; legalIOs)
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
                    return kAudioUnitErr_InvalidProperty;
                *pDataSize = uint.sizeof;
                *pWriteable = true;
                if (pData)
                {
                    *(cast(UInt32*) pData) = _maxFrames;
                }
                return noErr;
            }

            case kAudioUnitProperty_ParameterValueStrings: // 16
                printf("TODO kAudioUnitProperty_ParameterValueStrings\n");
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_GetUIComponentList: // 18
                printf("TODO kAudioUnitProperty_GetUIComponentList\n");
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_AudioChannelLayout:
                printf("TODO kAudioUnitProperty_AudioChannelLayout\n");
                // TODO: IPlug says "TODO: this seems wrong but works"
                return kAudioUnitErr_InvalidPropertyValue;

            case kAudioUnitProperty_TailTime: // 20
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidPropertyValue;
                float tailSize = _client.tailSizeInSeconds();
                *pDataSize = double.sizeof;
                if (pData)
                    *(cast(double*) pData) = tailSize;
                return noErr;
            }

            case kAudioUnitProperty_BypassEffect: // 21
            {
                if (!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidPropertyValue;
                *pWriteable = true;
                *pDataSize = UInt32.sizeof;
                if (pData)
                    *(cast(UInt32*) pData) = (_bypassed ? 1 : 0);
                return noErr;
            }

            case kAudioUnitProperty_LastRenderError:  // 22
            {
                if(!isGlobalScope(scope_))
                    return kAudioUnitErr_InvalidProperty;
                *pDataSize = OSStatus.sizeof;
                if (pData)
                    *(cast(OSStatus*) pData) = noErr;
                return noErr;
            }

            case kAudioUnitProperty_SetRenderCallback: // 23
            {
                // Not sure why it's not writing anything
                if(!isInputOrGlobalScope(scope_))
                    return kAudioUnitErr_InvalidProperty;
                if (element >= _inBuses.length)
                    return kAudioUnitErr_InvalidProperty;
                *pDataSize = AURenderCallbackStruct.sizeof;
                *pWriteable = true;
                return noErr;
            }

            case kAudioUnitProperty_FactoryPresets: // 24
            {
                printf("TODO kAudioUnitProperty_FactoryPresets\n");
                // TODO
                return kAudioUnitErr_InvalidProperty;
            }

            case kAudioUnitProperty_HostCallbacks: // 27
            {
                // Not sure why it's not writing anything
                return kAudioUnitErr_InvalidProperty;
            }

            case kAudioUnitProperty_ElementName: // 30
                printf("TODO kAudioUnitProperty_ElementName\n");
                // TODO, return name of bus
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_CocoaUI: // 31
                printf("TODO kAudioUnitProperty_CocoaUI\n");
                // TODO
                return kAudioUnitErr_InvalidProperty; // no UI

            case kAudioUnitProperty_SupportedChannelLayoutTags:
                // kAudioUnitProperty_SupportedChannelLayoutTags
                // is only needed for multi-output bus instruments
                // TODO when intruments are to be supported
                printf("TODO kAudioUnitProperty_SupportedChannelLayoutTags\n");
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_PresentPreset:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_DependentParameters:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_InputSamplesInOutput:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_ShouldAllocateBuffer:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_FrequencyResponse:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_ParameterHistoryInfo:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_NickName:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_OfflineRender:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_ParameterIDName:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_ParameterStringFromValue:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_ParameterClumpName:
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_ParameterValueFromString:
                return kAudioUnitErr_InvalidProperty;

            default:
                return kAudioUnitErr_InvalidProperty;
        }
    }

    ComponentResult setProperty(AudioUnitPropertyID propID, AudioUnitScope scope_, AudioUnitElement element,
                                UInt32* pDataSize, const(void)* pData)
    {
        // TODO
        //InformListeners(propID, scope);s

        //debug printf("SET property %d\n", propID);

        switch(propID)
        {
            case kAudioUnitProperty_ClassInfo:
                return kAudioUnitErr_InvalidProperty; // TODO?

            case kAudioUnitProperty_MakeConnection: // 1
            {
                if (!isInputOrGlobalScope(scope_))
                    return kAudioUnitErr_InvalidProperty;

                AudioUnitConnection* pAUC = cast(AudioUnitConnection*) pData;
                if (pAUC.destInputNumber >= _inBusConnections.length)
                    return kAudioUnitErr_InvalidProperty;

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


                      /+ TODO fast dispatch

                      // Will the upstream unit give us a fast render proc for input?
                      AudioUnitRenderProc srcRenderProc;
                      size = AudioUnitRenderProc.sizeof;
                      if (AudioUnitGetProperty(pAUC.sourceAudioUnit, kAudioUnitProperty_FastDispatch, kAudioUnitScope_Global, kAudioUnitRenderSelect,
                                               &srcRenderProc, &size) == noErr)
                      {
                        // Yes, we got a fast render proc, and we also need to store the pointer to the upstream audio unit object.
                        pInBusConn->mUpstreamRenderProc = srcRenderProc;
                        pInBusConn->mUpstreamObj = GetComponentInstanceStorage(pAUC->sourceAudioUnit);
                      }
                      // Else no fast render proc, so leave the input bus connection struct's upstream render proc and upstream object empty,
                      // and we will need to make a component call through the component manager to get input data.

                      +/
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
                _messageQueue.pushBack(makeResetStateMessage(AudioThreadMessage.Type.resetState));
                return noErr;
            }

            case kAudioUnitProperty_StreamFormat: // TODO
                printf("TODO kAudioUnitProperty_StreamFormat\n");
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_MaximumFramesPerSlice: // TODO
                printf("TODO kAudioUnitProperty_MaximumFramesPerSlice\n");
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_BypassEffect: // 21
            {
                _bypassed = (*(cast(UInt32*) pData) != 0);
                return noErr;
            }

            case kAudioUnitProperty_SetRenderCallback: // 23
            {
                if (!isInputScope(scope_))
                    return kAudioUnitErr_InvalidProperty;

                if (element >= _inBusConnections.length)
                    return kAudioUnitErr_InvalidProperty;

                InputBusConnection* pInBusConn = &_inBusConnections[element];
                *pInBusConn = InputBusConnection.init;
                AURenderCallbackStruct* pCS = cast(AURenderCallbackStruct*) pData;
                if (pCS.inputProc != null)
                    pInBusConn.upstreamRenderCallback = *pCS;
                assessInputConnections();
                return noErr;
            }

            case kAudioUnitProperty_HostCallbacks: // TODO
                printf("TODO kAudioUnitProperty_HostCallbacks\n");
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_CurrentPreset: // 28
            case kAudioUnitProperty_PresentPreset: // 36
                printf("TODO kAudioUnitProperty_CurrentPreset\n");
                printf("TODO kAudioUnitProperty_PresentPreset\n");
                return kAudioUnitErr_InvalidProperty; // TODO

            case kAudioUnitProperty_OfflineRender:
                return noErr; // 37

            case kAudioUnitProperty_AUHostIdentifier: // TODO
                printf("TODO kAudioUnitProperty_AUHostIdentifier\n");
                return kAudioUnitErr_InvalidProperty;

            default:
                return kAudioUnitErr_InvalidProperty; // NO-OP, or unsupported
        }
    }

    // From connection information, transmit to client
    void assessInputConnections()
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
        // TODO assign _usedInputs and _usedOutputs, and send a message to audio thread
        // maybe implement something similar to IPlug
    }

    AudioThreadMessage makeResetStateMessage(AudioThreadMessage.Type type) pure const nothrow @nogc
    {
        return AudioThreadMessage(type, _maxFrames, _sampleRate, _usedInputs, _usedOutputs);
    }

    // This is copypasta from the VST client unfortunately
    // This part is quite similar
    void processMessages() /* nothrow @nogc */
    {
        // Race condition here.
        // Being a tryPop, there is a tiny chance that we miss a message from the queue.
        // Thankfully it isn't that bad:
        // - we are going to read it next buffer
        // - not clearing the state for a buffer duration does no harm
        // - plugin is initialized first with the maximum amount of input and outputs
        //   so missing such a message isn't that bad: the audio callback will have some outputs that are untouched
        // (a third thread might start a collect while the UI thread takes the queue lock) which is another unlikely race condition.
        // Perhaps it's the one to favor, I don't know.

        AudioThreadMessage msg = void;
        while(_messageQueue.tryPopFront(msg)) // <- here, we have a problem: https://github.com/p0nce/dplug/issues/45
        {
            final switch(msg.type) with (AudioThreadMessage.Type)
            {
                case changedIO:
                {
                    bool success;
                    success = _client.setNumUsedInputs(msg.usedInputs);
                    assert(success);
                    success = _client.setNumUsedOutputs(msg.usedOutputs);
                    assert(success);

                    goto case resetState; // chaning the number of channels probably need to reset state too
                }

                case resetState:
                    //resizeScratchBuffers(msg.maxFrames);

                    // The client need not be aware of the actual size of the buffers,
                    // if it works on sliced buffers.
                    int maxFrameFromClientPOV = msg.maxFrames;
                    if (_maxFramesInProcess != 0 && _maxFramesInProcess < maxFrameFromClientPOV)
                        maxFrameFromClientPOV = _maxFramesInProcess;
                    _client.reset(msg.samplerate, maxFrameFromClientPOV, msg.usedInputs, msg.usedOutputs);
                    break;

                case midi:
                    _client.processMidiMsg(msg.midiMessage);
            }
        }
    }

    // Serialize state
    ComponentResult readState(CFPropertyListRef* ppPropList)
    {
        ComponentDescription cd;
        ComponentResult r = GetComponentInfo(cast(Component) _componentInstance, &cd, null, null, null);
        if (r != noErr)
            return r;

        // TODO!!!

  /+      CFMutableDictionaryRef pDict = CFDictionaryCreateMutable(0, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

        int version_ = _client.getPluginVersion();
        PutNumberInDict(pDict, kAUPresetVersionKey, &version_, kCFNumberSInt32Type);
        PutNumberInDict(pDict, kAUPresetTypeKey, &(cd.componentType), kCFNumberSInt32Type);
        PutNumberInDict(pDict, kAUPresetSubtypeKey, &(cd.componentSubType), kCFNumberSInt32Type);
        PutNumberInDict(pDict, kAUPresetManufacturerKey, &(cd.componentManufacturer), kCFNumberSInt32Type);
        //PutStrInDict(pDict, kAUPresetNameKey, GetPresetName(GetCurrentPresetIdx()));

      ByteChunk chunk;

      if (SerializeState(&chunk))
      {
        PutDataInDict(pDict, kAUPresetDataKey, &chunk);
      }+/

      *ppPropList = null;//pDict;
      return noErr;
    }
}


private:


extern(C) ComponentResult getParamProc(void* pPlug,
                             AudioUnitParameterID paramID,
                             AudioUnitScope scope_,
                             AudioUnitElement element,
                             AudioUnitParameterValue* pValue) nothrow @nogc
{
    AUClient _this = cast(AUClient)pPlug;
    auto client = _this._client;
    if (!client.isValidParamIndex(paramID))
        return kAudioUnitErr_InvalidParameter;
    *pValue = client.param(paramID).getForHost();
    return noErr;
}

extern(C) ComponentResult setParamProc(void* pPlug,
                             AudioUnitParameterID paramID,
                             AudioUnitScope scope_,
                             AudioUnitElement element,
                             AudioUnitParameterValue value,
                             UInt32 offsetFrames) nothrow @nogc
{
    AUClient _this = cast(AUClient)pPlug;
    auto client = _this._client;
    if (!client.isValidParamIndex(paramID))
        return kAudioUnitErr_InvalidParameter;
    client.setParameterFromHost(paramID, value);
    return noErr;
}

extern(C) ComponentResult renderProc(void* pPlug,
                                     AudioUnitRenderActionFlags* pFlags,
                                     const(AudioTimeStamp)* pTimestamp,
                                     uint outputBusIdx,
                                     uint nFrames,
                                     AudioBufferList* pOutBufList) nothrow @nogc
{
    // TODO, it's complicated
    AUClient _this = cast(AUClient)pPlug;
    auto client = _this._client;

    // TODO notify render callbacks
    printf("TODO renderProc\n");

    return noErr;
}

// CoreFoundation helpers

struct CFStrLocal
{
    CFStringRef parent;
    alias parent this;

    @disable this();
    @disable this(this);

    static fromString(string str)
    {
        CFStrLocal s = void;
        s.parent = CFStringCreateWithCString(null, toStringz(str), kCFStringEncodingUTF8);
        return s;
    }

    ~this()
    {
        CFRelease(parent);
    }
}

string copyCFString(CFStringRef cfStr)
{
    auto n = CFStringGetLength(cfStr) + 1;
    char[] buf = new char[n];
    CFStringGetCString(cfStr, buf.ptr, n, kCFStringEncodingUTF8);
    return fromStringz(buf.ptr).idup;
}

void putNumberInDict(CFMutableDictionaryRef pDict, string key, void* pNumber, CFNumberType type)
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);

    CFNumberRef pValue = CFNumberCreate(null, type, pNumber);
    CFDictionarySetValue(pDict, cfKey, pValue);
    CFRelease(pValue);
}

void putStrInDict(CFMutableDictionaryRef pDict, string key, string value)
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);
    CFStrLocal cfValue = CFStrLocal.fromString(value);
    CFDictionarySetValue(pDict, cfKey, cfValue);
}

void putDataInDict(CFMutableDictionaryRef pDict, string key, ubyte[] pChunk)
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);

    CFDataRef pData = CFDataCreate(null, pChunk.ptr, pChunk.length);
    CFDictionarySetValue(pDict, cfKey, pData);
    CFRelease(pData);
}


bool getNumberFromDict(CFDictionaryRef pDict, string key, void* pNumber, CFNumberType type)
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);

    CFNumberRef pValue = cast(CFNumberRef) CFDictionaryGetValue(pDict, cfKey);
    if (pValue)
    {
        CFNumberGetValue(pValue, type, pNumber);
        return true;
    }
    return false;
}

bool getStrFromDict(CFDictionaryRef pDict, string key, out string value)
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);

    CFStringRef pValue = cast(CFStringRef) CFDictionaryGetValue(pDict, cfKey);
    if (pValue)
    {
        value = copyCFString(pValue);
        return true;
    }
    return false;
}

bool getDataFromDict(CFDictionaryRef pDict, string key, ubyte[] pChunk)
{
    CFStrLocal cfKey = CFStrLocal.fromString(key);
    CFDataRef pData = cast(CFDataRef) CFDictionaryGetValue(pDict, cfKey);
    if (pData)
    {
        auto n = CFDataGetLength(pData);
        pChunk.length = n;
        pChunk[0..n] = CFDataGetBytePtr(pData)[0..n];
        return true;
    }
    return false;
}