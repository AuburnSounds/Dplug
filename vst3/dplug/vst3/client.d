//-----------------------------------------------------------------------------
// LICENSE
// (c) 2005, Steinberg Media Technologies GmbH, All Rights Reserved
// (c) 2018, Guillaume Piolat (contact@auburnsounds.com)
//-----------------------------------------------------------------------------
//
// This Software Development Kit is licensed under the terms of the General
// Public License (GPL) Version 3.
//
// Details of that license can be found at: www.gnu.org/licenses/gpl-3.0.html
//-----------------------------------------------------------------------------
module dplug.vst3.client;

import core.atomic;
import core.stdc.stdlib: free;
import core.stdc.string: strcmp;

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

        // if no preset, pretend to be a continuous parameter
        _presetStepCount = _client.presetBank.numPresets() - 1;
        if (_presetStepCount < 0) _presetStepCount = 0;

        _maxInputs = client.maxInputs();
        _inputScratchBuffers = mallocSlice!(Vec!float)(_maxInputs);
        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffers[i] = makeVec!float();
    }

    ~this()
    {
        debug(logVST3Client) debugLog(">VST3Client.~this()");
        debug(logVST3Client) scope(exit) debugLog("<VST3Client.~this()");
        destroyFree(_client);
        _client = null;

        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffers[i].destroy();
        _inputScratchBuffers.freeSlice();

        _zeroesBuffer.reallocBuffer(0);
        _outputScratchBuffer.reallocBuffer(0);

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

        _sampleRate = -42.0f; // so that a latency change is sent at next `setupProcessing`

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
        Bus* buses = (*busList).ptr;
        buses[index].active = (state != 0);
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
        return kNotImplemented;
    }

    extern(Windows) override tresult getStateController (IBStream state)
    {
        debug(logVST3Client) debugLog(">getStateController".ptr);
        debug(logVST3Client) scope(exit) debugLog("<getStateController".ptr);
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
        return _client.latencySamples(_sampleRateHostPOV);
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
        atomicStore(_sampleRateHostPOV, cast(float)(setup.sampleRate));
        if (sampleRateChanged && _handler)
            _handler.restartComponent(kLatencyChanged);

        // Pass these new values to the audio thread
        atomicStore(_sampleRateAudioThreadPOV, cast(float)(setup.sampleRate));
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
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();

        assert(data.symbolicSampleSize == kSample32); // no conversion to 64-bit supported

        // Call initialize if needed
        float newSampleRate = atomicLoad!(MemoryOrder.raw)(_sampleRateAudioThreadPOV);
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
            resizeScratchBuffers(_maxSamplesPerBlockDSPPOV);

            _inputPointers.reallocBuffer(_numInputChannels);
            _outputPointers.reallocBuffer(_numOutputChannels);
        }

        // Gather all I/O pointers
        foreach(chan; 0.._numInputChannels)
        {
            float* pInput = data.inputs[0].channelBuffers32[chan];

            // May be null in case of deactivated bus, in which case we feed zero instead
            if (pInput is null)
                pInput = _zeroesBuffer.ptr;
            _inputPointers[chan] = pInput;
        }

        foreach(chan; 0.._numOutputChannels)
        {
            float* pOutput = data.outputs[0].channelBuffers32[chan];

            // May be null in case of deactivated bus, in which case we use a garbage buffer instead
            if (pOutput is null)
                pOutput = _outputScratchBuffer.ptr;

            _outputPointers[chan] = pOutput;
        }

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
                        if (id == PARAM_ID_BYPASS)
                        {
                            atomicStore(_bypassed, (value >= 0.5f));
                        }
                        else if (id == PARAM_ID_PROGRAM_CHANGE)
                        {
                            int presetIndex;
                            if (convertPresetParamToPlain(value, &presetIndex))
                            {
                                _client.presetBank.loadPresetFromHost(presetIndex);
                            }
                        }
                        else
                        {
                            // Dplug assume parameter do not change over a single buffer, and parameter smoothing is handled
                            // inside the plugin itself. So we take the most future point (inside this buffer) and applies it now.
                            _client.setParameterFromHost(convertParamIDToClientParamIndex(id), value);
                        }
                    }
                }
            }
        }

        // Deal with input MIDI events (only note on, note off, CC and pitch bend supported so far)
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

                        case Event.EventTypes.kLegacyMIDICCOutEvent:
                        {
                            if (e.midiCCOut.controlNumber <= 127)
                            {
                                _client.enqueueMIDIFromHost(
                                    makeMidiMessage(offset, e.midiCCOut.channel, MidiStatus.controlChange, e.midiCCOut.controlNumber, e.midiCCOut.value));
                            }
                            else if (e.midiCCOut.controlNumber == 129)
                            {
                                _client.enqueueMIDIFromHost(
                                    makeMidiMessage(offset, e.midiCCOut.channel, MidiStatus.pitchBend, e.midiCCOut.value, e.midiCCOut.value2));
                            }
                            break;
                        }

                        default:
                            // unsupported events
                    }
                }
            }
        }

        int frames = data.numSamples;
        updateTimeInfo(data.processContext, frames);

        // Support bypass
        bool bypassed = atomicLoad!(MemoryOrder.raw)(_bypassed);
        if (bypassed)
        {
            int minIO = numInputs;
            if (minIO > numOutputs) minIO = numOutputs;

            for (int chan = 0; chan < minIO; ++chan)
            {
                float* pOut = _outputPointers[chan];
                float* pIn = _inputPointers[chan];
                for(int i = 0; i < frames; ++i)
                {
                    pOut[i] = pIn[i];
                }
            }

            for (int chan = minIO; chan < numOutputs; ++chan)
            {
                float* pOut = _outputPointers[chan];
                for(int i = 0; i < frames; ++i)
                {
                    pOut[i] = 0.0f;
                }
            }
        }
        else
        {
            // Regular processing

            // Hosts like Cubase gives input and output buffer which are identical.
            // This creates problems since Dplug assumes the contrary.
            // Copy the input to scratch buffers to avoid overwrite.
            for (int chan = 0; chan < numInputs; ++chan)
            {
                float* pCopy = _inputScratchBuffers[chan].ptr;
                float* pInput = _inputPointers[chan];
                for(int i = 0; i < frames; ++i)
                {
                    pCopy[i] = pInput[i];
                }
                _inputPointers[chan] = pCopy;
            }

            _client.processAudioFromHost(_inputPointers[0..numInputs],
                                         _outputPointers[0..numOutputs],
                                         frames,
                                         _timeInfo);
        }
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
        return kNotImplemented;
    }

    extern(Windows) override tresult setState(IBStream state)
    {
        debug(logVST3Client) debugLog(">setState".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setState".ptr);

        // Manage VST3 state versionning.
        // First byte of the state is the major VST3 chunk parsing method (we need versionning just in case)
        ubyte version_;
        int bytesRead;
        if (state.read (&version_, 1, &bytesRead) != kResultOk)
            return kResultFalse;
        if (version_ != 0)
            return kResultFalse; // Only version zero is supported

        // (version 0) Second byte of the state is the bypass parameter
        ubyte bypass;
        if (state.read (&bypass, 1, &bytesRead) != kResultOk)
            return kResultFalse;
        atomicStore(_bypassed, bypass != 0);

        // Try to find current position with seeking to the end
        int size;
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

        // First byte of the state is the major VST3 chunk parsing method (we need versionning just in case)
        ubyte CURRENT_VST3_STATE_VERSION = 0;
        if (state.write(&CURRENT_VST3_STATE_VERSION, 1, null) != kResultTrue)
            return kResultFalse;

        // (version 0) Second byte of the state is the bypass parameter
        ubyte bypass = atomicLoad(_bypassed) ? 1 : 0;
        if (state.write(&bypass, 1, null) != kResultTrue)
            return kResultFalse;

        auto presetBank = _client.presetBank();
        ubyte[] chunk = presetBank.getStateChunkFromCurrentState();
        scope(exit) free(chunk.ptr);
        return state.write(chunk.ptr, cast(int)(chunk.length), null);
    }

    extern(Windows) override int32 getParameterCount()
    {
        return cast(int)(_client.params.length) + 2; // 2 because bypass and program change fake parameters
    }

    extern(Windows) override tresult getParameterInfo (int32 paramIndex, ref ParameterInfo info)
    {
        if (paramIndex >= (cast(uint)(_client.params.length) + 2))
            return kResultFalse;

        if (paramIndex == 0)
        {
            info.id = PARAM_ID_BYPASS;
            str8ToStr16(info.title.ptr, "Bypass".ptr, 128);
            str8ToStr16(info.shortTitle.ptr, "Byp".ptr, 128);
            str8ToStr16(info.units.ptr, "".ptr, 128);
            info.stepCount = 1;
            info.defaultNormalizedValue = 0.0f;
            info.unitId = 0; // root, unit 0 is always here
            info.flags = ParameterInfo.ParameterFlags.kCanAutomate
                       | ParameterInfo.ParameterFlags.kIsBypass
                       | ParameterInfo.ParameterFlags.kIsList;
            return kResultTrue;
        }
        else if (paramIndex == 1)
        {
            info.id = PARAM_ID_PROGRAM_CHANGE;
            str8ToStr16(info.title.ptr, "Preset".ptr, 128);
            str8ToStr16(info.shortTitle.ptr, "Pre".ptr, 128);
            str8ToStr16(info.units.ptr, "".ptr, 128);
            info.stepCount = _presetStepCount;
            info.defaultNormalizedValue = 0.0f;
            info.unitId = 0; // root, unit 0 is always here
            info.flags = ParameterInfo.ParameterFlags.kIsProgramChange;
            return kResultTrue;
        }
        else
        {
            info.id = convertVST3ParamIndexToParamID(paramIndex);
            Parameter param = _client.param(convertParamIDToClientParamIndex(info.id));
            str8ToStr16(info.title.ptr, param.name, 128);
            str8ToStr16(info.shortTitle.ptr, param.name(), 128);
            str8ToStr16(info.units.ptr, param.label(), 128);
            info.stepCount = 0; // continuous
            info.defaultNormalizedValue = param.getNormalizedDefault();
            info.unitId = 0; // root, unit 0 is always here
            info.flags = 0;
            if (param.isAutomatable) {
                info.flags |= ParameterInfo.ParameterFlags.kCanAutomate;
            }
            return kResultTrue;
        }
    }

    /** Gets for a given paramID and normalized value its associated string representation. */
    extern(Windows) override tresult getParamStringByValue (ParamID id, ParamValue valueNormalized, String128* string_ )
    {
        debug(logVST3Client) debugLog(">getParamStringByValue".ptr);
        if (id == PARAM_ID_BYPASS)
        {
            if (valueNormalized < 0.5f)
                str8ToStr16(string_.ptr, "No".ptr, 128);
            else
                str8ToStr16(string_.ptr, "Yes".ptr, 128);
            return kResultTrue;
        }

        if (id == PARAM_ID_PROGRAM_CHANGE)
        {
            int presetIndex;
            if (convertPresetParamToPlain(valueNormalized, &presetIndex))
            {
                // Gives back name of preset
                str8ToStr16(string_.ptr, _client.presetBank.preset(presetIndex).name, 128);
                return kResultTrue;
            }
            else
            {
                str8ToStr16(string_.ptr, "None".ptr, 128);
                return kResultTrue;
            }
        }

        int paramIndex = convertParamIDToClientParamIndex(id);
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

        if (id == PARAM_ID_BYPASS || id == PARAM_ID_PROGRAM_CHANGE)
            return kResultFalse; // MAYDO, eventually

        int paramIndex = convertParamIDToClientParamIndex(id);
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

        if (id == PARAM_ID_BYPASS)
        {
            return convertBypassParamToPlain(valueNormalized);
        }
        else if (id == PARAM_ID_PROGRAM_CHANGE)
        {
            int presetIndex = 0;
            convertPresetParamToPlain(valueNormalized, &presetIndex);
            return presetIndex;
        }
        else
        {
            int paramIndex = convertParamIDToClientParamIndex(id);
            if (!_client.isValidParamIndex(paramIndex))
                return 0;
            Parameter param = _client.param(paramIndex);
            return valueNormalized; // Note: the host don't need to know we do not deal with normalized values internally
        }
    }

    /** Returns for a given paramID and a plain value its normalized value. (see \ref vst3AutomationIntro) */
    extern(Windows) override ParamValue plainParamToNormalized (ParamID id, ParamValue plainValue)
    {
        debug(logVST3Client) debugLog(">plainParamToNormalized".ptr);
        debug(logVST3Client) scope(exit) debugLog("<plainParamToNormalized".ptr);

        if (id == PARAM_ID_BYPASS)
        {
            return convertBypassParamToNormalized(plainValue);
        }
        else if (id == PARAM_ID_PROGRAM_CHANGE)
        {
            return convertPresetParamToNormalized(plainValue);
        }
        else
        {
            int paramIndex = convertParamIDToClientParamIndex(id);
            if (!_client.isValidParamIndex(paramIndex))
                return 0;
            Parameter param = _client.param(paramIndex);
            return plainValue; // Note: the host don't need to know we do not deal with normalized values internally
        }
    }

    /** Returns the normalized value of the parameter associated to the paramID. */
    extern(Windows) override ParamValue getParamNormalized (ParamID id)
    {
        debug(logVST3Client) debugLog(">getParamNormalized".ptr);
        debug(logVST3Client) scope(exit) debugLog("<getParamNormalized".ptr);

        if (id == PARAM_ID_BYPASS)
        {
            return atomicLoad(_bypassed) ? 1.0f : 0.0f;
        }
        else if (id == PARAM_ID_PROGRAM_CHANGE)
        {
            int currentPreset = _client.presetBank.currentPresetIndex();
            return convertPresetParamToNormalized(currentPreset);
        }
        else
        {
            int paramIndex = convertParamIDToClientParamIndex(id);
            if (!_client.isValidParamIndex(paramIndex))
                return 0;
            Parameter param = _client.param(paramIndex);
            return param.getForHost();
        }
    }

    /** Sets the normalized value to the parameter associated to the paramID. The controller must never
    pass this value-change back to the host via the IComponentHandler. It should update the according
    GUI element(s) only!*/
    extern(Windows) override tresult setParamNormalized (ParamID id, ParamValue value)
    {
        debug(logVST3Client) debugLog(">setParamNormalized".ptr);
        debug(logVST3Client) scope(exit) debugLog("<setParamNormalized".ptr);

        if (id == PARAM_ID_BYPASS)
        {
            atomicStore(_bypassed, (value >= 0.5f));
            return kResultTrue;
        }
        else if (id == PARAM_ID_PROGRAM_CHANGE)
        {
            int presetIndex;
            if (convertPresetParamToPlain(value, &presetIndex))
            {
                _client.presetBank.loadPresetFromHost(presetIndex);
            }
            return kResultTrue;
        }
        else
        {
            int paramIndex = convertParamIDToClientParamIndex(id);
            if (!_client.isValidParamIndex(paramIndex))
                return kResultFalse;
            Parameter param = _client.param(paramIndex);
            param.setFromHost(value);
            return kResultTrue;
        }
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
        if (!_client.hasGUI)
            return null;
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
            info.programListId = PARAM_ID_PROGRAM_CHANGE;
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
        result.id = PARAM_ID_PROGRAM_CHANGE;
        result.programCount = _client.presetBank().numPresets();
        str8ToStr16(result.name.ptr, "Factory Presets".ptr, 128);
        info = result;
        return kResultTrue;
    }

    /** Gets for a given program list ID and program index its program name. */
    extern(Windows) override tresult getProgramName (ProgramListID listId, int32 programIndex, String128* name /*out*/)
    {
        if (listId != PARAM_ID_PROGRAM_CHANGE)
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

    // Assigned when UI is opened, nulled when closed. This allow to request a host parent window resize.
    IPlugFrame _plugFrame = null; 
    IPlugView _currentView = null;

    shared(bool) _shouldInitialize = true;
    shared(bool) _bypassed = false;

    // This is number of preset - 1, but 0 if no presets
    // "stepcount" is offset by 1 in VST3 Parameter parlance
    // stepcount = 1 gives 2 different values
    int _presetStepCount;

    float _sampleRate;
    shared(float) _sampleRateHostPOV = 44100.0f;
    shared(float) _sampleRateAudioThreadPOV = 44100.0f;
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

    // Scratch buffers
    float[] _zeroesBuffer; // for deactivated input bus
    float[] _outputScratchBuffer; // for deactivated output bus
    Vec!float[] _inputScratchBuffers; // for input safe copy
    int _maxInputs;

    void resizeScratchBuffers(int maxFrames) nothrow @nogc
    {
        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffers[i].resize(maxFrames);
        _outputScratchBuffer.reallocBuffer(maxFrames);
        _zeroesBuffer.reallocBuffer(maxFrames);
        _zeroesBuffer[0..maxFrames] = 0;
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

    double convertBypassParamToNormalized(double plainValue) const
    {
        return plainValue / cast(double)1;
    }

    double convertBypassParamToPlain(double normalizedValue) const
    {
        double v = cast(int)(normalizedValue * 2);
        if (v > 1)
            v = 1;
        return v;
    }

    double convertPresetParamToNormalized(double presetPlainValue) const
    {
        if (_presetStepCount == 0) // 0 or 1 preset
            return 0;
        return presetPlainValue / cast(double)_presetStepCount;
    }

    bool convertPresetParamToPlain(double presetNormalizedValue, int* presetIndex)
    {
        int index = cast(int)(presetNormalizedValue * (_presetStepCount + 1));
        if (index > _presetStepCount)
            index = _presetStepCount;
        *presetIndex = index;
        return _client.presetBank.isValidPresetIndex(_presetStepCount);
    }
}

private:
nothrow:
pure:
@nogc:

enum int PARAM_ID_BYPASS = 998;
enum int PARAM_ID_PROGRAM_CHANGE = 999;

// Convert from VST3 index to VST3 ParamID
int convertVST3ParamIndexToParamID(int index)
{
    // Parameter with VST3 index 0 is a fake Bypass parameter
    if (index == 0)
        return PARAM_ID_BYPASS;

    // Parameter with VST3 index 1 is a fake Program Change parameter
    if (index == 1)
        return PARAM_ID_PROGRAM_CHANGE;

    // Parameter with VST3 index 2 is the first client Parameter
    return index - 2;
}

// Convert from VST3 ParamID to VST3 index
int convertParamIDToVST3ParamIndex(int index)
{
    // Parameter with VST3 index 0 is a fake Bypass parameter
    if (index == PARAM_ID_BYPASS)
        return 0;

    // Parameter with VST3 index 1 is a fake Program Change parameter
    if (index == PARAM_ID_PROGRAM_CHANGE)
        return 1;

    // Parameter with VST3 index 2 is the first client Parameter
    return index + 2;
}

/// Convert from VST3 ParamID to Client Parameter index
int convertParamIDToClientParamIndex(int paramID)
{
    // Shouldn't be here if this is a fake parameter
    assert (paramID != PARAM_ID_BYPASS);
    assert (paramID != PARAM_ID_PROGRAM_CHANGE);

    // Parameter with VST3 index 2 is the first client Parameter
    return paramID;
}

/// Convert from Client Parameter index to VST3 ParamID
int convertClientParamIndexToParamID(int clientIndex)
{
    return clientIndex;
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
        GraphicsBackend backend;
        if (convertPlatformToGraphicsBackend(type, &backend))
            return isGraphicsBackendSupported(backend) ? kResultTrue : kResultFalse;
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

            GraphicsBackend backend = GraphicsBackend.autodetect;
            if (!convertPlatformToGraphicsBackend(type, &backend))
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
            _vst3Client._plugFrame = null;
            _vst3Client._currentView = null;
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

        int widthLogicalPixels, heightLogicalPixels;
        if (_vst3Client._client.getGUISize(&widthLogicalPixels, &heightLogicalPixels))
        {
            size.left = 0;
            size.top = 0;
            size.right = widthLogicalPixels;
            size.bottom = heightLogicalPixels;
            return kResultTrue;
        }
        return kResultFalse;
    }

    /** Resizes the platform representation of the view to the given rect. Note that if the Plug-in
    *  requests a resize (IPlugFrame::resizeView ()) onSize has to be called afterward. */
    extern(Windows) tresult onSize (ViewRect* newSize)
    {
        _graphicsMutex.lock();
        scope(exit) _graphicsMutex.unlock();

        auto graphics = _vst3Client._client.graphicsAcquire();
        if (graphics is null) 
            return kResultOk; // Window not yet opened, nothing to do.

        graphics.nativeWindowResize(newSize.getWidth(), newSize.getHeight()); // Tell the IWindow to position itself at newSize.

        _vst3Client._client.graphicsRelease();
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
        _vst3Client._plugFrame = frame;
        _vst3Client._currentView = cast(IPlugView)this;
        return kResultTrue;
    }

    /** Is view sizable by user. */
    extern(Windows) tresult canResize ()
    {
        auto graphics = _vst3Client._client.graphicsAcquire();
        if (graphics is null) 
            return kResultFalse;
        tresult result = graphics.isResizeable() ? kResultTrue : kResultFalse;
        _vst3Client._client.graphicsRelease();
        return result;
    }

    /** On live resize this is called to check if the view can be resized to the given rect, if not
    *  adjust the rect to the allowed size. */
    extern(Windows) tresult checkSizeConstraint (ViewRect* rect)
    {
        auto graphics = _vst3Client._client.graphicsAcquire();
        if (graphics is null) 
            return kResultFalse; // could as well return true? since we accomodate for any size anyway.

        int W = rect.getWidth();
        int H = rect.getHeight();

        graphics.getNearestValidSize(&W, &H);

        rect.right = rect.left + W;
        rect.bottom = rect.top + H;

        _vst3Client._client.graphicsRelease();
        return kResultTrue;
    }

private:
    VST3Client _vst3Client;
    UncheckedMutex _graphicsMutex;

    static bool convertPlatformToGraphicsBackend(FIDString type, GraphicsBackend* backend)
    {
        if (strcmp(type, kPlatformTypeHWND.ptr) == 0)
        {
            *backend = GraphicsBackend.win32;
            return true;
        }
        if (strcmp(type, kPlatformTypeNSView.ptr) == 0)
        {
            *backend = GraphicsBackend.cocoa;
            return true;
        }
        if (strcmp(type, kPlatformTypeX11EmbedWindowID.ptr) == 0)
        {
            *backend = GraphicsBackend.x11;
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
            handler.beginEdit(convertClientParamIndexToParamID(paramIndex));
    }

    override void paramAutomate(int paramIndex, float value)
    {
        auto handler = _vst3Client._handler;
        if (handler)
            handler.performEdit(convertClientParamIndexToParamID(paramIndex), value);
    }

    override void endParamEdit(int paramIndex)
    {
        auto handler = _vst3Client._handler;
        if (handler)
            handler.endEdit(convertClientParamIndexToParamID(paramIndex));
    }

    override bool requestResize(int width, int height)
    {
        IPlugFrame frame = _vst3Client._plugFrame;
        IPlugView view = _vst3Client._currentView;
        if (frame is null || view is null)
            return false;
        ViewRect rect;
        rect.left = 0;
        rect.top = 0;
        rect.right = width;
        rect.bottom = height;
        return frame.resizeView(view, &rect) == kResultOk;
    }

    DAW getDAW()
    {
        return _vst3Client._daw;
    }

    override PluginFormat getPluginFormat()
    {
        return PluginFormat.vst3;
    }

private:
    VST3Client _vst3Client;
}

/// Returns: `true` if that graphics backend is supported on this platform in VST3
private bool isGraphicsBackendSupported(GraphicsBackend backend) nothrow @nogc
{
    version(Windows)
        return (backend == GraphicsBackend.win32);
    else version(OSX)
    {
        return (backend == GraphicsBackend.cocoa);
    }
    else version(linux)
        return (backend == GraphicsBackend.x11);
    else
        static assert(false, "Unsupported OS");
}
