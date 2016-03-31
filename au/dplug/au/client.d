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


private T getCompParam(T, int Idx, int Num)(ComponentParameters* params)
{
    /*

    Strange, in AU base classes we have something like:

        #if __LP64__
            // comp instance, parameters in forward order
            #define PARAM(_typ, _name, _index, _nparams) \
                _typ _name = *(_typ *)&params->params[_index + 1];
        #else
            // parameters in reverse order, then comp instance
            #define PARAM(_typ, _name, _index, _nparams) \
                _typ _name = *(_typ *)&params->params[_nparams - 1 - _index];
        #endif

    Which is decidedly not the same.

    */

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

        import core.stdc.stdio;
        debug printf("audioUnitEntryPoint select %d\n", select);

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
    // TODO
    return 0;
}

/// AU client wrapper
/// Big TODO
class AUClient
{
public:

    this(Client client, ComponentInstance instance)
    {
        _client = client;
        _instance = instance;

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
    }

    ~this()
    {
        debug ensureNotInGC("dplug.au.AUClient");
        _client.destroy();
    }

private:
    ComponentInstance _instance;
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

                    case kAudioUnitAddRenderNotifySelect:
                    case kAudioUnitRemoveRenderNotifySelect: */
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
            //    debugBreak();
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
                // TODO
                return badComponentSelector;

            case kAudioUnitRemovePropertyListenerSelect: // 7
                // TODO
                return badComponentSelector;

            case kAudioUnitRemovePropertyListenerWithUserDataSelect: // 8
                // TODO
                return badComponentSelector;

            case kAudioUnitAddRenderNotifySelect: // 9
                // TODO
                return badComponentSelector;

            case kAudioUnitRemoveRenderNotifySelect: // 10
                // TODO
                return badComponentSelector;

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
        debug printf("GET property %d\n", propID);
        // TODO
        switch(propID)
        {
            case kAudioUnitProperty_ClassInfo: // 0
                return kAudioUnitErr_InvalidProperty; // TODO?

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
                // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_ParameterInfo: // 4
                // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_FastDispatch: // 5
                // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_StreamFormat: // 8
                // TODO
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
                // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_GetUIComponentList: // 18
                // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_AudioChannelLayout:
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
                // TODO
                return kAudioUnitErr_InvalidProperty;
            }

            case kAudioUnitProperty_HostCallbacks: // 27
            {
                // Not sure why it's not writing anything
                return kAudioUnitErr_InvalidProperty;
            }

            case kAudioUnitProperty_ElementName: // 30
                // TODO, return name of bus
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_CocoaUI: // 31
                // TODO
                return kAudioUnitErr_InvalidProperty; // no UI

            case kAudioUnitProperty_SupportedChannelLayoutTags:
                // kAudioUnitProperty_SupportedChannelLayoutTags
                // is only needed for multi-output bus instruments
                // TODO when intruments are to be supported
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

        debug printf("SET property %d\n", propID);

        switch(propID)
        {
            case kAudioUnitProperty_ClassInfo:
                return kAudioUnitErr_InvalidProperty; // TODO?

            case kAudioUnitProperty_MakeConnection: // 1
                // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_SampleRate: // 2
            {
                _sampleRate = *(cast(Float64*)pData);
                _messageQueue.pushBack(makeResetStateMessage(AudioThreadMessage.Type.resetState));
                return noErr;
            }

            case kAudioUnitProperty_StreamFormat: // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_MaximumFramesPerSlice: // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_BypassEffect: // 21
            {
                _bypassed = (*(cast(UInt32*) pData) != 0);
                return noErr;
            }

            case kAudioUnitProperty_SetRenderCallback: // 23
                return kAudioUnitErr_InvalidProperty; // TODO

            case kAudioUnitProperty_HostCallbacks: // TODO
                return kAudioUnitErr_InvalidProperty;

            case kAudioUnitProperty_CurrentPreset: // 28
            case kAudioUnitProperty_PresentPreset: // 36
                return kAudioUnitErr_InvalidProperty; // TODO

            case kAudioUnitProperty_OfflineRender:
                return noErr; // 37

            case kAudioUnitProperty_AUHostIdentifier: // TODO
                return kAudioUnitErr_InvalidProperty;

            default:
                return kAudioUnitErr_InvalidProperty; // NO-OP, or unsupported
        }
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
                                     AudioBufferList* pOutBufList)
{
    // TODO, it's complicated
    AUClient _this = cast(AUClient)pPlug;
    auto client = _this._client;

    return noErr;
}


