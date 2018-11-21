//-----------------------------------------------------------------------------
// Project     : VST SDK
//
// Category    : Helpers
// Filename    : plublic.sdk/source/vst/vstsinglecomponenteffect.h
// Created by  : Steinberg, 03/2008
// Description : Recombination class of Audio Effect and Edit Controller
//
//-----------------------------------------------------------------------------
// LICENSE
// (c) 2018, Steinberg Media Technologies GmbH, All Rights Reserved
//-----------------------------------------------------------------------------
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
//   * Redistributions of source code must retain the above copyright notice, 
//     this list of conditions and the following disclaimer.
//   * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation 
//     and/or other materials provided with the distribution.
//   * Neither the name of the Steinberg Media Technologies nor the names of its
//     contributors may be used to endorse or promote products derived from this 
//     software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
// IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
// INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
// BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE  OF THIS SOFTWARE, EVEN IF ADVISED
// OF THE POSSIBILITY OF SUCH DAMAGE.
//-----------------------------------------------------------------------------

module dplug.vst3.client;

import core.atomic;

import dplug.core.nogc;
import dplug.core.vec;
import dplug.core.runtime;
import dplug.vst3.ftypes;
import dplug.vst3.funknown;
import dplug.vst3.fplatform;
import dplug.vst3.ivstaudioprocessor;
import dplug.vst3.ivsteditcontroller;
import dplug.vst3.iplugview;
import dplug.vst3.ivstcomponent;
import dplug.vst3.ipluginbase;
import dplug.vst3.fstrdefs;
import dplug.vst3.ibstream;

import dplug.client.client;
import dplug.client.params;

// TODO: implement more interfaces 
//     * ComponentBase,
// TODO: call IComponentHandler::restartComponent (kLatencyChanged) after a latency change
// TODO buffer split
// Note: assumes shared memory
class VST3Client : IAudioProcessor, IComponent, IEditController
{
public:
nothrow:
@nogc:

    this(Client client, IUnknown hostCallback)
    {
        _client = client;
        // TODO do something with host callback
    }

    ~this()
    {
        if (_client !is null)
        {
            destroyFree(_client);
            _client = null;
        }
    }

    // Implements FUnknown
    mixin QUERY_INTERFACE_SPECIAL_CASE_IUNKNOWN!(IAudioProcessor, IComponent, IEditController, IPluginBase);
	mixin IMPLEMENT_REFCOUNT;


    // Implements IPluginBase

    /** The host passes a number of interfaces as context to initialize the Plug-in class.
    @note Extensive memory allocations etc. should be performed in this method rather than in the class' constructor!
    If the method does NOT return kResultOk, the object is released immediately. In this case terminate is not called! */
	override tresult initialize(FUnknown context)
    {
        // Create buses
        int maxInputs = _client.maxInputs();
        int maxOutputs = _client.maxOutputs();
        bool receivesMIDI = _client.receivesMIDI();

        _audioInputs = makeVec!Bus;
        _audioOutputs = makeVec!Bus;
        _eventInputs = makeVec!Bus;

        if (maxInputs)
        {
            Bus busAudioIn;
            busAudioIn.active = false;
            busAudioIn.speakerArrangement = 3; // TODO right arrangement for input audio
            with(busAudioIn.info)
            {
                mediaType = kAudio;
                direction = kInput;
                channelCount = maxInputs;
                setName("Audio Input"w);
                busType = kMain;
                uint32 flags = BusInfo.BusFlags.kDefaultActive;
            }
            _audioInputs.pushBack(busAudioIn);
        }

        if (maxOutputs)
        {
            Bus busAudioOut;
            busAudioOut.active = false;
            busAudioOut.speakerArrangement = 3; // TODO right arrangement for output audio
            with(busAudioOut.info)
            {
                mediaType = kAudio;
                direction = kOutput;
                channelCount = maxInputs;
                setName("Audio Output"w);
                busType = kMain;
                uint32 flags = BusInfo.BusFlags.kDefaultActive;
            }
            _audioOutputs.pushBack(busAudioOut);
        }

        if (receivesMIDI)
        {
            Bus busEventsIn;
            busEventsIn.active = false;
            busEventsIn.speakerArrangement = 0; // whatever
            with(busEventsIn.info)
            {
                mediaType = kEvent;
                direction = kInput;
                channelCount = 1;
                setName("MIDI Input"w);
                busType = kMain;
                uint32 flags = BusInfo.BusFlags.kDefaultActive;
            }
            _eventInputs.pushBack(busEventsIn);
        }

        return kResultOk;
    }

	/** This function is called before the Plug-in is unloaded and can be used for
    cleanups. You have to release all references to any host application interfaces. */
	override tresult terminate()
    {
        return kResultOk;
    }

    // Implements IComponent

    override tresult getControllerClassId (TUID* classId)
    {
        // No need to implement since we "did not succeed to separate component from controller"
        return kNotImplemented;
    }

    override tresult setIoMode (IoMode mode)
    {
        // Unused in every VST3 SDK example
        return kNotImplemented;
    }

    override int32 getBusCount (MediaType type, BusDirection dir)
    {
        Vec!Bus* busList = getBusList(type, dir);
        if (busList is null)
            return 0;
        return cast(int)( busList.length );
    }

    override tresult getBusInfo (MediaType type, BusDirection dir, int32 index, ref BusInfo bus /*out*/)
    {
        Vec!Bus* busList = getBusList(type, dir);
        if (busList is null)
            return kInvalidArgument;
        if (index >= busList.length)
            return kResultFalse;
        bus = (*busList)[index].info;
        return kResultTrue;
    }

    override tresult getRoutingInfo (ref RoutingInfo inInfo, ref RoutingInfo outInfo /*out*/)
    {
        // Apparently not needed in any SDK examples
        return kNotImplemented;
    }

    override tresult activateBus (MediaType type, BusDirection dir, int32 index, TBool state)
    {
        Vec!Bus* busList = getBusList(type, dir);
        if (busList is null)
            return kInvalidArgument;
        if (index >= busList.length)
            return kResultFalse;
        (*busList)[index].active = (state != 0);
        return kResultTrue;
    }

    override tresult setActive (TBool state)
    {
        // In some VST3 examples, this place is used to initialize buffers.
        return kResultOk;
    }

    override tresult setState (IBStream state)
    {
        // TODO deserialize
        return kNotImplemented;
    }

    override tresult getState (IBStream state)
    {
        // TODO serialize
        return kNotImplemented;
    }

    // Implements IAudioProcessor
    override tresult setBusArrangements (SpeakerArrangement* inputs, int32 numIns, SpeakerArrangement* outputs, int32 numOuts)
    {
        if (numIns < 0 || numOuts < 0)
            return kInvalidArgument;

        int busIn = cast(int) (_audioInputs.length);
        int busOut = cast(int) (_audioOutputs.length);

        if (numIns > busIn || numOuts > busOut)
            return kResultFalse;

        foreach(index; 0..busIn)
        {
            if (index >= numIns)
                break;
            _audioInputs[index].speakerArrangement = inputs[index];
        }

        foreach(index; 0..busOut)
        {
            if (index >= numOuts)
                break;
            _audioOutputs[index].speakerArrangement = outputs[index];
        }
        return kResultTrue;
    }

    override tresult getBusArrangement (BusDirection dir, int32 index, ref SpeakerArrangement arr)
    {
        Vec!Bus* busList = getBusList(kAudio, dir);
        if (busList is null || index >= cast(int)(busList.length))
            return kInvalidArgument;
        arr = (*busList)[index].speakerArrangement;
        return kResultTrue;
    }

    override tresult canProcessSampleSize (int32 symbolicSampleSize)
    {
        return symbolicSampleSize == kSample32 ? kResultTrue : kResultFalse;
    }

    override uint32 getLatencySamples ()
    {
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
        return _client.latencySamples(_sampleRateHostPOV);
    }

    override tresult setupProcessing (ref ProcessSetup setup)
    {
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
        atomicStore(_sampleRateHostPOV, cast(float)(setup.sampleRate));
        atomicStore(_maxSamplesPerBlockHostPOV, setup.maxSamplesPerBlock);
        if (setup.symbolicSampleSize != kSample32)
            return kResultFalse;
        return kResultOk;
    }

    override tresult setProcessing (TBool state)
    {
        if (state)
        {
            atomicStore(_shouldInitialize, true);
        }
        return kResultOk;
    }

    override tresult process (ref ProcessData data)
    {
        // Call initialize if needed
        float newSampleRate = atomicLoad!(MemoryOrder.raw)(_sampleRateHostPOV);
        int newMaxSamplesPerBlock = atomicLoad!(MemoryOrder.raw)(_maxSamplesPerBlockHostPOV);
        bool shouldReinit = cas(&_shouldInitialize, true, false);
        bool sampleRateChanged = (newSampleRate != _sampleRateDSPPOV);
        bool maxSamplesChanged = (newMaxSamplesPerBlock != _maxSamplesPerBlockDSPPOV);

        if (shouldReinit || sampleRateChanged || maxSamplesChanged)
        {
            _sampleRateDSPPOV = newSampleRate;
            _maxSamplesPerBlockDSPPOV = newMaxSamplesPerBlock;
            _client.resetFromHost(_sampleRateDSPPOV, _maxSamplesPerBlockDSPPOV, 2, 2); // TODO
        }

        // TODO call processFromHost

        return kResultOk;
    }

    override uint32 getTailSamples()
    {
        return cast(int)(0.5f + _client.tailSizeInSeconds() * atomicLoad(_sampleRateHostPOV));
    }


    // Implements IEditController

    tresult setComponentState (IBStream* state)
    {
        // TODO
        // Why duplicate?
        return kNotImplemented;
    }

    tresult setState (IBStream* state)
    {
        // TODO
        // Why duplicate?
        return kNotImplemented;
    }

    tresult getState (IBStream* state)
    {
        // TODO
        // Why duplicate?
        return kNotImplemented;
    }

    int32 getParameterCount()
    {
        return cast(int)(_client.params.length);
    }

    tresult getParameterInfo (int32 paramIndex, ref ParameterInfo info)
    {
        if (!_client.isValidParamIndex(paramIndex))
            return kResultFalse;

        Parameter param = _client.param(paramIndex);
       
        info.id = convertParamIndexToParamID(paramIndex);
        str8ToStr16(info.title.ptr, param.name, 128);
        str8ToStr16(info.shortTitle.ptr, param.name(), 128);
        str8ToStr16(info.units.ptr, param.label(), 128);
        info.stepCount = 0; // continuous
        info.defaultNormalizedValue = param.getNormalizedDefault();
        info.unitId = 0; // root, TODO understand what "units" are for
        info.flags = ParameterInfo.ParameterFlags.kCanAutomate; // Dplug assumption: all parameters automatable.
        return kResultTrue;
    }

    /** Gets for a given paramID and normalized value its associated string representation. */
    tresult getParamStringByValue (ParamID id, ParamValue valueNormalized, String128 string_ )
    {
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return kResultFalse;
        Parameter param = _client.param(paramIndex);
        char[128] buf;
        param.stringFromNormalizedValue(valueNormalized, buf.ptr, 128);
        str8ToStr16(string_.ptr, buf.ptr, 128);
        return kResultTrue;
    }

    /** Gets for a given paramID and string its normalized value. */
    tresult getParamValueByString (ParamID id, TChar* string_, ref ParamValue valueNormalized )
    {
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return kResultFalse;
        Parameter param = _client.param(paramIndex);

        char[128] valueUTF8;
        int len = 0;
        for(int i = 0; i < 128; ++i)
        {
            // Note: no surrogates supported in this UTF-16 to UTF8 conversion
            valueUTF8[i] = cast(char)string_[i];
            if (!string_[i])
                break;
            else
                len++;
        }
        if (param.normalizedValueFromString( valueUTF8[0..len], valueNormalized))
            return kResultTrue;
        else
            return kResultFalse;
    }

    /** Returns for a given paramID and a normalized value its plain representation
    (for example 90 for 90db - see \ref vst3AutomationIntro). */
    ParamValue normalizedParamToPlain (ParamID id, ParamValue valueNormalized)
    {
        // TODO: correct thing to do? SDK examples expose remapped integers and floats
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return 0;
        Parameter param = _client.param(paramIndex);
        return valueNormalized; // Note: the host don't need to know we do not deal with normalized values internally
    }

    /** Returns for a given paramID and a plain value its normalized value. (see \ref vst3AutomationIntro) */
    ParamValue plainParamToNormalized (ParamID id, ParamValue plainValue)
    {
        // TODO: correct thing to do? SDK examples expose remapped integers and floats
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return 0;
        Parameter param = _client.param(paramIndex);
        return plainValue; // Note: the host don't need to know we do not deal with normalized values internally
    }

    /** Returns the normalized value of the parameter associated to the paramID. */
    ParamValue getParamNormalized (ParamID id)
    {
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return 0;
        Parameter param = _client.param(paramIndex);
        return param.getForHost();
    }

    /** Sets the normalized value to the parameter associated to the paramID. The controller must never
    pass this value-change back to the host via the IComponentHandler. It should update the according
    GUI element(s) only!*/
    tresult setParamNormalized (ParamID id, ParamValue value)
    {
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return kResultFalse;
        Parameter param = _client.param(paramIndex);
        param.setFromHost(value);
        return kResultTrue;
    }

    /** Gets from host a handler. */
    tresult setComponentHandler (IComponentHandler* handler)
    {
        // TODO: keep a reference on it
        return kNotImplemented;
    }

    // view
    /** Creates the editor view of the Plug-in, currently only "editor" is supported, see \ref ViewType.
    The life time of the editor view will never exceed the life time of this controller instance. */
    IPlugView createView (FIDString name)
    {
        return null; // TODO
    }


private:
    Client _client;

    shared(bool) _shouldInitialize = true;

    shared(float) _sampleRateHostPOV = 44100.0f;
    float _sampleRateDSPPOV = 0.0f;
    
    shared(int) _maxSamplesPerBlockHostPOV = -1;
    int _maxSamplesPerBlockDSPPOV = -1;

    static struct Bus
    {
        bool active;
        SpeakerArrangement speakerArrangement;
        BusInfo info;
    }

    Vec!Bus _audioInputs;
    Vec!Bus _audioOutputs;
    Vec!Bus _eventInputs;
    Vec!Bus _eventOutputs;

    Vec!Bus* getBusList(MediaType type, BusDirection dir)
    {
        if (type == kAudio)
        {
            if (dir == kInput) return &_audioInputs;
            if (dir == kOutput) return &_audioOutputs;
        }
        else if (type == kEvent)
        {
            if (dir == kInput) return &_eventInputs;
            if (dir == kOutput) return &_eventOutputs;
        }
        return null;
    }
}

private:
nothrow:
pure:
@nogc:

int convertParamIndexToParamID(int index)
{
    return index;
}

int convertParamIDToParamIndex(int index)
{
    return index;
}