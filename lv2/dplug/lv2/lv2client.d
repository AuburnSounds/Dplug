/**
* LV2 Client implementation
*
* Copyright: Ethan Reker 2018.
*            Guillaume Piolat 2019.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
/*
 * DISTRHO Plugin Framework (DPF)
 * Copyright (C) 2012-2018 Filipe Coelho <falktx@falktx.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any purpose with
 * or without fee is hereby granted, provided that the above copyright notice and this
 * permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD
 * TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN
 * NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
 * DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER
 * IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
 * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

module dplug.lv2.lv2client;

import std.string,
       std.algorithm.comparison;

import core.stdc.stdlib,
       core.stdc.string,
       core.stdc.stdio,
       core.stdc.math,
       core.stdc.stdint;

import dplug.core.vec,
       dplug.core.nogc,
       dplug.core.math,
       dplug.core.lockedqueue,
       dplug.core.runtime,
       dplug.core.fpcontrol,
       dplug.core.thread,
       dplug.core.sync;

import dplug.client.client,
       dplug.client.daw,
       dplug.client.preset,
       dplug.client.graphics,
       dplug.client.midi,
       dplug.client.params;

import dplug.lv2.lv2,
       dplug.lv2.midi,
       dplug.lv2.ui,
       dplug.lv2.options,
       dplug.lv2.urid,
       dplug.lv2.atom;

//debug = debugLV2Client;

nothrow:
@nogc:

class LV2Client : IHostCommand
{
nothrow:
@nogc:

    Client _client;

    this(Client client, int legalIOIndex)
    {
        _client = client;

        // Implement IHostCommand itself
        _client.setHostCommand(this);
        _graphicsMutex = makeMutex();
        _legalIOIndex = legalIOIndex;
        _eventsInput = null;
    }

    ~this()
    {
        _client.destroyFree();

        _paramsPointers.reallocBuffer(0);
        _paramsLastValue.reallocBuffer(0);

        _inputPointersProvided.freeSlice();
        _outputPointersProvided.freeSlice();
        _inputPointersProcessing.freeSlice();
        _outputPointersProcessing.freeSlice();

        // destroy scratch buffers
        for (int i = 0; i < _numInputs; ++i)
            _inputScratchBuffer[i].destroy();
        for (int i = 0; i < _numOutputs; ++i)
            _outputScratchBuffer[i].destroy();
        _inputScratchBuffer.freeSlice();
        _outputScratchBuffer.freeSlice();
    }

    void instantiate(const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)
    {
        LV2_Options_Option* options = null;
        LV2_URID_Map* uridMap = null;

        for(int i = 0; features[i] != null; ++i)
        {
            if (strcmp(features[i].URI, "http://lv2plug.in/ns/ext/options#options") == 0)
                options = cast(LV2_Options_Option*)features[i].data;
            else if (strcmp(features[i].URI, "http://lv2plug.in/ns/ext/urid#map") == 0)
                uridMap = cast(LV2_URID_Map*)features[i].data;
        }

        // Some default value to initialize with in case we don't find an option with the max buffer size
        _maxBufferSize = 512;

        // Retrieve max buffer size from options
        if (options && uridMap)
        {
            for (int i = 0; options[i].key != 0; ++i)
            {
                if (options[i].key == uridMap.map(uridMap.handle, LV2_BUF_SIZE__maxBlockLength))
                    _maxBufferSize = *cast(const(int)*)options[i].value;
            }
        }

        _callResetOnNextRun = true;

        _mappedURIs.initialize(uridMap);

        LegalIO selectedIO = _client.legalIOs()[_legalIOIndex];

        _numInputs = selectedIO.numInputChannels;
        _numOutputs = selectedIO.numOutputChannels;
        _sampleRate = cast(float)rate;

        _numParams = cast(int)(_client.params.length);

        _paramsPointers.reallocBuffer(_numParams);
        _paramsPointers[] = null;

        _paramsLastValue.reallocBuffer(_numParams);
        for (int i = 0; i < _numParams; ++i)
            _paramsLastValue[i] = _client.param(i).getNormalized();


        _inputPointersProcessing  = mallocSlice!(float*)(_numInputs);
        _outputPointersProcessing = mallocSlice!(float*)(_numOutputs);
        _inputPointersProvided    = mallocSlice!(float*)(_numInputs);
        _outputPointersProvided   = mallocSlice!(float*)(_numOutputs);

        _inputScratchBuffer = mallocSlice!(Vec!float)(_numInputs);
        _outputScratchBuffer = mallocSlice!(Vec!float)(_numOutputs);
        for (int i = 0; i < _numInputs; ++i)
            _inputScratchBuffer[i] = makeVec!float();
        for (int i = 0; i < _numOutputs; ++i)
            _outputScratchBuffer[i] = makeVec!float();
        
        resizeScratchBuffers(_maxBufferSize);

        _write_function = null;

        _currentTimeInfo = TimeInfo.init;
        _currentTimeInfo.hostIsPlaying = true;
    }

    void connect_port(uint32_t port, void* data)
    {
        int numParams = cast(int)(_client.params.length);
        if(port < _client.params.length)
        {
            _paramsPointers[port] = cast(float*)data;
        }
        else if(port < _numInputs + numParams)
        {
            uint input = port - numParams;
            _inputPointersProvided[input] = cast(float*)data;
        }
        else if(port < _numOutputs + _numInputs + numParams)
        {
            uint output = port - numParams - _numInputs;
            _outputPointersProvided[output] = cast(float*)data;
        }
        else if(port < 1 + _numOutputs + _numInputs + numParams)
        {
            _eventsInput = cast(LV2_Atom_Sequence*)data;
        }
        else
            assert(false, "Error unknown port index");
    }

    void activate()
    {
        _callResetOnNextRun = true;
    }

    void resizeScratchBuffers(int numSamples)
    {
        for (int i = 0; i < _numInputs; ++i)
        {
            _inputScratchBuffer[i].resize(numSamples);
            _inputScratchBuffer[i].fill(0);
        }
        for (int i = 0; i < _numOutputs; ++i)
        {
            _outputScratchBuffer[i].resize(numSamples);
        }
    }

    void run(uint32_t n_samples)
    {
        if (_maxBufferSize < n_samples)
        {
            _callResetOnNextRun = true;
            _maxBufferSize = n_samples; // in case the max buffer value wasn't found within options
            resizeScratchBuffers(_maxBufferSize);
        }

        if(_callResetOnNextRun)
        {
            _callResetOnNextRun = false;
            _client.resetFromHost(_sampleRate, _maxBufferSize, _numInputs, _numOutputs);
        }

        if (_eventsInput !is null)
        {
            for(LV2_Atom_Event* event = lv2_atom_sequence_begin(&_eventsInput.body_);
                !lv2_atom_sequence_is_end(&_eventsInput.body_, _eventsInput.atom.size, event);
                event = lv2_atom_sequence_next(event))
            {
                if (event is null)
                    break;

                if (_client.receivesMIDI() && event.body_.type == _mappedURIs.midiEvent)
                {
                    // Get offset of MIDI message in that buffer
                    int offset = cast(int)(event.time.frames);
                    if (offset < 0)
                        offset = 0;
                    int bytes = event.body_.size;
                    ubyte* data = cast(ubyte*)(event + 1);

                    if (bytes >= 1 && bytes <= 3) // else doesn't fit in a Dplug MidiMessage
                    {
                        ubyte byte0 = data[0];
                        ubyte byte1 = (bytes >= 2) ? data[1] : 0;
                        ubyte byte2 = (bytes >= 3) ? data[2] : 0;
                        MidiMessage message = MidiMessage(offset, byte0, byte1, byte2);
                        _client.enqueueMIDIFromHost(message);
                    }
                }
                else if (event.body_.type == _mappedURIs.atomBlank || event.body_.type == _mappedURIs.atomObject)
                {

                    const (LV2_Atom_Object*) obj = cast(LV2_Atom_Object*)&event.body_;

                    if (obj.body_.otype == _mappedURIs.timePosition)
                    {
                        LV2_Atom* beatsPerMinute = null;
                        LV2_Atom* frame = null;
                        LV2_Atom* speed = null;

                        lv2AtomObjectExtractTimeInfo(obj,
                                           _mappedURIs.timeBeatsPerMinute, &beatsPerMinute,
                                           _mappedURIs.timeFrame, &frame,
                                           _mappedURIs.timeSpeed, &speed);

                        if (beatsPerMinute != null)
                        {
                            if (beatsPerMinute.type == _mappedURIs.atomDouble)
                                _currentTimeInfo.tempo = (cast(LV2_Atom_Double*)beatsPerMinute).body_;
                            else if (beatsPerMinute.type == _mappedURIs.atomFloat)
                                _currentTimeInfo.tempo = (cast(LV2_Atom_Float*)beatsPerMinute).body_;
                            else if (beatsPerMinute.type == _mappedURIs.atomInt)
                                _currentTimeInfo.tempo = (cast(LV2_Atom_Int*)beatsPerMinute).body_;
                            else if (beatsPerMinute.type == _mappedURIs.atomLong)
                                _currentTimeInfo.tempo = (cast(LV2_Atom_Long*)beatsPerMinute).body_;
                        }
                        if (frame != null)
                        {
                            if (frame.type == _mappedURIs.atomDouble)
                                _currentTimeInfo.timeInSamples = cast(long)(cast(LV2_Atom_Double*)frame).body_;
                            else if (frame.type == _mappedURIs.atomFloat)
                                _currentTimeInfo.timeInSamples = cast(long)(cast(LV2_Atom_Float*)frame).body_;
                            else if (frame.type == _mappedURIs.atomInt)
                                _currentTimeInfo.timeInSamples = (cast(LV2_Atom_Int*)frame).body_;
                            else if (frame.type == _mappedURIs.atomLong)
                                _currentTimeInfo.timeInSamples = (cast(LV2_Atom_Long*)frame).body_;
                        }
                        if (speed != null)
                        {
                            if (speed.type == _mappedURIs.atomDouble)
                                _currentTimeInfo.hostIsPlaying = (cast(LV2_Atom_Double*)speed).body_ > 0.0f;
                            else if (speed.type == _mappedURIs.atomFloat)
                                _currentTimeInfo.hostIsPlaying = (cast(LV2_Atom_Float*)speed).body_ > 0.0f;
                            else if (speed.type == _mappedURIs.atomInt)
                                _currentTimeInfo.hostIsPlaying = (cast(LV2_Atom_Int*)speed).body_ > 0.0f;
                            else if (speed.type == _mappedURIs.atomLong)
                                _currentTimeInfo.hostIsPlaying = (cast(LV2_Atom_Long*)speed).body_ > 0.0f;
                        }
                    }
                }
            }
        }

        // Update changed parameters
        {
            for (int i = 0; i < _numParams; ++i)
            {
                if (_paramsPointers[i])
                {
                    float currentValue = *_paramsPointers[i];

                    // Force normalization in case host sends invalid parameter values
                    if (currentValue < 0) currentValue = 0;
                    if (currentValue > 1) currentValue = 1;

                    if (currentValue != _paramsLastValue[i])
                    {
                        _paramsLastValue[i] = currentValue;
                        _client.setParameterFromHost(i, currentValue);
                    }
                }
            }
        }

        // Fill input and output pointers for this block, based on what we have received
        for(int input = 0; input < _numInputs; ++input)
        {
            // Copy each available input to a scrach buffer, because some hosts (Mixbus/Ardour)
            // give identical pointers for input and output buffers.
            if (_inputPointersProvided[input])
            {
                const(float)* source = _inputPointersProvided[input];
                float* dest = _inputScratchBuffer[input].ptr;
                dest[0..n_samples] = source[0..n_samples];
            }
            _inputPointersProcessing[input] = _inputScratchBuffer[input].ptr;
        }
        for(int output = 0; output < _numOutputs; ++output)
        {
            _outputPointersProcessing[output] = _outputPointersProvided[output] ? _outputPointersProvided[output] : _outputScratchBuffer[output].ptr;
        }

        // Process audio
        _client.processAudioFromHost(_inputPointersProcessing, _outputPointersProcessing, n_samples, _currentTimeInfo);

        _currentTimeInfo.timeInSamples += n_samples;
    }

    void instantiateUI(const LV2UI_Descriptor* descriptor,
                       const char*                     plugin_uri,
                       const char*                     bundle_path,
                       LV2UI_Write_Function            write_function,
                       LV2UI_Controller                controller,
                       LV2UI_Widget*                   widget,
                       const (LV2_Feature*)*       features)
    {
        debug(debugLV2Client) debugLog(">instantiateUI");

        int transientWinId;
        void* parentId = null;
        LV2_Options_Option* options = null;
        _uiResize = null;
        LV2_URID_Map* uridMap = null;

        // Useful to record automation
        _write_function = write_function;
        _controller = controller;
        _uiTouch = null;

        for (int i=0; features[i] != null; ++i)
        {
            if (strcmp(features[i].URI, LV2_UI__parent) == 0)
                parentId = cast(void*)features[i].data;
            else if (strcmp(features[i].URI, LV2_UI__resize) == 0)
                _uiResize = cast(LV2UI_Resize*)features[i].data;
            else if (strcmp(features[i].URI, LV2_OPTIONS__options) == 0)
                options = cast(LV2_Options_Option*)features[i].data;
            else if (strcmp(features[i].URI, LV2_URID__map) == 0)
                uridMap = cast(LV2_URID_Map*)features[i].data;
            else if (strcmp(features[i].URI, LV2_UI__touch) == 0)
                _uiTouch = cast(LV2UI_Touch*)features[i].data;
        }

        // Not transmitted yet
        /*
        if (options && uridMap)
        {
            for (int i = 0; options[i].key != 0; ++i)
            {
                if (options[i].key == uridTransientWinId)
                {
                    transientWin = cast(void*)(options[i].value);    // sound like it lacks a dereferencing
                }
            }
        }*/

        if (widget != null)
        {
            _graphicsMutex.lock();
            void* pluginWindow = cast(LV2UI_Widget)_client.openGUI(parentId, null, GraphicsBackend.autodetect);
            _graphicsMutex.unlock();

            int width, height;
            if (_client.getGUISize(&width, &height))
            {
                _graphicsMutex.lock();
                _uiResize.ui_resize(_uiResize.handle, width, height);
                _graphicsMutex.unlock();
            }

            *widget = cast(LV2UI_Widget)pluginWindow;
        }
        debug(debugLV2Client) debugLog("<instantiateUI");
    }

    void portEventUI(uint32_t     port_index,
                     uint32_t     buffer_size,
                     uint32_t     format,
                     const void*  buffer)
    {
        // Nothing to do since parameter changes already dirty the UI?
    }

    void cleanupUI()
    {
        debug(debugLV2Client) debugLog(">cleanupUI");
        _graphicsMutex.lock();
        assert(_client.hasGUI());
        _client.closeGUI();
        _graphicsMutex.unlock();
        debug(debugLV2Client) debugLog("<cleanupUI");
    }

    override void beginParamEdit(int paramIndex)
    {
        // Note: this is untested, since it appears DISTRHO doesn't really ask 
        // for this interface, and Carla doesn't provide one.
        if ( (_uiTouch !is null) && (_uiTouch.touch !is null) )
            _uiTouch.touch(_uiTouch.handle, paramIndex, true);
    }

    override void paramAutomate(int paramIndex, float value)
    {
        // write back automation to host
        assert(_write_function !is null);
        _write_function(_controller, paramIndex, float.sizeof, 0, &value);
    }

    override void endParamEdit(int paramIndex)
    {
        // Note: this is untested, since it appears DISTRHO doesn't really ask 
        // for this interface, and Carla doesn't provide one.
        if ( (_uiTouch !is null) && (_uiTouch.touch !is null) )
            _uiTouch.touch(_uiTouch.handle, paramIndex, false);
    }

    override bool requestResize(int width, int height)
    {
        int result = _uiResize.ui_resize(_uiResize.handle, width, height);
        return result == 0;
    }

    // Not properly implemented yet. LV2 should have an extension to get DAW information.
    override DAW getDAW()
    {
        return DAW.Unknown;
    }

private:

    uint _numInputs;
    uint _numOutputs;

    // the maximum buffer size we've found, from either the options or reality of incoming buffers
    int _maxBufferSize;

    // whether the plugin should call resetFromHost at next `run()`
    bool _callResetOnNextRun;

    int _numParams;
    float*[] _paramsPointers;
    float[] _paramsLastValue;

    // Scratch input buffers in case the host doesn't provide ones.
    Vec!float[] _inputScratchBuffer;

    // Scratch output buffers in case the host doesn't provide ones.
    Vec!float[] _outputScratchBuffer;

    // Input pointers that were provided by the host, `null` if not provided.
    float*[] _inputPointersProvided;

    // Output input used by processing, recomputed at each run().
    float*[] _inputPointersProcessing;

    // Output pointers that were provided by the host, `null` if not provided.
    float*[] _outputPointersProvided;

    // Output pointers used by processing, recomputed at each run().
    float*[] _outputPointersProcessing;

    LV2_Atom_Sequence* _eventsInput;

    float _sampleRate;

    UncheckedMutex _graphicsMutex;

    // Set at instantiation
    MappedURIs _mappedURIs;

    int _legalIOIndex;

    LV2UI_Write_Function _write_function;
    LV2UI_Controller _controller;
    LV2UI_Touch* _uiTouch;
    LV2UI_Resize* _uiResize;

    // Current time info, eventually extrapolated when data is missing.
    TimeInfo _currentTimeInfo;
}

struct MappedURIs
{
nothrow:
@nogc:

    LV2_URID atomDouble;
    LV2_URID atomFloat;
    LV2_URID atomInt;
    LV2_URID atomLong;
    LV2_URID atomBlank;
    LV2_URID atomObject;
    LV2_URID atomSequence;
    LV2_URID midiEvent;
    LV2_URID timePosition;
    LV2_URID timeFrame;
    LV2_URID timeBeatsPerMinute;
    LV2_URID timeSpeed;

    void initialize(LV2_URID_Map* uridMap)
    {
        atomDouble = uridMap.map(uridMap.handle, LV2_ATOM__Double);
        atomFloat = uridMap.map(uridMap.handle, LV2_ATOM__Float);
        atomInt = uridMap.map(uridMap.handle, LV2_ATOM__Int);
        atomLong = uridMap.map(uridMap.handle, LV2_ATOM__Long);
        atomBlank = uridMap.map(uridMap.handle, LV2_ATOM__Blank);
        atomObject = uridMap.map(uridMap.handle, LV2_ATOM__Object);
        atomSequence = uridMap.map(uridMap.handle, LV2_ATOM__Sequence);
        midiEvent = uridMap.map(uridMap.handle, LV2_MIDI__MidiEvent);
        timePosition = uridMap.map(uridMap.handle, LV2_TIME__Position);
        timeFrame = uridMap.map(uridMap.handle, LV2_TIME__frame);
        timeBeatsPerMinute = uridMap.map(uridMap.handle, LV2_TIME__beatsPerMinute);
        timeSpeed = uridMap.map(uridMap.handle, LV2_TIME__speed);
    }
}


int lv2AtomObjectExtractTimeInfo(const (LV2_Atom_Object*) object,
                                 LV2_URID tempoURID, LV2_Atom** tempoAtom,
                                 LV2_URID frameURID, LV2_Atom** frameAtom,
                                 LV2_URID speedURID, LV2_Atom** speedAtom)
{
    int n_queries = 3;
    int matches = 0;
    // #define LV2_ATOM_OBJECT_FOREACH(obj, iter)
    for (LV2_Atom_Property_Body* prop = lv2_atom_object_begin(&object.body_);
        !lv2_atom_object_is_end(&object.body_, object.atom.size, prop);
        prop = lv2_atom_object_next(prop))
    {
        for (int i = 0; i < n_queries; ++i) {
            // uint32_t         qkey = va_arg!(uint32_t)(args);
            // LV2_Atom** qval = va_arg!(LV2_Atom**)(args);
            // if (qkey == prop.key && !*qval) {
            //     *qval = &prop.value;
            //     if (++matches == n_queries) {
            //         return matches;
            //     }
            //     break;
            // }
            if(tempoURID == prop.key && tempoAtom) {
                *tempoAtom = &prop.value;
                ++matches;
            }
            else if(frameURID == prop.key && frameAtom) {
                *frameAtom = &prop.value;
                ++matches;
            }
            else if(speedURID == prop.key && speedAtom) {
                *speedAtom = &prop.value;
                ++matches;
            }
        }
    }
    return matches;
}