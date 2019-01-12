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
       dplug.lv2.atomutil;

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
    }

    void instantiate(const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)
    {
        LV2_Options_Option* options = null;
        LV2_URID_Map* uridMap = null;
        for(int i = 0; features[i] != null; ++i)
        {
            if (strcmp(features[i].URI, LV2_OPTIONS__options) == 0)
                options = cast(LV2_Options_Option*)features[i].data;
            else if (strcmp(features[i].URI, LV2_URID__map) == 0)
                uridMap = cast(LV2_URID_Map*)features[i].data;
        }

        // Retrieve max buffer size from options
        for (int i=0; options[i].key != 0; ++i)
        {
            if (options[i].key == assumeNothrowNoGC(uridMap.map)(uridMap.handle, LV2_BUF_SIZE__maxBlockLength))
            {
                _maxBufferSize = *cast(const(int)*)options[i].value;
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
        if (widget != null)
        {
            _graphicsMutex.lock();
            int* windowHandle;
            _client.openGUI(windowHandle, null, GraphicsBackend.x11);
            *widget = cast(LV2UI_Widget)windowHandle;
            _graphicsMutex.unlock();
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
    LV2_Atom_Sequence* control;

    float _sampleRate;

    UncheckedMutex _graphicsMutex;
}