/**
* LV2 Client implementation
*
* Copyright: Ethan Reker 2018.
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
       dplug.core.sync,
       dplug.core.map;

import dplug.client.client,
       dplug.client.daw,
       dplug.client.preset,
       dplug.client.graphics,
       dplug.client.midi,
       dplug.client.params;

import dplug.lv2.lv2,
       dplug.lv2.lv2util,
       dplug.lv2.midi,
       dplug.lv2.ui,
       dplug.lv2.options,
       dplug.lv2.urid,
       dplug.lv2.bufsize,
       dplug.lv2.atom,
       dplug.lv2.atomutil,
       dplug.lv2.kxstudio,
       dplug.lv2.time;

class LV2Client : IHostCommand
{
nothrow:
@nogc:

    Client _client;
    Map!(string, int)* _uriMap;

    this(Client client, Map!(string, int)* uriMapPtr)
    {
        _client = client;
        _client.setHostCommand(this);
        _graphicsMutex = makeMutex();
        _uriMap = uriMapPtr;
        _options = null;
        _uridMap = null;
    }

    void instantiate(const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)
    {
        for(int i = 0; features[i] != null; ++i)
        {
            if (strcmp(features[i].URI, LV2_OPTIONS__options) == 0)
                _options = cast(LV2_Options_Option*)features[i].data;
            else if (strcmp(features[i].URI, LV2_URID__map) == 0)
                _uridMap = cast(LV2_URID_Map*)features[i].data;
        }

        for(int i = 0; features[i] != null; ++i)
        {

        }

        // Retrieve max buffer size from options
        for (int i=0; _options[i].key != 0; ++i)
        {
            if (_options[i].key == assumeNothrowNoGC(_uridMap.map)(_uridMap.handle, LV2_BUF_SIZE__maxBlockLength))
            {
                _maxBufferSize = *cast(const(int)*)_options[i].value;
                _callResetOnNextRun = true;
            }
        }

        fURIDs = URIDs(_uridMap);

        // Retrieve index of legalIO that was stored in the uriMap
        string uri = cast(string)descriptor.URI[0..strlen(descriptor.URI)];
        int legalIOIndex = (*_uriMap)[uri];

        LegalIO selectedIO = _client.legalIOs()[legalIOIndex];

        _maxInputs = selectedIO.numInputChannels;
        _maxOutputs = selectedIO.numOutputChannels;
        _numParams = cast(uint)_client.params().length;
        _sampleRate = cast(float)rate;

        _params = cast(float**)mallocSlice!(float*)(_client.params.length);
        _inputs = mallocSlice!(float*)(_maxInputs);
        _outputs = mallocSlice!(float*)(_maxOutputs);
    }

    void cleanup()
    {
    }

    void updateParamFromHost(uint32_t port_index)
    {
        float* port = _params[port_index];
        float paramValue = *port;
        _client.setParameterFromHost(port_index, paramValue);
    }

    void updatePortFromClient(uint32_t port_index, float value)
    {
        float* port = _params[port_index];
        *port = value;
    }

    void connect_port(uint32_t port, void* data)
    {
        if(port < _client.params.length)
        {
            _params[port] = cast(float*)data;
        }
        else if(port < _maxInputs + _client.params.length)
        {
            _inputs[port - _client.params.length] = cast(float*)data;
        }
        else if(port < _maxOutputs + _maxInputs + _client.params.length)
        {
            _outputs[port - _client.params.length - _maxInputs] = cast(float*)data;
        }
        else if(port < _maxOutputs + _maxInputs + _client.params.length + 1)
        {
            _midiInput = cast(LV2_Atom_Sequence*)data;    
        }
        else
            assert(false, "Error unknown port index");
    }

    void activate()
    {
        _callResetOnNextRun = true;
    }

    void run(uint32_t n_samples)
    {
        TimeInfo timeInfo;

        if(_callResetOnNextRun)
        {
            _callResetOnNextRun = false;
            _client.resetFromHost(_sampleRate, _maxBufferSize, _maxInputs, _maxOutputs);
        }

        uint32_t  offset = 0;

        // LV2_ATOM_SEQUENCE_FOREACH Macro from atom.util. Only used once so no need to write a template for it.
        for(LV2_Atom_Event* event = assumeNothrowNoGC(&lv2_atom_sequence_begin)(&(_midiInput.body)); 
            !assumeNothrowNoGC(&lv2_atom_sequence_is_end)(&(this._midiInput).body, this._midiInput.atom.size, event); 
            event = assumeNothrowNoGC(&lv2_atom_sequence_next)(event))
        {
            if (event.body.type == fURIDs.midiEvent) {
                MidiMessage message;
                uint8_t* data = cast(uint8_t*)(event + 1);
                switch(data[0]) {
                    case LV2_MIDI_MSG_NOTE_ON:
                        message = makeMidiMessageNoteOn(offset, 0, cast(int)data[1], cast(int)data[2]);
                        break;
                    case LV2_MIDI_MSG_NOTE_OFF:
                        message = makeMidiMessageNoteOff(offset, 0, cast(int)data[1]);
                        break;
                    default: break;
                }
                _client.enqueueMIDIFromHost(message);
                continue;
            }

            if (event.body.type == fURIDs.atomBlank || event.body.type == fURIDs.atomObject)
            {
                const (LV2_Atom_Object*) obj = cast(LV2_Atom_Object*)&event.body;
                
                if (obj.body.otype != fURIDs.timePosition)
                    continue;

                LV2_Atom* beatsPerMinute = null;
                LV2_Atom* frame = null;
                LV2_Atom* speed = null;

                assumeNothrowNoGC(&lv2AtomObjectExtractTimeInfo)(obj,
                                   fURIDs.timeBeatsPerMinute, &beatsPerMinute,
                                   fURIDs.timeFrame, &frame,
                                   fURIDs.timeSpeed, &speed);

                if(beatsPerMinute != null) {
                    if (beatsPerMinute.type == fURIDs.atomDouble)
                        timeInfo.tempo = (cast(LV2_Atom_Double*)beatsPerMinute).body;
                    else if (beatsPerMinute.type == fURIDs.atomFloat)
                        timeInfo.tempo = (cast(LV2_Atom_Float*)beatsPerMinute).body;
                    else if (beatsPerMinute.type == fURIDs.atomInt)
                        timeInfo.tempo = (cast(LV2_Atom_Int*)beatsPerMinute).body;
                    else if (beatsPerMinute.type == fURIDs.atomLong)
                        timeInfo.tempo = (cast(LV2_Atom_Long*)beatsPerMinute).body;
                }
                if(frame != null) {
                    if (frame.type == fURIDs.atomDouble)
                        timeInfo.timeInSamples = cast(long)(cast(LV2_Atom_Double*)frame).body;
                    else if (frame.type == fURIDs.atomFloat)
                        timeInfo.timeInSamples = cast(long)(cast(LV2_Atom_Float*)frame).body;
                    else if (frame.type == fURIDs.atomInt)
                        timeInfo.timeInSamples = (cast(LV2_Atom_Int*)frame).body;
                    else if (frame.type == fURIDs.atomLong)
                        timeInfo.timeInSamples = (cast(LV2_Atom_Long*)frame).body;
                }
                if(speed != null) {
                    if (speed.type == fURIDs.atomDouble)
                        timeInfo.hostIsPlaying = (cast(LV2_Atom_Double*)speed).body > 0.0f;
                    else if (speed.type == fURIDs.atomFloat)
                        timeInfo.hostIsPlaying = (cast(LV2_Atom_Float*)speed).body > 0.0f;
                    else if (speed.type == fURIDs.atomInt)
                        timeInfo.hostIsPlaying = (cast(LV2_Atom_Int*)speed).body > 0.0f;
                    else if (speed.type == fURIDs.atomLong)
                        timeInfo.hostIsPlaying = (cast(LV2_Atom_Long*)speed).body > 0.0f;
                }
            }           
            offset = cast(uint32_t)(event.time.frames);
        }
        
        _client.processAudioFromHost(_inputs, _outputs, n_samples, timeInfo);
    }

    void deactivate()
    {

    }

    void instantiateUI(const LV2UI_Descriptor* descriptor,
                       const char*                     plugin_uri,
                       const char*                     bundle_path,
                       LV2UI_Write_Function            write_function,
                       LV2UI_Controller                controller,
                       LV2UI_Widget*                   widget,
                       const (LV2_Feature*)*       features)
    {
        void* parentId = null;
        LV2UI_Resize* uiResize = null;
        char* windowTitle = null;
        void* transientWin = null;
        int width, height;

        for (int i=0; features[i] != null; ++i)
        {
            if (strcmp(features[i].URI, LV2_UI__parent) == 0)
                parentId = cast(void*)features[i].data;
            else if (strcmp(features[i].URI, LV2_UI__resize) == 0)
                uiResize = cast(LV2UI_Resize*)features[i].data;
            else if (strcmp(features[i].URI, LV2_OPTIONS__options) == 0)
                _options = cast(LV2_Options_Option*)features[i].data;
            else if (strcmp(features[i].URI, LV2_URID__map) == 0)
                _uridMap = cast(LV2_URID_Map*)features[i].data;
        }

        LV2_URID uridWindowTitle = assumeNothrowNoGC(_uridMap.map)(_uridMap.handle, LV2_UI__windowTitle);
        LV2_URID uridTransientWinId = assumeNothrowNoGC(_uridMap.map)(_uridMap.handle, LV2_KXSTUDIO_PROPERTIES__TransientWindowId);

        for (int i=0; _options[i].key != 0; ++i)
        {
            if (_options[i].key == assumeNothrowNoGC(_uridMap.map)(_uridMap.handle, LV2_UI__windowTitle))
            {
                windowTitle = cast(char*)_options[i].value;   
            }
            else if (_options[i].key == assumeNothrowNoGC(_uridMap.map)(_uridMap.handle, LV2_KXSTUDIO_PROPERTIES__TransientWindowId))
            {
                transientWin = cast(void*)_options[i].value;   
            }
        }


        if (widget != null)
        {
            void* pluginWindow;
            _graphicsMutex.lock();
            pluginWindow = cast(LV2UI_Widget)_client.openGUI(parentId, windowTitle, GraphicsBackend.autodetect);
            _client.getGUISize(&width, &height);
            _graphicsMutex.unlock();

            assumeNothrowNoGC(uiResize.ui_resize)(uiResize.handle, width, height);
            *widget = pluginWindow;
        }
    }

    void port_event(uint32_t     port_index,
                    uint32_t     buffer_size,
                    uint32_t     format,
                    const void*  buffer)
    {
        _graphicsMutex.lock();
        updateParamFromHost(port_index);
        _graphicsMutex.unlock();
    }

    void cleanupUI()
    {
        _graphicsMutex.lock();
        _client.closeGUI();
        _graphicsMutex.unlock();
    }

    override void beginParamEdit(int paramIndex)
    {
        
    }

    override void paramAutomate(int paramIndex, float value)
    {
        updatePortFromClient(paramIndex, value);
    }

    override void endParamEdit(int paramIndex)
    {

    }

    override bool requestResize(int width, int height)
    {
        return false;
    }

    // Not properly implemented yet. LV2 should have an extension to get DAW information.
    override DAW getDAW()
    {
        return DAW.Unknown;
    }

private:

    uint _maxInputs;
    uint _maxOutputs;
    uint _numParams;
    int _maxBufferSize;
    bool _callResetOnNextRun;

    float** _params;
    float*[] _inputs;
    float*[] _outputs;
    LV2_Atom_Sequence* _midiInput;

    float _sampleRate;
    
    LV2_URID _midiEvent;
    LV2_URID _atomBlank;
    LV2_URID _atomObject;
    LV2_Options_Option* _options;
    LV2_URID_Map* _uridMap;

    UncheckedMutex _graphicsMutex;

    URIDs fURIDs;
}

struct URIDs {
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

    this(LV2_URID_Map* uridMap) nothrow @nogc
    {
        atomDouble = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_ATOM__Double);
        atomFloat = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_ATOM__Float);
        atomInt = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_ATOM__Int);
        atomLong = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_ATOM__Long);
        atomBlank = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_ATOM__Blank);
        atomObject = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_ATOM__Object);
        atomSequence = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_ATOM__Sequence);
        midiEvent = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_MIDI__MidiEvent);
        timePosition = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_TIME__Position);
        timeFrame = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_TIME__frame);
        timeBeatsPerMinute = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_TIME__beatsPerMinute);
        timeSpeed = assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_TIME__speed);
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
    for (LV2_Atom_Property_Body* prop = lv2_atom_object_begin(&object.body);
        !lv2_atom_object_is_end(&object.body, object.atom.size, prop);
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