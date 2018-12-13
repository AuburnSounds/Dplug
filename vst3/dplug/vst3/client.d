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
import core.stdc.stdlib: free;
import core.stdc.string: strcmp;

import dplug.window.window;

import dplug.client.client;
import dplug.client.params;
import dplug.client.graphics;
import dplug.client.daw;
import dplug.client.midi;

import dplug.core.nogc;
import dplug.core.sync;
import dplug.core.vec;
import dplug.core.runtime;
import dplug.vst3.ftypes;
import dplug.vst3.ivstaudioprocessor;
import dplug.vst3.ivsteditcontroller;
import dplug.vst3.iplugview;
import dplug.vst3.ivstcomponent;
import dplug.vst3.ipluginbase;
import dplug.vst3.ibstream;
import dplug.vst3.ivstunit;

//debug = logVST3Client;


// Note: the VST3 client assumes shared memory
class VST3Client : IAudioProcessor, IComponent, IEditController, IEditController2, IUnitInfo
{
public:
nothrow:
@nogc:

    this(Client client)
    {
        debug(logVST3Client) debugLog(">VST3Client.this()");
        debug(logVST3Client) scope(exit) debugLog("<VST3Client.this()");
        _client = client;
        _hostCommand = mallocNew!VST3HostCommand(this);
        _client.setHostCommand(_hostCommand);
    }

    ~this()
    {
        debug(logVST3Client) debugLog(">VST3Client.~this()");
        debug(logVST3Client) scope(exit) debugLog("<VST3Client.~this()");
        destroyFree(_client);
        _client = null;

        destroyFree(_hostCommand);
        _hostCommand = null;

        _inputPointers.reallocBuffer(0);
        _outputPointers.reallocBuffer(0);
    }

    // Implements all COM interfaces needed
    mixin QUERY_INTERFACE_SPECIAL_CASE_IUNKNOWN!(IAudioProcessor, 
                                                 IComponent, 
                                                 IEditController, 
                                                 IEditController2, 
                                                 IPluginBase, 
                                                 IUnitInfo);

    mixin IMPLEMENT_REFCOUNT;


    // Implements IPluginBase

    /** The host passes a number of interfaces as context to initialize the Plug-in class.
    @note Extensive memory allocations etc. should be performed in this method rather than in the class' constructor!
    If the method does NOT return kResultOk, the object is released immediately. In this case terminate is not called! */
    extern(Windows) override tresult initialize(FUnknown context)
    {
        debug(logVST3Client) debugLog(">initialize()".ptr);
        debug(logVST3Client) scope(exit) debugLog("<initialize()".ptr);

        setHostApplication(context);

        // Create buses
        int maxInputs = _client.maxInputs();
        int maxOutputs = _client.maxOutputs();
        bool receivesMIDI = _client.receivesMIDI();

        _audioInputs = makeVec!Bus;
        _audioOutputs = makeVec!Bus;
        _eventInputs = makeVec!Bus;

        _sampleRate = -42.0f; // so that a latency changed is sent at next `setupProcessing`

        if (maxInputs)
        {
            Bus busAudioIn;
            busAudioIn.active = true;
            busAudioIn.speakerArrangement = getSpeakerArrangement(maxInputs);
            with(busAudioIn.info)
            {
                mediaType = kAudio;
                direction = kInput;
                channelCount = maxInputs;
                setName("Audio Input"w);
                busType = kMain;
                flags = BusInfo.BusFlags.kDefaultActive;
            }
            _audioInputs.pushBack(busAudioIn);
        }

        if (maxOutputs)
        {
            Bus busAudioOut;
            busAudioOut.active = true;
            busAudioOut.speakerArrangement = getSpeakerArrangement(maxOutputs);
            with(busAudioOut.info)
            {
                mediaType = kAudio;
                direction = kOutput;
                channelCount = maxInputs;
                setName("Audio Output"w);
                busType = kMain;
                flags = BusInfo.BusFlags.kDefaultActive;
            }
            _audioOutputs.pushBack(busAudioOut);
        }

        if (receivesMIDI)
        {
            Bus busEventsIn;
            busEventsIn.active = true;
            busEventsIn.speakerArrangement = 0; // whatever
            with(busEventsIn.info)
            {
                mediaType = kEvent;
                direction = kInput;
                channelCount = 1;
                setName("MIDI Input"w);
                busType = kMain;
                flags = BusInfo.BusFlags.kDefaultActive;
            }
            _eventInputs.pushBack(busEventsIn);
        }

        return kResultOk;
    }

    /** This function is called before the Plug-in is unloaded and can be used for
    cleanups. You have to release all references to any host application interfaces. */
    extern(Windows) override tresult terminate()
    {
        debug(logVST3Client) debugLog("terminate()".ptr);
        debug(logVST3Client) scope(exit) debugLog("terminate()".ptr);
        if (_hostApplication !is null)
        {
            _hostApplication.release();
            _hostApplication = null;
        }
        return kResultOk;
    }

    // Implements IComponent

    extern(Windows) override tresult getControllerClassId (TUID* classId)
    {
        // No need to implement since we "did not succeed to separate component from controller"
        return kNotImplemented;
    }

    extern(Windows) override tresult setIoMode (IoMode mode)
    {
        // Unused in every VST3 SDK example
        return kNotImplemented;
    }

    extern(Windows) override int32 getBusCount (MediaType type, BusDirection dir)
    {
        Vec!Bus* busList = getBusList(type, dir);
        if (busList is null)
            return 0;
        return cast(int)( busList.length );
    }

    extern(Windows) override tresult getBusInfo (MediaType type, BusDirection dir, int32 index, ref BusInfo bus /*out*/)
    {
        Vec!Bus* busList = getBusList(type, dir);
        if (busList is null)
            return kInvalidArgument;
        if (index >= busList.length)
            return kResultFalse;
        bus = (*busList)[index].info;
        return kResultTrue;
    }

    extern(Windows) override tresult getRoutingInfo (ref RoutingInfo inInfo, ref RoutingInfo outInfo /*out*/)
    {
        // Apparently not needed in any SDK examples
        return kNotImplemented;
    }

    extern(Windows) override tresult activateBus (MediaType type, BusDirection dir, int32 index, TBool state)
    {
        debug(logVST3Client) debugLog(">activateBus".ptr);
        debug(logVST3Client) scope(exit) debugLog("<activateBus".ptr);
        Vec!Bus* busList = getBusList(type, dir);
        if (busList is null)
            return kInvalidArgument;
        if (index >= busList.length)
            return kResultFalse;
        (*busList)[index].active = (state != 0);
        return kResultTrue;
    }

    extern(Windows) override tresult setActive (TBool state)
    {
        // In some VST3 examples, this place is used to initialize buffers.
        return kResultOk;
    }

    extern(Windows) override tresult setStateController (IBStream state)
    {
        debug(logVST3Client) debugLog(">setStateController".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setStateController".ptr);

        // TODO deserialize
        return kNotImplemented;
    }

    extern(Windows) override tresult getStateController (IBStream state)
    {
        debug(logVST3Client) debugLog(">getStateController".ptr);
        debug(logVST3Client) scope(exit) debugLog("<getStateController".ptr);
        // TODO serialize
        return kNotImplemented;
    }

    // Implements IAudioProcessor

    extern(Windows) override tresult setBusArrangements (SpeakerArrangement* inputs, int32 numIns, SpeakerArrangement* outputs, int32 numOuts)
    {
        debug(logVST3Client) debugLog(">setBusArrangements".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setBusArrangements".ptr);

        if (numIns < 0 || numOuts < 0)
            return kInvalidArgument;
        int busIn = cast(int) (_audioInputs.length);   // 0 or 1
        int busOut = cast(int) (_audioOutputs.length); // 0 or 1
        if (numIns > busIn || numOuts > busOut)
            return kResultFalse;
        assert(numIns == 0 || numIns == 1);
        assert(numOuts == 0 || numOuts == 1);

        int reqInputs = 0;
        int reqOutputs = 0;

        if (numIns == 1)
            reqInputs = getChannelCount(inputs[0]);
        if (numOuts == 1)
            reqOutputs = getChannelCount(outputs[0]);

        if (!_client.isLegalIO(reqInputs, reqOutputs))
            return kResultFalse;

        if (numIns == 1)
        {
            Bus* pbus = _audioInputs.ptr;
            pbus[0].speakerArrangement = inputs[0];
            pbus[0].info.channelCount = reqInputs;
        }
        if (numOuts == 1)
        {
            Bus* pbus = _audioOutputs.ptr;
            pbus[0].speakerArrangement = outputs[0];
            pbus[0].info.channelCount = reqOutputs;
        }
        return kResultTrue;
    }

    extern(Windows) override tresult getBusArrangement (BusDirection dir, int32 index, ref SpeakerArrangement arr)
    {
        debug(logVST3Client) debugLog(">getBusArrangement".ptr);
        debug(logVST3Client) scope(exit) debugLog("<getBusArrangement".ptr);

        Vec!Bus* busList = getBusList(kAudio, dir);
        if (busList is null || index >= cast(int)(busList.length))
            return kInvalidArgument;
        arr = (*busList)[index].speakerArrangement;
        return kResultTrue;
    }

    extern(Windows) override tresult canProcessSampleSize (int32 symbolicSampleSize)
    {
        return symbolicSampleSize == kSample32 ? kResultTrue : kResultFalse;
    }

    extern(Windows) override uint32 getLatencySamples ()
    {
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
        return _client.latencySamples(44100.0f);//_sampleRateHostPOV);
    }

    extern(Windows) override tresult setupProcessing (ref ProcessSetup setup)
    {
        debug(logVST3Client) debugLog(">setupProcessing".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setupProcessing".ptr);

        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();

        // Find out if this is a new latency, and inform host of latency change if yes.
        // That is an implicit assumption in Dplug that latency is dependent upon sample-rate.
        bool sampleRateChanged = (_sampleRate != setup.sampleRate);
        _sampleRate = setup.sampleRate;
        if (sampleRateChanged && _handler)
            _handler.restartComponent(kLatencyChanged);

        // Pass these new values to the audio thread
        atomicStore(_sampleRateHostPOV, cast(float)(setup.sampleRate));
        atomicStore(_maxSamplesPerBlockHostPOV, setup.maxSamplesPerBlock);
        if (setup.symbolicSampleSize != kSample32)
            return kResultFalse;
        return kResultOk;
    }

    extern(Windows) override tresult setProcessing (TBool state)
    {
        debug(logVST3Client) debugLog(">setProcessing".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setProcessing".ptr);
        if (state)
        {
            atomicStore(_shouldInitialize, true);
        }
        return kResultOk;
    }

    extern(Windows) override tresult process (ref ProcessData data)
    {
        assert(data.symbolicSampleSize == kSample32); // no conversion to 64-bit supported

        // Call initialize if needed
        float newSampleRate = atomicLoad!(MemoryOrder.raw)(_sampleRateHostPOV);
        int newMaxSamplesPerBlock = atomicLoad!(MemoryOrder.raw)(_maxSamplesPerBlockHostPOV);
        // find current number of inputs audio channels
        int numInputs = 0;
        if (data.numInputs != 0) // 0 or 1 output audio bus in a Dplug plugin
            numInputs = data.inputs[0].numChannels;

        // find current number of inputs audio channels
        int numOutputs = 0;
        if (data.numOutputs != 0) // 0 or 1 output audio bus in a Dplug plugin
            numOutputs = data.outputs[0].numChannels;

        bool shouldReinit = cas(&_shouldInitialize, true, false);
        bool sampleRateChanged = (newSampleRate != _sampleRateDSPPOV);
        bool maxSamplesChanged = (newMaxSamplesPerBlock != _maxSamplesPerBlockDSPPOV);
        bool inputChanged = (_numInputChannels != numInputs);
        bool outputChanged = (_numOutputChannels != numOutputs);

        if (shouldReinit || sampleRateChanged || maxSamplesChanged || inputChanged || outputChanged)
        {
            _sampleRateDSPPOV = newSampleRate;
            _maxSamplesPerBlockDSPPOV = newMaxSamplesPerBlock;
            _numInputChannels = numInputs;
            _numOutputChannels = numOutputs;
            _client.resetFromHost(_sampleRateDSPPOV, _maxSamplesPerBlockDSPPOV, _numInputChannels, _numOutputChannels);

            _inputPointers.reallocBuffer(_numInputChannels);
            _outputPointers.reallocBuffer(_numOutputChannels);
        }

        // Gather all I/O pointers
        foreach(chan; 0.._numInputChannels)
            _inputPointers[chan] = data.inputs[0].channelBuffers32[chan];

        foreach(chan; 0.._numOutputChannels)
            _outputPointers[chan] = data.outputs[0].channelBuffers32[chan];

        //
        // Read parameter changes, sets them.
        //
        IParameterChanges paramChanges = data.inputParameterChanges;
        if (paramChanges !is null)
        {
            int numParamChanges = paramChanges.getParameterCount();
            foreach(index; 0..numParamChanges)
            {
                IParamValueQueue queue = paramChanges.getParameterData(index);

                ParamID id = queue.getParameterId();
                int pointCount = queue.getPointCount();
                if (pointCount > 0)
                {
                    int offset;
                    ParamValue value;
                    if (kResultTrue == queue.getPoint(pointCount-1, offset, value))
                    {
                        // Dplug assume parameter do not change over a single buffer, and parameter smoothing is handled
                        // inside the plugin itself. So we take the most future point (inside this buffer) and applies it now.
                        _client.setParameterFromHost(convertParamIDToParamIndex(id), value);
                    }
                }
            }
        }

        // Deal with input MIDI events (only note on and note off supported so far)
        if (data.inputEvents !is null && _client.receivesMIDI())
        {
            IEventList eventList = data.inputEvents;
            int numEvents = eventList.getEventCount();
            foreach(index; 0..numEvents)
            {
                Event e;
                if (eventList.getEvent(index, e) == kResultOk)
                {
                    int offset = e.sampleOffset;
                    switch(e.type)
                    {
                        case Event.EventTypes.kNoteOnEvent:
                        {
                            ubyte velocity = cast(ubyte)(0.5f + 127.0f * e.noteOn.velocity);
                            ubyte noteNumber = cast(ubyte)(e.noteOn.pitch);
                            _client.enqueueMIDIFromHost( makeMidiMessageNoteOn(offset, e.noteOn.channel, noteNumber, velocity));
                            break;
                        }

                        case Event.EventTypes.kNoteOffEvent:
                        {
                            ubyte noteNumber = cast(ubyte)(e.noteOff.pitch);
                            _client.enqueueMIDIFromHost( makeMidiMessageNoteOff(offset, e.noteOff.channel, noteNumber));
                            break;
                        }

                        default:
                            // unsupported events
                    }
                }
            }
        }

        updateTimeInfo(data.processContext, data.numSamples);
        _client.processAudioFromHost(_inputPointers[], _outputPointers[], data.numSamples, _timeInfo);
        return kResultOk;
    }

    void updateTimeInfo(ProcessContext* context, int frames)
    {
        if (context !is null)
        {
            if (context.state & ProcessContext.kTempoValid)
                _timeInfo.tempo = context.tempo;
            _timeInfo.timeInSamples = context.projectTimeSamples;
            _timeInfo.hostIsPlaying = (context.state & ProcessContext.kPlaying) != 0;
        }
        else
        {
            _timeInfo.timeInSamples += frames;
        }
    }

    extern(Windows) override uint32 getTailSamples()
    {
        return cast(int)(0.5f + _client.tailSizeInSeconds() * atomicLoad(_sampleRateHostPOV));
    }

    // Implements IEditController

    extern(Windows) override tresult setComponentState (IBStream state)
    {
        // TODO
        // Why duplicate?
        return kNotImplemented;
    }

    extern(Windows) override tresult setState(IBStream state)
    {
        debug(logVST3Client) debugLog(">setState".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setState".ptr);

        int size;

        // Try to use

        // Try to find current position with seeking to the end
        {
            long curPos;
            if (state.tell(&curPos) != kResultOk)
                return kResultFalse;

            long newPos;
            if (state.seek(0, IBStream.kIBSeekEnd, &newPos) != kResultOk)
                return kResultFalse;

            size = cast(int)(newPos - curPos);

            if (state.seek(curPos, IBStream.kIBSeekSet, null) != kResultOk)
                return kResultFalse;
        }

        ubyte[] chunk = mallocSlice!ubyte(size);
        scope(exit) chunk.freeSlice();

        int bytesRead;
        if (state.read (chunk.ptr, size, &bytesRead) != kResultOk)
            return kResultFalse;

        try
        {
            auto presetBank = _client.presetBank();
            presetBank.loadStateChunk(chunk);
            return kResultTrue;
        }
        catch(Exception e)
        {
            e.destroyFree();
            return kResultFalse;
        }
    }

    extern(Windows) override tresult getState(IBStream state)
    {
        debug(logVST3Client) debugLog(">getState".ptr);
        debug(logVST3Client) scope(exit) debugLog("<getState".ptr);

        auto presetBank = _client.presetBank();
        ubyte[] chunk = presetBank.getStateChunkFromCurrentState();
        scope(exit) free(chunk.ptr);
        return state.write(chunk.ptr, cast(int)(chunk.length), null);
    }

    extern(Windows) override int32 getParameterCount()
    {
        return cast(int)(_client.params.length);
    }

    extern(Windows) override tresult getParameterInfo (int32 paramIndex, ref ParameterInfo info)
    {
        debug(logVST3Client) debugLog(">getParameterInfo".ptr);
        debug(logVST3Client) scope(exit) debugLog("<getParameterInfo".ptr);
        if (!_client.isValidParamIndex(paramIndex))
            return kResultFalse;

        Parameter param = _client.param(paramIndex);

        info.id = convertParamIndexToParamID(paramIndex);
        str8ToStr16(info.title.ptr, param.name, 128);
        str8ToStr16(info.shortTitle.ptr, param.name(), 128);
        str8ToStr16(info.units.ptr, param.label(), 128);
        info.stepCount = 0; // continuous
        info.defaultNormalizedValue = param.getNormalizedDefault();
        info.unitId = 0; // root, unit 0 is always here
        info.flags = ParameterInfo.ParameterFlags.kCanAutomate; // Dplug assumption: all parameters automatable.
        return kResultTrue;
    }

    /** Gets for a given paramID and normalized value its associated string representation. */
    extern(Windows) override tresult getParamStringByValue (ParamID id, ParamValue valueNormalized, String128* string_ )
    {
        debug(logVST3Client) debugLog(">getParamStringByValue".ptr);
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
        {
            return kResultFalse;
        }

        if (string_ is null)
            return kResultFalse;

        Parameter param = _client.param(paramIndex);
        char[128] buf;
        param.stringFromNormalizedValue(valueNormalized, buf.ptr, 128);
        str8ToStr16(string_.ptr, buf.ptr, 128);

        debug(logVST3Client) debugLog("<getParamStringByValue".ptr);
        return kResultTrue;
    }

    /** Gets for a given paramID and string its normalized value. */
    extern(Windows) override tresult getParamValueByString (ParamID id, TChar* string_, ref ParamValue valueNormalized )
    {
        debug(logVST3Client) debugLog(">getParamValueByString".ptr);

        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
        {
            debug(logVST3Client) debugLog("getParamValueByString got a wrong parameter index".ptr);
            return kResultFalse;
        }
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
        {
            debug(logVST3Client) scope(exit) debugLog("<getParamValueByString".ptr);
            return kResultTrue;
        }
        else
        {
            debug(logVST3Client) scope(exit) debugLog("<getParamValueByString".ptr);
            return kResultFalse;
        }
    }

    /** Returns for a given paramID and a normalized value its plain representation
    (for example 90 for 90db - see \ref vst3AutomationIntro). */
    extern(Windows) override ParamValue normalizedParamToPlain (ParamID id, ParamValue valueNormalized)
    {
        debug(logVST3Client) debugLog(">normalizedParamToPlain".ptr);
        debug(logVST3Client) debugLog("<normalizedParamToPlain".ptr);

        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return 0;
        Parameter param = _client.param(paramIndex);
        return valueNormalized; // Note: the host don't need to know we do not deal with normalized values internally
    }

    /** Returns for a given paramID and a plain value its normalized value. (see \ref vst3AutomationIntro) */
    extern(Windows) override ParamValue plainParamToNormalized (ParamID id, ParamValue plainValue)
    {
        debug(logVST3Client) debugLog(">plainParamToNormalized".ptr);
        debug(logVST3Client) scope(exit) debugLog("<plainParamToNormalized".ptr);

        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return 0;
        Parameter param = _client.param(paramIndex);
        return plainValue; // Note: the host don't need to know we do not deal with normalized values internally
    }

    /** Returns the normalized value of the parameter associated to the paramID. */
    extern(Windows) override ParamValue getParamNormalized (ParamID id)
    {
        debug(logVST3Client) debugLog(">getParamNormalized".ptr);
        debug(logVST3Client) scope(exit) debugLog("<getParamNormalized".ptr);
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return 0;
        Parameter param = _client.param(paramIndex);
        return param.getForHost();
    }

    /** Sets the normalized value to the parameter associated to the paramID. The controller must never
    pass this value-change back to the host via the IComponentHandler. It should update the according
    GUI element(s) only!*/
    extern(Windows) override tresult setParamNormalized (ParamID id, ParamValue value)
    {
        debug(logVST3Client) debugLog(">setParamNormalized".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setParamNormalized".ptr);
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return kResultFalse;
        Parameter param = _client.param(paramIndex);
        param.setFromHost(value);
        return kResultTrue;
    }

    /** Gets from host a handler. */
    extern(Windows) override tresult setComponentHandler (IComponentHandler handler)
    {
        debug(logVST3Client) debugLog(">setComponentHandler".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setComponentHandler".ptr);
        if (_handler is handler)
            return kResultTrue;

        if (_handler)
        {
            _handler.release();
            _handler = null;
        }

        _handler = handler;
        if (_handler)
        {
            _handler.addRef();
        }
        return kResultTrue;
    }

    // view
    /** Creates the editor view of the Plug-in, currently only "editor" is supported, see \ref ViewType.
    The life time of the editor view will never exceed the life time of this controller instance. */
    extern(Windows) override IPlugView createView (FIDString name)
    {
        debug(logVST3Client) debugLog(">createView".ptr);
        debug(logVST3Client) scope(exit) debugLog("<createView".ptr);
        if (name !is null && strcmp(name, "editor") == 0)
            return mallocNew!DplugView(this);
        return null;
    }

    // implements IEditController2

    extern(Windows) override tresult setKnobMode (KnobMode mode)
    {
        return (mode == kLinearMode) ? kResultTrue : kResultFalse;
    }

    extern(Windows) override tresult openHelp (TBool onlyCheck)
    {
        return kResultFalse;
    }

    extern(Windows) override tresult openAboutBox (TBool onlyCheck)
    {
        return kResultFalse;
    }


    // implements IUnitInfo

    extern(Windows) override int32 getUnitCount ()
    {
        return 1;
    }

    /** Gets UnitInfo for a given index in the flat list of unit. */
    extern(Windows) override tresult getUnitInfo (int32 unitIndex, ref UnitInfo info /*out*/)
    {
        if (unitIndex == 0)
        {
            info.id = kRootUnitId;
            info.parentUnitId = kNoParentUnitId;
            str8ToStr16(info.name.ptr, "Root Unit".ptr, 128);
            info.programListId = kNoProgramListId;
            return kResultTrue;
        }
        return kResultFalse;
    }

    /** Component intern program structure. */
    /** Gets the count of Program List. */
    extern(Windows) override int32 getProgramListCount ()
    {
        return 1;
    }

    /** Gets for a given index the Program List Info. */
    extern(Windows) override tresult getProgramListInfo (int32 listIndex, ref ProgramListInfo info /*out*/)
    {
        ProgramListInfo result;
        result.id = 0;
        result.programCount = _client.presetBank().numPresets();
        str8ToStr16(result.name.ptr, "Factory Presets".ptr, 128);
        info = result;
        return kResultTrue;
    }

    /** Gets for a given program list ID and program index its program name. */
    extern(Windows) override tresult getProgramName (ProgramListID listId, int32 programIndex, String128* name /*out*/)
    {
        if (listId != 0)
            return kResultFalse;
        auto presetBank = _client.presetBank();
        if (!presetBank.isValidPresetIndex(programIndex))
            return kResultFalse;
        str8ToStr16((*name).ptr, presetBank.preset(programIndex).name, 128);
        return kResultTrue;
    }

    /** Gets for a given program list ID, program index and attributeId the associated attribute value. */
    extern(Windows) override tresult getProgramInfo (ProgramListID listId, int32 programIndex,
                            const(wchar)* attributeId /*in*/, String128* attributeValue /*out*/)
    {
        return kNotImplemented; // I don't understand what these "attributes" could be
    }

    /** Returns kResultTrue if the given program index of a given program list ID supports PitchNames. */
    extern(Windows) override tresult hasProgramPitchNames (ProgramListID listId, int32 programIndex)
    {
        return kResultFalse;
    }

    /** Gets the PitchName for a given program list ID, program index and pitch.
    If PitchNames are changed the Plug-in should inform the host with IUnitHandler::notifyProgramListChange. */
    extern(Windows) override tresult getProgramPitchName (ProgramListID listId, int32 programIndex,
                                 int16 midiPitch, String128* name /*out*/)
    {
        return kResultFalse;
    }

    // units selection --------------------
    /** Gets the current selected unit. */
    extern(Windows) override UnitID getSelectedUnit ()
    {
        return 0;
    }

    /** Sets a new selected unit. */
    extern(Windows) override tresult selectUnit (UnitID unitId)
    {
        return (unitId == 0) ? kResultTrue : kResultFalse;
    }

    /** Gets the according unit if there is an unambiguous relation between a channel or a bus and a unit.
    This method mainly is intended to find out which unit is related to a given MIDI input channel. */
    extern(Windows) override tresult getUnitByBus (MediaType type, BusDirection dir, int32 busIndex,
                                                   int32 channel, ref UnitID unitId /*out*/)
    {
        unitId = 0;
        return kResultTrue;
    }

    /** Receives a preset data stream.
    - If the component supports program list data (IProgramListData), the destination of the data
    stream is the program specified by list-Id and program index (first and second parameter)
    - If the component supports unit data (IUnitData), the destination is the unit specified by the first
    parameter - in this case parameter programIndex is < 0). */
    extern(Windows) tresult setUnitProgramData (int32 listOrUnitId, int32 programIndex, IBStream data)
    {
        return kNotImplemented;
    }

private:
    Client _client;
    IComponentHandler _handler;
    IHostCommand _hostCommand;

    shared(bool) _shouldInitialize = true;

    float _sampleRate;
    shared(float) _sampleRateHostPOV = 44100.0f;
    float _sampleRateDSPPOV = 0.0f;

    shared(int) _maxSamplesPerBlockHostPOV = -1;
    int _maxSamplesPerBlockDSPPOV = -1;

    int _numInputChannels = -1; /// Number of input channels from the DSP point of view
    int _numOutputChannels = -1; /// Number of output channels from the DSP point of view

    float*[] _inputPointers;
    float*[] _outputPointers;

    DAW _daw = DAW.Unknown;
    char[128] _hostName;

    TimeInfo _timeInfo;

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

    // host application reference
    IHostApplication _hostApplication = null;

    void setHostApplication(FUnknown context)
    {
        debug(logVST3Client) debugLog(">setHostApplication".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setHostApplication".ptr);
        IHostApplication hostApplication = null;
        if (context.queryInterface(IHostApplication.iid, cast(void**)(&hostApplication)) != kResultOk)
            hostApplication = null;

        // clean-up _hostApplication former if any
        if (_hostApplication !is null)
        {
            _hostApplication.release();
            _hostApplication = null;
        }

        if (hostApplication !is null)
        {
            hostApplication.addRef();
            _hostApplication = hostApplication;

            // Identify host
            String128 name;
            if (_hostApplication.getName(&name) == kResultOk)
            {
                str16ToStr8(_hostName.ptr, name.ptr, 128);
                _daw = identifyDAW(_hostName.ptr);
            }
        }
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

class DplugView : IPlugView
{
public:
nothrow:
@nogc:

    this(VST3Client vst3Client)
    {
        _vst3Client = vst3Client;
        _graphicsMutex = makeMutex();
    }

    ~this()
    {
    }

    // Implements FUnknown
    mixin QUERY_INTERFACE_SPECIAL_CASE_IUNKNOWN!(IPlugView);
    mixin IMPLEMENT_REFCOUNT;

    // IPlugView

    /** Is Platform UI Type supported
    \param type : IDString of \ref platformUIType */
    // MAYDO: there is considerable coupling with dplug:window here.
    extern(Windows) override tresult isPlatformTypeSupported (FIDString type)
    {
        debug(logVST3Client) debugLog(">isPlatformTypeSupported".ptr);
        debug(logVST3Client) scope(exit) debugLog("<isPlatformTypeSupported".ptr);
        WindowBackend backend;
        if (convertPlatformToWindowBackend(type, &backend))
            return isWindowBackendSupported(backend) ? kResultTrue : kResultFalse;
        return kResultFalse;
    }

    /** The parent window of the view has been created, the (platform) representation of the view
    should now be created as well.
    Note that the parent is owned by the caller and you are not allowed to alter it in any way
    other than adding your own views.
    Note that in this call the Plug-in could call a IPlugFrame::resizeView ()!
    \param parent : platform handle of the parent window or view
    \param type : \ref platformUIType which should be created */
    extern(Windows) tresult attached (void* parent, FIDString type)
    {
        debug(logVST3Client) debugLog(">attached".ptr);
        debug(logVST3Client) scope(exit) debugLog("<attached".ptr);

        if (_vst3Client._client.hasGUI() )
        {
            if (kResultTrue != isPlatformTypeSupported(type))
                return kResultFalse;

            WindowBackend backend = WindowBackend.autodetect;
            if (!convertPlatformToWindowBackend(type, &backend))
                return kResultFalse;
            _graphicsMutex.lock();
            scope(exit) _graphicsMutex.unlock();

            _vst3Client._client.openGUI(parent, null, cast(GraphicsBackend)backend);
            return kResultTrue;
        }
        return kResultFalse;

    }

    /** The parent window of the view is about to be destroyed.
    You have to remove all your own views from the parent window or view. */
    extern(Windows) tresult removed ()
    {
        debug(logVST3Client) debugLog(">removed".ptr);

        if (_vst3Client._client.hasGUI() )
        {
            _graphicsMutex.lock();
            scope(exit) _graphicsMutex.unlock();
            _vst3Client._client.closeGUI();
            debug(logVST3Client) debugLog("<removed".ptr);
            return kResultTrue;
        }
        return kResultFalse;
    }

    /** Handling of mouse wheel. */
    extern(Windows) tresult onWheel (float distance)
    {
        debug(logVST3Client) debugLog(">onWheel".ptr);
        debug(logVST3Client) scope(exit) debugLog("<onWheel".ptr);
        return kResultFalse;
    }

    /** Handling of keyboard events : Key Down.
    \param key : unicode code of key
    \param keyCode : virtual keycode for non ascii keys - see \ref VirtualKeyCodes in keycodes.h
    \param modifiers : any combination of modifiers - see \ref KeyModifier in keycodes.h
    \return kResultTrue if the key is handled, otherwise kResultFalse. \n
    <b> Please note that kResultTrue must only be returned if the key has really been
    handled. </b> Otherwise key command handling of the host might be blocked! */
    extern(Windows) tresult onKeyDown (char16 key, int16 keyCode, int16 modifiers)
    {
        debug(logVST3Client) debugLog(">onKeyDown".ptr);
        debug(logVST3Client) scope(exit) debugLog("<onKeyDown".ptr);
        return kResultFalse;
    }

    /** Handling of keyboard events : Key Up.
    \param key : unicode code of key
    \param keyCode : virtual keycode for non ascii keys - see \ref VirtualKeyCodes in keycodes.h
    \param modifiers : any combination of KeyModifier - see \ref KeyModifier in keycodes.h
    \return kResultTrue if the key is handled, otherwise return kResultFalse. */
    extern(Windows) tresult onKeyUp (char16 key, int16 keyCode, int16 modifiers)
    {
        debug(logVST3Client) debugLog(">onKeyUp".ptr);
        debug(logVST3Client) scope(exit) debugLog("<onKeyUp".ptr);
        return kResultFalse;
    }

    /** Returns the size of the platform representation of the view. */
    extern(Windows) tresult getSize (ViewRect* size)
    {
        debug(logVST3Client) debugLog(">getSize".ptr);
        debug(logVST3Client) scope(exit) debugLog("<getSize".ptr);
        if (!_vst3Client._client.hasGUI())
            return kResultFalse;

        _graphicsMutex.lock();
        scope(exit) _graphicsMutex.unlock();

        int w, h;
        if (_vst3Client._client.getGUISize(&w, &h))
        {
            size.left = 0;
            size.top = 0;
            size.right = w;
            size.bottom = h;
            return kResultTrue;
        }
        return kResultFalse;
    }

    /** Resizes the platform representation of the view to the given rect. Note that if the Plug-in
    *  requests a resize (IPlugFrame::resizeView ()) onSize has to be called afterward. */
    extern(Windows) tresult onSize (ViewRect* newSize)
    {
        return kResultOk;
    }

    /** Focus changed message. */
    extern(Windows) tresult onFocus (TBool state)
    {
        return kResultOk;
    }

    /** Sets IPlugFrame object to allow the Plug-in to inform the host about resizing. */
    extern(Windows) tresult setFrame (IPlugFrame frame)
    {
        debug(logVST3Client) debugLog(">setFrame".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setFrame".ptr);
        _plugFrame = frame;
        return kResultTrue;
    }

    /** Is view sizable by user. */
    extern(Windows) tresult canResize ()
    {
        return kResultFalse;
    }

    /** On live resize this is called to check if the view can be resized to the given rect, if not
    *  adjust the rect to the allowed size. */
    extern(Windows) tresult checkSizeConstraint (ViewRect* rect)
    {
        return kResultTrue;
    }

private:
    VST3Client _vst3Client;
    UncheckedMutex _graphicsMutex;
    IPlugFrame _plugFrame;

    static bool convertPlatformToWindowBackend(FIDString type, WindowBackend* backend)
    {
        if (strcmp(type, kPlatformTypeHWND.ptr) == 0)
        {
            *backend = WindowBackend.win32;
            return true;
        }
        if (strcmp(type, kPlatformTypeNSView.ptr) == 0)
        {
            *backend = WindowBackend.cocoa;
            return true;
        }
        if (strcmp(type, kPlatformTypeX11EmbedWindowID.ptr) == 0)
        {
            *backend = WindowBackend.x11;
            return true;
        }
        return false;
    }
}



// Host commands

class VST3HostCommand : IHostCommand
{
public:
nothrow:
@nogc:

    this(VST3Client vst3Client)
    {
        _vst3Client = vst3Client;
    }

    override void beginParamEdit(int paramIndex)
    {
        auto handler = _vst3Client._handler;
        if (handler)
            handler.beginEdit(convertParamIndexToParamID(paramIndex));
    }

    override void paramAutomate(int paramIndex, float value)
    {
        auto handler = _vst3Client._handler;
        if (handler)
            handler.performEdit(convertParamIndexToParamID(paramIndex), value);
    }

    override void endParamEdit(int paramIndex)
    {
        auto handler = _vst3Client._handler;
        if (handler)
            handler.endEdit(convertParamIndexToParamID(paramIndex));
    }

    override bool requestResize(int width, int height)
    {
        // FUTURE, will need to keep an instance pointer of the current IPluginView
        return false;
    }

    DAW getDAW()
    {
        return _vst3Client._daw;
    }

private:
    VST3Client _vst3Client;
}