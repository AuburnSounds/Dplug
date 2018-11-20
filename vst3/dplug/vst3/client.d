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
import dplug.core.runtime;
import dplug.vst3.ftypes;
import dplug.vst3.funknown;
import dplug.vst3.fplatform;
import dplug.vst3.ivstaudioprocessor;
import dplug.vst3.ivstcomponent;
import dplug.vst3.ipluginbase;
import dplug.vst3.ibstream;

import dplug.client.client;

// TODO: implement more interfaces 
//     * ComponentBase,
//     * IEditController,
//     * IEditController2
// TODO: call IComponentHandler::restartComponent (kLatencyChanged) after a latency change
// TODO buffer split
class VST3Client : IAudioProcessor, IComponent
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
    mixin QUERY_INTERFACE_SPECIAL_CASE_IUNKNOWN!(IAudioProcessor, IComponent);
	mixin IMPLEMENT_REFCOUNT;


    // Implements IPluginBase

    /** The host passes a number of interfaces as context to initialize the Plug-in class.
    @note Extensive memory allocations etc. should be performed in this method rather than in the class' constructor!
    If the method does NOT return kResultOk, the object is released immediately. In this case terminate is not called! */
	override tresult initialize(FUnknown context)
    {
        // TODO: do something with that context?
        return kResultOk;
    }

	/** This function is called before the Plug-in is unloaded and can be used for
    cleanups. You have to release all references to any host application interfaces. */
	override tresult terminate()
    {
        // TODO clean-up reference to host interface
        return kResultOk;
    }

    override tresult getControllerClassId (TUID classId)
    {
        // TODO
        return kNotImplemented;
    }

    override tresult setIoMode (IoMode mode)
    {
        // TODO
        return kNotImplemented;
    }

    override int32 getBusCount (MediaType type, BusDirection dir)
    {
        // TODO
        return kNotImplemented;
    }

    override tresult getBusInfo (MediaType type, BusDirection dir, int32 index, ref BusInfo bus /*out*/)
    {
        // TODO
        return kNotImplemented;
    }

    override tresult getRoutingInfo (ref RoutingInfo inInfo, ref RoutingInfo outInfo /*out*/)
    {
        // TODO
        return kNotImplemented;
    }

    override tresult activateBus (MediaType type, BusDirection dir, int32 index, TBool state)
    {
        // TODO
        return kNotImplemented;
    }

    override tresult setActive (TBool state)
    {
        // TODO
        return kNotImplemented;
    }

    override tresult setState (IBStream state)
    {
        // TODO
        return kNotImplemented;
    }

    override tresult getState (IBStream state)
    {
        // TODO
        return kNotImplemented;
    }


    // Implements IAudioProcessor
    override tresult setBusArrangements (SpeakerArrangement* inputs, int32 numIns,  SpeakerArrangement* outputs, int32 numOuts)
    {
        assert(false, "TODO");
    }

    override tresult getBusArrangement (BusDirection dir, int32 index, ref SpeakerArrangement arr)
    {
        assert(false, "TODO");
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

        atomicStore(_sampleRateHostPOV, setup.sampleRate);
        atomicStore(_maxSamplesPerBlockHostPOV, setup.maxSamplesPerBlock);

        // TODO setup input and output?

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

        if (shouldReinit || sampleRateChanged)
        {
            _sampleRateDSPPOV = newSampleRate;
            _maxSamplesPerBlockDSPPOV = newMaxSamplesPerBlock;
            _client.resetFromHost(_sampleRateDSPPOV, _maxSamplesPerBlockDSPPOV, 2, 2);//int numInputs, int numOutputs);
        }

        // TODO call processFromHost

        return kResultOk;
    }

    override uint32 getTailSamples()
    {
        return cast(int)(0.5f + _client.tailSizeInSeconds() * atomicLoad(_sampleRateHostPOV));
    }

private:
    Client _client;

    shared(bool) _shouldInitialize = true;

    shared(float) _sampleRateHostPOV = 44100.0f;
    float _sampleRateDSPPOV = 0.0f;
    
    shared(int) _maxSamplesPerBlockHostPOV = -1;
    int _maxSamplesPerBlockDSPPOV = -1;
}