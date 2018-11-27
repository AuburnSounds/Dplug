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

import dplug.core.nogc;
import dplug.core.sync;
import dplug.core.vec;
import dplug.core.runtime;
import dplug.vst3.ftypes;
import dplug.vst3.funknown;
import dplug.vst3.fplatform;
import dplug.vst3.ivstaudioprocessor;
import dplug.vst3.ivsteditcontroller;
import dplug.vst3.ihostapplication;
import dplug.vst3.iplugview;
import dplug.vst3.ivstcomponent;
import dplug.vst3.ipluginbase;
import dplug.vst3.fstrdefs;
import dplug.vst3.ibstream;
import dplug.vst3.ivstunit;

//version(Windows)
//    debug = logVST3Client;

debug(logVST3Client)
    import core.sys.windows.windows: OutputDebugStringA;

// TODO: call IComponentHandler::restartComponent (kLatencyChanged) after a latency change
// Note: the VST3 client assumes shared memory
class VST3Client : IAudioProcessor, IComponent, IEditController, IUnitInfo
{
public:
nothrow:
@nogc:

    this(Client client, IUnknown hostCallback)
    {
        _client = client;

        _hostCommand = mallocNew!VST3HostCommand();
        _client.setHostCommand(_hostCommand);
    }

    ~this()
    {
        destroyFree(_client);
        _client = null;

        destroyFree(_hostCommand);
        _hostCommand = null;

        _inputPointers.reallocBuffer(0);
        _outputPointers.reallocBuffer(0);
    }

    // Implements FUnknown
    mixin QUERY_INTERFACE_SPECIAL_CASE_IUNKNOWN!(IAudioProcessor, IComponent, IEditController, IPluginBase, IUnitInfo);
	mixin IMPLEMENT_REFCOUNT;


    // Implements IPluginBase

    /** The host passes a number of interfaces as context to initialize the Plug-in class.
    @note Extensive memory allocations etc. should be performed in this method rather than in the class' constructor!
    If the method does NOT return kResultOk, the object is released immediately. In this case terminate is not called! */
	override tresult initialize(FUnknown context)
    {
        debug(logVST3Client) OutputDebugStringA("initialize()".ptr);
        setHostApplication(context);

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
            busAudioIn.speakerArrangement = getSpeakerArrangement(maxInputs); // TODO right arrangement for input audio
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
            busAudioOut.speakerArrangement = getSpeakerArrangement(maxOutputs); // TODO right arrangement for output audio
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
        debug(logVST3Client) OutputDebugStringA("terminate()".ptr);
        if (_hostApplication !is null)
        {
            _hostApplication.release();
            _hostApplication = null;
        }
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

    override tresult setStateController (IBStream state)
    {
        // TODO deserialize
        return kNotImplemented;
    }

    override tresult getStateController (IBStream state)
    {
        // TODO serialize
        return kNotImplemented;
    }

    // Implements IAudioProcessor

    override tresult setBusArrangements (SpeakerArrangement* inputs, int32 numIns, SpeakerArrangement* outputs, int32 numOuts)
    {
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
            _audioInputs[0].speakerArrangement = inputs[0];
            _audioInputs[0].info.channelCount = reqInputs;
        }
        if (numOuts == 1)
        {
            _audioOutputs[0].speakerArrangement = outputs[0];
            _audioOutputs[0].info.channelCount = reqOutputs;
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

        // TODO fill TimeInfo
        TimeInfo info;
        _client.processAudioFromHost(_inputPointers[], _outputPointers[], data.numSamples, info);
        return kResultOk;
    }

    override uint32 getTailSamples()
    {
        return cast(int)(0.5f + _client.tailSizeInSeconds() * atomicLoad(_sampleRateHostPOV));
    }

    // Implements IEditController

    override tresult setComponentState (IBStream state)
    {
        // TODO
        // Why duplicate?
        return kNotImplemented;
    }

    override tresult setState(IBStream state)
    {
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

    override tresult getState(IBStream state)
    {
        auto presetBank = _client.presetBank();
        ubyte[] chunk = presetBank.getStateChunkFromCurrentState();
        scope(exit) free(chunk.ptr);
        return state.write(chunk.ptr, cast(int)(chunk.length), null);
    }

    override int32 getParameterCount()
    {
        return cast(int)(_client.params.length);
    }

    override tresult getParameterInfo (int32 paramIndex, ref ParameterInfo info)
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
        info.unitId = 0; // root, unit 0 is always here
        info.flags = ParameterInfo.ParameterFlags.kCanAutomate; // Dplug assumption: all parameters automatable.
        return kResultTrue;
    }

    /** Gets for a given paramID and normalized value its associated string representation. */
    override tresult getParamStringByValue (ParamID id, ParamValue valueNormalized, String128 string_ )
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
    override tresult getParamValueByString (ParamID id, TChar* string_, ref ParamValue valueNormalized )
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
    override ParamValue normalizedParamToPlain (ParamID id, ParamValue valueNormalized)
    {
        // TODO: correct thing to do? SDK examples expose remapped integers and floats
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return 0;
        Parameter param = _client.param(paramIndex);
        return valueNormalized; // Note: the host don't need to know we do not deal with normalized values internally
    }

    /** Returns for a given paramID and a plain value its normalized value. (see \ref vst3AutomationIntro) */
    override ParamValue plainParamToNormalized (ParamID id, ParamValue plainValue)
    {
        // TODO: correct thing to do? SDK examples expose remapped integers and floats
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return 0;
        Parameter param = _client.param(paramIndex);
        return plainValue; // Note: the host don't need to know we do not deal with normalized values internally
    }

    /** Returns the normalized value of the parameter associated to the paramID. */
    override ParamValue getParamNormalized (ParamID id)
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
    override tresult setParamNormalized (ParamID id, ParamValue value)
    {
        int paramIndex = convertParamIDToParamIndex(id);
        if (!_client.isValidParamIndex(paramIndex))
            return kResultFalse;
        Parameter param = _client.param(paramIndex);
        param.setFromHost(value);
        return kResultTrue;
    }

    /** Gets from host a handler. */
    override tresult setComponentHandler (IComponentHandler handler)
    {
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
    override IPlugView createView (FIDString name)
    {
        if (name !is null && strcmp(name, "editor") == 0)
            return mallocNew!DplugView(this);
        return null;
    }


    // implements IUnitInfo

    override int32 getUnitCount ()
    {
        return 1;
    }

    /** Gets UnitInfo for a given index in the flat list of unit. */
    override tresult getUnitInfo (int32 unitIndex, ref UnitInfo info /*out*/)
    {
        if (unitIndex == 0)
        {
            info.id = kRootUnitId;
            info.parentUnitId = kNoParentUnitId;
            str8ToStr16(info.name.ptr, "Root Unit", 128);
            info.programListId = kNoProgramListId;
            return kResultTrue;
        }
        return kResultFalse;
    }

    /** Component intern program structure. */
    /** Gets the count of Program List. */
    int32 getProgramListCount ()
    {
        return 0;
    }

    /** Gets for a given index the Program List Info. */
    tresult getProgramListInfo (int32 listIndex, ref ProgramListInfo info /*out*/)
    {
        return kResultFalse; // TODO
    }

    /** Gets for a given program list ID and program index its program name. */
    tresult getProgramName (ProgramListID listId, int32 programIndex, String128 name /*out*/)
    {
        return kResultFalse; // TODO
    }

    /** Gets for a given program list ID, program index and attributeId the associated attribute value. */
    tresult getProgramInfo (ProgramListID listId, int32 programIndex,
                            const(wchar)* attributeId /*in*/, String128 attributeValue /*out*/)
    {
        return kResultFalse; // TODO
    }

    /** Returns kResultTrue if the given program index of a given program list ID supports PitchNames. */
    tresult hasProgramPitchNames (ProgramListID listId, int32 programIndex)
    {
        return kResultFalse; // TODO
    }

    /** Gets the PitchName for a given program list ID, program index and pitch.
    If PitchNames are changed the Plug-in should inform the host with IUnitHandler::notifyProgramListChange. */
    tresult getProgramPitchName (ProgramListID listId, int32 programIndex,
                                 int16 midiPitch, String128 name /*out*/)
    {
        return kResultFalse; // TODO
    }

    // units selection --------------------
    /** Gets the current selected unit. */
    UnitID getSelectedUnit ()
    {
        return 0;
    }

    /** Sets a new selected unit. */
    tresult selectUnit (UnitID unitId)
    {
        return kResultTrue; // TODO
    }

    /** Gets the according unit if there is an unambiguous relation between a channel or a bus and a unit.
    This method mainly is intended to find out which unit is related to a given MIDI input channel. */
    tresult getUnitByBus (MediaType type, BusDirection dir, int32 busIndex,
                          int32 channel, ref UnitID unitId /*out*/)
    {
        return kResultFalse; // TODO
    }

    /** Receives a preset data stream.
    - If the component supports program list data (IProgramListData), the destination of the data
    stream is the program specified by list-Id and program index (first and second parameter)
    - If the component supports unit data (IUnitData), the destination is the unit specified by the first
    parameter - in this case parameter programIndex is < 0). */
    tresult setUnitProgramData (int32 listOrUnitId, int32 programIndex, IBStream data)
    {
        return kResultFalse; // TODO
    }

private:
    Client _client;
    IComponentHandler _handler;
    IHostCommand _hostCommand;

    shared(bool) _shouldInitialize = true;

    shared(float) _sampleRateHostPOV = 44100.0f;
    float _sampleRateDSPPOV = 0.0f;
    
    shared(int) _maxSamplesPerBlockHostPOV = -1;
    int _maxSamplesPerBlockDSPPOV = -1;

    int _numInputChannels = -1; /// Number of input channels from the DSP point of view
    int _numOutputChannels = -1; /// Number of output channels from the DSP point of view

    float*[] _inputPointers;
    float*[] _outputPointers;

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
    override tresult isPlatformTypeSupported (FIDString type)
    {
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
    tresult attached (void* parent, FIDString type)
    {
        debug(logVST3Client) OutputDebugStringA("attached".ptr);

        if (_vst3Client._client.hasGUI() )
        {
            WindowBackend backend = WindowBackend.autodetect;
            convertPlatformToWindowBackend(type, &backend);  
            _graphicsMutex.lock();
            scope(exit) _graphicsMutex.unlock();

            _vst3Client._client.openGUI(parent, null, cast(GraphicsBackend)backend);
            return kResultTrue;
        }
        return kResultFalse;
        
    }

    /** The parent window of the view is about to be destroyed.
    You have to remove all your own views from the parent window or view. */
    tresult removed ()
    {
        debug(logVST3Client) OutputDebugStringA("removed".ptr);
        if (_vst3Client._client.hasGUI() )
        {
            _graphicsMutex.lock();
            scope(exit) _graphicsMutex.unlock();
            _vst3Client._client.closeGUI();
        }
        return kResultOk;
    }

    /** Handling of mouse wheel. */
    tresult onWheel (float distance)
    {
        return kResultFalse;
    }

    /** Handling of keyboard events : Key Down.
    \param key : unicode code of key
    \param keyCode : virtual keycode for non ascii keys - see \ref VirtualKeyCodes in keycodes.h
    \param modifiers : any combination of modifiers - see \ref KeyModifier in keycodes.h
    \return kResultTrue if the key is handled, otherwise kResultFalse. \n
    <b> Please note that kResultTrue must only be returned if the key has really been
    handled. </b> Otherwise key command handling of the host might be blocked! */
    tresult onKeyDown (char16 key, int16 keyCode, int16 modifiers)
    {
        return kResultFalse;
    }

    /** Handling of keyboard events : Key Up.
    \param key : unicode code of key
    \param keyCode : virtual keycode for non ascii keys - see \ref VirtualKeyCodes in keycodes.h
    \param modifiers : any combination of KeyModifier - see \ref KeyModifier in keycodes.h
    \return kResultTrue if the key is handled, otherwise return kResultFalse. */
    tresult onKeyUp (char16 key, int16 keyCode, int16 modifiers)
    {
        return kResultFalse;
    }

    /** Returns the size of the platform representation of the view. */
    tresult getSize (ViewRect* size)
    {
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
    tresult onSize (ViewRect* newSize)
    {
        return kResultOk;
    }

    /** Focus changed message. */
    tresult onFocus (TBool state)
    {
        return kResultOk;
    }

    /** Sets IPlugFrame object to allow the Plug-in to inform the host about resizing. */
    tresult setFrame (IPlugFrame frame)
    {
        _plugFrame = frame;
        return kResultTrue;
    }

    /** Is view sizable by user. */
    tresult canResize ()
    {
        return kResultFalse;
    }

    /** On live resize this is called to check if the view can be resized to the given rect, if not
    *  adjust the rect to the allowed size. */
    tresult checkSizeConstraint (ViewRect* rect)
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
        _vst3client = vst3Client;
    }

    override void beginParamEdit(int paramIndex)
    {
        auto handler = _vst3client._handler;
        if (handler)
            handler.beginEdit(convertParamIndexToParamID(paramIndex));
    }

    override void paramAutomate(int paramIndex, float value)
    {
        auto handler = _vst3client._handler;
        if (handler)
            handler.performEdit(convertParamIndexToParamID(paramIndex), value);
    }

    override void endParamEdit(int paramIndex)
    {
        auto handler = _vst3client._handler;
        if (handler)
            handler.endEdit(convertParamIndexToParamID(paramIndex));
    }

    override bool requestResize(int width, int height)
    {
        // TODO, need to keep an instance pointer of the current IPluginView
        return false;
    }

    DAW getDAW()
    {
        return DAW.Cubase; // there are no host-related workarounds for now
    }
}