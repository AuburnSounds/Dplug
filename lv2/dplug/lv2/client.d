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

module dplug.lv2.client;

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
       dplug.lv2.kxstudio;

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

        // Retrieve max buffer size from options
        for (int i=0; _options[i].key != 0; ++i)
        {
            if (_options[i].key == assumeNothrowNoGC(_uridMap.map)(_uridMap.handle, LV2_BUF_SIZE__maxBlockLength))
            {
                _maxBufferSize = *cast(const(int)*)_options[i].value;
                _callResetOnNextRun = true;
            }
        }

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

        // uint32_t  offset = 0;

        // // LV2_ATOM_SEQUENCE_FOREACH Macro from atom.util. Only used once so no need to write a template for it.
        // for(LV2_Atom_Event* ev = assumeNothrowNoGC(&lv2_atom_sequence_begin)(&(_midiInput.body)); 
        //     !assumeNothrowNoGC(&lv2_atom_sequence_is_end)(&(this._midiInput).body, this._midiInput.atom.size, ev); 
        //     ev = assumeNothrowNoGC(&lv2_atom_sequence_next)(ev))
        // {
        //     if (ev.body.type == _midiEvent) {
        //         MidiMessage message;
        //         const (uint8_t)* msg = cast(const (uint8_t)*)(ev + 1);
        //         switch (assumeNothrowNoGC(&lv2_midi_message_type)(msg)) {
        //         case LV2_MIDI_MSG_NOTE_ON:
        //             // ++n_active_notes;
        //             break;
        //         case LV2_MIDI_MSG_NOTE_OFF:
        //             // --n_active_notes;
        //             break;
        //         default: break;
        //         }
        //         _client.enqueueMIDIFromHost(message);
        //     }

        //     if (ev.body.type == _atomBlank || ev.body.type == _atomObject)
        //     {
        //         LV2_Atom* frame = null;
        //     }           

        // //     write_output(self, offset, ev.time.frames - offset);
        //     // offset = cast(uint32_t)(ev.time.frames);
        // }

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
        int width, height;

        for (int i=0; features[i] != null; ++i)
        {
            if (strcmp(features[i].URI, LV2_UI__parent) == 0)
                parentId = cast(void*)features[i].data;
            if (strcmp(features[i].URI, LV2_UI__resize) == 0)
                uiResize = cast(LV2UI_Resize*)features[i].data;
        }

        LV2_URID uridWindowTitle = assumeNothrowNoGC(_uridMap.map)(_uridMap.handle, LV2_UI__windowTitle);
        LV2_URID uridTransientWinId = assumeNothrowNoGC(_uridMap.map)(_uridMap.handle, LV2_KXSTUDIO_PROPERTIES__TransientWindowId);

        if (widget != null)
        {
            void* pluginWindow;
            _graphicsMutex.lock();
            pluginWindow = cast(LV2UI_Widget)_client.openGUI(parentId, null, GraphicsBackend.autodetect);
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
}