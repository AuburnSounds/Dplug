/*
MIT License

Copyright (c) 2021 Alexandre BIQUE
Copyright (c) 2024 Guillaume PIOLAT

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
module dplug.clap.client;

import core.stdc.string: strcmp, strlen, memcpy;
import core.stdc.stdio: sscanf, snprintf;
import core.stdc.stdlib: free;
import core.stdc.math: isnan, isinf, isfinite;

import dplug.core.nogc;
import dplug.core.runtime;
import dplug.core.vec;
import dplug.core.sync;

import dplug.client.client;
import dplug.client.params;
import dplug.client.graphics;
import dplug.client.daw;
import dplug.client.preset;
import dplug.client.midi;

import dplug.clap.types;

//debug = clap;
debug(clap) import core.stdc.stdio;

nothrow @nogc:

// TODO https://github.com/free-audio/clap/blob/main/include/clap/ext/audio-ports-config.h
// else not possible in theory to have both mono and stereo ports
class CLAPClient
{
public:
nothrow:
@nogc:

    this(Client client, const(clap_host_t)* host)
    {
        _client = client;
        _hostCommand = mallocNew!CLAPHost(this, host);

        // fill _plugin

        _plugin.desc = get_descriptor_from_client(client);
        _plugin.plugin_data = cast(void*)(cast(Object)this);
        _plugin.init             = &plugin_init;
        _plugin.destroy          = &plugin_destroy;
        _plugin.activate         = &plugin_activate;
        _plugin.deactivate       = &plugin_deactivate;
        _plugin.start_processing = &plugin_start_processing;
        _plugin.stop_processing  = &plugin_stop_processing;
        _plugin.reset            = &plugin_reset;
        _plugin.process          = &plugin_process;
        _plugin.get_extension    = &plugin_get_extension;
        _plugin.on_main_thread   = &plugin_on_main_thread;

        activated = false;
        processing = false;
    }

    ~this()
    {
        destroyFree(_client);
        destroyFree(_hostCommand);

        for (int i = 0; i < _maxInputs; ++i)
            _inputBuffers[i].destroy();
        for (int i = 0; i < _maxOutputs; ++i)
            _outputBuffers[i].destroy();
        _inputBuffers.freeSlice();
        _outputBuffers.freeSlice();
    }

    // Resize copy buffers according to maximum block size.
    void resizeScratchBuffers(int maxFrames, 
                              int inputChannels,
                              int outputChannels)
    {
        for (int i = 0; i < inputChannels; ++i)
            _inputBuffers[i].resize(maxFrames);
        for (int i = 0; i < outputChannels; ++i)
            _outputBuffers[i].resize(maxFrames);
    }

    const(clap_plugin_t)* get_clap_plugin()
    {
        return &_plugin;
    }

private:

    // Underlying generic client.
    Client _client;

    // Host access.
    CLAPHost _hostCommand;

    // Which DAW is it?
    DAW _daw; 

    // Returned to the CLAP api, it's a sort of v-table.
    clap_plugin_t _plugin;

    // plugin is "activated" (status of activate / deactivate sequence)
    bool activated;

    // plugin is "processing" (status of activate / deactivate sequence)
    bool processing;

    // true if resetFromHost must be called before next block
    bool _mustReset;

    // Last hint at sampleRate, -1 if not specified yet
    double _sampleRate = -1;

    // Current latency in samples.
    int _latencySamples = 0;

    // Current tail in samples. int.max if infinite tail.
    int _tailSamples = int.max;

    // Max frames in block., -1 if not specified yet.
    int _maxFrames = -1;

    // Max possible number of channels (should belong to Bus ideally)
    int _maxInputs;

    // Max possible number of channels (should belong to Bus ideally)
    int _maxOutputs;

    // Input and output scratch buffers, one per channel.
    Vec!float[] _inputBuffers;  
    Vec!float[] _outputBuffers;

    Vec!(float*) _inputPointers;
    Vec!(float*) _outputPointers;

    // Events that need to be sent to host at next `process`/`flush`.
    // Those need no synchronization if done from audio thread, or 
    // from main-thread outside activation.
    // However, popping from there, or pushing from a parameter listener, 
    // needs locking;
    UncheckedMutex _pendingEventsMutex;
    Vec!clap_event_any_t _pendingEvents;

    // Note: REAPER doesn't like parameters with -inf as minimum value.
    // It will react by sending NaNs around.
    // What we do for FloatParameter is expose them as normalized floats.
    // This helps UI-less programs to have more meaningful mapping.
    Vec!bool expose_param_as_normalized;

    // Implement methods of clap_plugin_t using the C trampolines

    // Must be called after creating the plugin.
    // If init returns false, the host must destroy the plugin instance.
    // If init returns true, then the plugin is initialized and in the deactivated state.
    // Unlike in `plugin-factory::create_plugin`, in init you have complete access to the host 
    // and host extensions, so clap related setup activities should be done here rather than in
    // create_plugin.
    // [main-thread]
    bool initFun()
    {
        _client.setHostCommand(_hostCommand);

        // Detect DAW here
        _daw = _hostCommand.getDAW();

        expose_param_as_normalized.resize(_client.params.length);
        expose_param_as_normalized.fill(false);

        // Create the bus configuration.
        _maxInputs = _client.maxInputs();
        _maxOutputs = _client.maxOutputs();
        bool receivesMIDI = _client.receivesMIDI();
        bool sendsMIDI = _client.sendsMIDI();

        // Note: extrapolate buses from just channel count (:

        if (_maxInputs)
        {
            Bus b;
            b.isMain = true;
            b.isActive = true;
            b.name = "Input";
            b.numChannels = _maxInputs;
            audioInputs.pushBack(b);
        }

        if (_maxOutputs)
        {
            Bus b;
            b.isMain = true;
            b.isActive = true;
            b.name = "Output";
            b.numChannels = _maxOutputs;
            audioOutputs.pushBack(b);
        }

        if (receivesMIDI)
        {
            NoteBus b;
            noteInputs.pushBack(b);
        }

        if (sendsMIDI)
        {
            NoteBus b;
            noteOutputs.pushBack(b);
        }

        _inputBuffers  = mallocSlice!(Vec!float)(_maxInputs);
        _outputBuffers = mallocSlice!(Vec!float)(_maxOutputs);
        return true;
    }

    // Free the plugin and its resources.
    // It is required to deactivate the plugin prior to this call.
    // [main-thread & !active]
    void destroyFun()
    {
        destroyFree(this);
    }

    // Activate and deactivate the plugin.
    // In this call the plugin may allocate memory and prepare everything needed for the process
    // call. The process's sample rate will be constant and process's frame count will included in
    // the [min, max] range, which is bounded by [1, INT32_MAX].
    // Once activated the latency and port configuration must remain constant, until deactivation.
    // Returns true on success.
    // [main-thread & !active]
    bool activate(double sample_rate, uint min_frames_count, uint max_frames_count)
    {
        if (max_frames_count > int.max)
            return false;

        // Note: We can assume we already know the port configuration!
        //       CLAP host are strictly typed and host follow the constraints.
        // And no synchronization needed, since the plugin is deactivated.
        _sampleRate = sample_rate;
        _maxFrames = assumeNoOverflow(max_frames_count);
        activated = true;
        clientReset();

        // Set latency. Tells the host to check latency immediately.
        _latencySamples = _client.latencySamples(_sampleRate);
        _hostCommand.notifyLatencyChanged();

        // Set tail size.
        float tailSizeInSeconds = _client.tailSizeInSeconds();
        assert(tailSizeInSeconds >= 0);
        if (isinf(tailSizeInSeconds))
        {
            _tailSamples = int.max;
        }
        else
        {
            long samples = cast(long)(0.5 + tailSizeInSeconds * _sampleRate);
            if (samples > int.max)
                samples = int.max;
            _tailSamples = cast(int)(samples);
        }
         _hostCommand.notifyTailChanged();
        return true;
    }

    void clientReset()
    {
        // We're at a point we know everything about port 
        // configurations. (re)initialize the client.
        Bus* ibus = getMainInputBus();
        Bus* obus = getMainOutputBus();
        int numInputs  = ibus ? ibus.numChannels : 0;
        int numOutputs = obus ? obus.numChannels : 0;
        _client.resetFromHost(_sampleRate, _maxFrames, numInputs, numOutputs);

        // Allocate space for scratch buffers
        resizeScratchBuffers(_maxFrames, numInputs, numOutputs);
        _inputPointers.resize(numInputs);
        _outputPointers.resize(numOutputs);
    }

    void deactivate()
    {
        activated = true;
    }

    // Call start processing before processing.
    // Returns true on success.
    // [audio-thread & active & !processing]
    bool start_processing()
    {
        processing = true;
        return true;
    }

    // Call stop processing before sending the plugin to sleep.
    // [audio-thread & active & processing]
    void stop_processing()
    {
        processing = false;
    }

    // - Clears all buffers, performs a full reset of the processing state (filters, oscillators,
    //   envelopes, lfo, ...) and kills all voices.
    // - The parameter's value remain unchanged.
    // - clap_process.steady_time may jump backward.
    //
    // [audio-thread & active]
    void reset()
    {
        // TBH I don't remember a similar function from other APIs.
        // Dplug doesn't have that semantic (it's just initialize 
        // + process, no separate reset call)
        // Since activate can potentially change sample-rate and 
        // allocate, we can simply call our .reset again
        clientReset();
    }

    clap_process_status process(const(clap_process_t)* processParams)
    {
        // It seems the number of ports and channels is discovered here
        // as last resort.

        // 0. First, process incoming events.
        if (processParams)
        {
            if (processParams.in_events)
                processInputEvents(processParams.in_events);
        }

        int inputPorts = processParams.audio_inputs_count;
        int outputPorts = processParams.audio_outputs_count;

        if (processParams.frames_count > int.min)
            return CLAP_PROCESS_ERROR;
        int frames = assumeNoOverflow(processParams.frames_count);

        // 1. Check number of buses we agreed upon with the host
        if (inputPorts != audioInputs.length) 
            return CLAP_PROCESS_ERROR;
        if (outputPorts != audioOutputs.length) 
            return CLAP_PROCESS_ERROR;

        // 2. Check number of channels we agreed upon with the host
        for (int n = 0; n < inputPorts; ++n)
        {
            int expected = getInputBus(n).numChannels;
            int got = processParams.audio_inputs[n].channel_count;
            if (got != expected) return CLAP_PROCESS_ERROR;
        }
        for (int n = 0; n < outputPorts; ++n)
        {
            int expected = getOutputBus(n).numChannels;
            int got = processParams.audio_outputs[n].channel_count;
            if (got != expected) return CLAP_PROCESS_ERROR;
        }

        Bus* ibus = getMainInputBus();
        Bus* obus = getMainOutputBus();
        int numInputs  = ibus ? ibus.numChannels : 0;
        int numOutputs = obus ? obus.numChannels : 0;
                

        // 3. Fetch input audio in input buffers
        if (numInputs)
        {
            int chans = ibus.numChannels;
            for (int chan = 0; chan < chans; ++chan)
            {
                const(float)* source = processParams.audio_inputs[0].data32[chan];
                float* dest = _inputBuffers[chan].ptr;
                memcpy(dest, source, float.sizeof * frames);
            }
        }

        // 4. Process audio
        {
            for (int n = 0; n < numInputs; ++n)
                _inputPointers[n] = _inputBuffers[n].ptr;
            for (int n = 0; n < numOutputs; ++n)
                _outputPointers[n] = _outputBuffers[n].ptr;
            TimeInfo timeInfo;

            // TODO: per-subbuffer parameter changes like in VST3
            _client.processAudioFromHost(_inputPointers[0..numInputs], 
                                         _outputPointers[0..numInputs], 
                                         frames,
                                         timeInfo);
        }

        // 5. Copy to output
        if (numOutputs)
        {
            int chans = obus.numChannels;
            for (int chan = 0; chan < chans; ++chan)
            {
                float* dest = cast(float*) processParams.audio_outputs[0].data32[chan];
                const(float)* source= _outputBuffers[chan].ptr;
                memcpy(dest, source, float.sizeof * frames);
            }
        }

        // 6. Lastly, process output events.
        if (processParams)
        {
            if (processParams.out_events)
                processOutputEvents(processParams.out_events);
        }

        // Note: CLAP can expose more internal state, such as tail, 
        // process only non-silence etc. It is of course 
        // underdocumented.
        // However a realistic plug-in will implement silence 
        // detection for the other formats as well.
        return CLAP_PROCESS_CONTINUE;
    }

    // aka QueryInterface for the people
    void* get_extension(const(char)* s)
    {
        if (strcmp(s, "clap.params") == 0)
        {
            __gshared clap_plugin_params_t api;
            api.count         = &plugin_params_count;
            api.get_info      = &plugin_params_get_info;
            api.get_value     = &plugin_params_get_value;
            api.value_to_text = &plugin_params_value_to_text;
            api.text_to_value = &plugin_params_text_to_value;
            api.flush         = &plugin_params_flush;
            return &api;
        }

        if (strcmp(s, "clap.audio-ports") == 0)
        {
            __gshared clap_plugin_audio_ports_t api;
            api.count = &plugin_audio_ports_count;
            api.get = &plugin_audio_ports_get;
            return &api;
        }

        if (_client.hasGUI() && strcmp(s, "clap.gui") == 0)
        {
            __gshared clap_plugin_gui_t api;
            api.is_api_supported = &plugin_gui_is_api_supported;
            api.get_preferred_api = &plugin_gui_get_preferred_api;
            api.create = &plugin_gui_create;
            api.destroy = &plugin_gui_destroy;
            api.set_scale = &plugin_gui_set_scale;
            api.get_size = &plugin_gui_get_size;
            api.can_resize = &plugin_gui_can_resize;
            api.get_resize_hints = &plugin_gui_get_resize_hints;
            api.adjust_size = &plugin_gui_adjust_size;
            api.set_size = &plugin_gui_set_size;
            api.set_parent = &plugin_gui_set_parent;
            api.set_transient = &plugin_gui_set_transient;
            api.suggest_title = &plugin_gui_suggest_title;
            api.show = &plugin_gui_show;
            api.hide = &plugin_gui_hide;
            return &api;
        }

        if (strcmp(s, "clap.latency") == 0)
        {
            __gshared clap_plugin_latency_t api;
            api.get = &plugin_latency_get;
            return &api;
        }

        // Note: nothing in the spec forces the host to save session 
        // using the extension but as plug-in we assume that is the 
        // case, the host MUST use clap.state if present.
        if (strcmp(s, "clap.state") == 0)
        {
            __gshared clap_plugin_state_t api;
            api.save = &plugin_state_save;
            api.load = &plugin_state_load;
            return &api;
        }

        if ( (strcmp(s, CLAP_EXT_PRESET_LOAD.ptr) == 0)
          || (strcmp(s, CLAP_EXT_PRESET_LOAD_COMPAT.ptr) == 0) )
        {
            __gshared clap_plugin_preset_load_t api;
            api.from_location = &plugin_preset_load_from_location;
            return &api;
        }

        if (strcmp(s, CLAP_EXT_AUDIO_PORTS_CONFIG.ptr) == 0)
        {
            __gshared clap_plugin_audio_ports_config_t api;
            api.count  = &plugin_ports_config_count;
            api.get    = &plugin_ports_config_get;
            api.select = &plugin_ports_config_select;
            return &api;
        }

        if ( (strcmp(s, CLAP_EXT_AUDIO_PORTS_CONFIG_INFO.ptr) == 0)
          || (strcmp(s, CLAP_EXT_AUDIO_PORTS_CONFIG_INFO_COMPAT.ptr) == 0) )
        {
            __gshared clap_plugin_audio_ports_config_info_t api;
            api.current_config = &plugin_ports_current_config;
            api.get = &plugin_ports_config_info_get;
            return &api;
        }

        if (strcmp(s, CLAP_EXT_NOTE_PORTS.ptr) == 0)
        {
            __gshared clap_plugin_note_ports_t api;
            api.count = &plugin_note_ports_count;
            api.get   = &plugin_note_ports_get;
            return &api;
        }

        // extension not supported
        return null;
    }

    // clap.params interface implementation

    uint convertParamIndexToParamID(uint param_index)
    {
        return param_index;
    }

    uint convertParamIDToParamIndex(uint param_id)
    {
        return param_id;
    }

    uint params_count()
    {
        return cast(uint) _client.params().length;
    }

    bool params_get_info(uint param_index, clap_param_info_t* param_info)
    {
        // DPlug note about parameter IDs.
        // Clap parameters IDs are defined as indexes in uint form.
        // To have better IDs, would need Dplug support for custom parameters IDs,
        // that would still be `uint`. Could then have somekind of map.
        // I don't see too much value spending time choosing those IDs, unfortunately.

        Parameter p = _client.param(param_index);
        if (!p)
            return false;

        param_info.id = convertParamIndexToParamID(param_index);

        int flags = 0;
        double min, max, def;

        if (BoolParameter bp = cast(BoolParameter)p)
        {
            flags |= CLAP_PARAM_IS_STEPPED;
            min = 0;
            max = 1;
            def = bp.defaultValue() ? 1 : 0;
        }
        else if (IntegerParameter ip = cast(IntegerParameter)p)
        {
            if (EnumParameter ep = cast(EnumParameter)p)
                flags |= CLAP_PARAM_IS_ENUM;
            flags |= CLAP_PARAM_IS_STEPPED; // truncate called
            min = ip.minValue();
            max = ip.maxValue();
            def = ip.defaultValue();
        }
        else if (FloatParameter fp = cast(FloatParameter)p)
        {
            // REAPER doesn't actually accept parameters that are -inf, 
            // but Dplug does. So we have to normalize the float params,
            // which also improve the display in UI-less plugins since
            // it's mapped as the programmer intended.
            flags |= 0;
            expose_param_as_normalized[param_index] = true;
            min = 0;
            max = 1.0;
            def = fp.getNormalizedDefault();
        }
        else
            assert(false);

        if (p.isAutomatable) flags |= CLAP_PARAM_IS_AUTOMATABLE;

        // Note: all Dplug parameters supposed to requires process.
        flags |= CLAP_PARAM_REQUIRES_PROCESS;

        param_info.flags = flags;
        param_info.min_value = min;
        param_info.max_value = max;
        param_info.default_value = def;
        param_info.cookie = null;//cast(void*) p; // fast access cookie

        p.toNameN(param_info.name.ptr, CLAP_NAME_SIZE);

        // "" string for module name, as Dplug has a flag parameter structure :/
        param_info.module_[0] = 0;

        return true;
    }

    double paramValueForHost(Parameter p, int index)
    {
        assert(p);

        if (expose_param_as_normalized[index])
        {
            return p.getNormalized();
        }

        if (BoolParameter bp = cast(BoolParameter)p)
            return bp.value() ? 1.0 : 0.0;
        else if (IntegerParameter ip = cast(IntegerParameter)p)
            return ip.value();
        else if (FloatParameter fp = cast(FloatParameter)p)
            return fp.value();
        else
            assert(false);
    }

    bool params_get_value(clap_id param_id, double *out_value)
    {
        uint idx = convertParamIDToParamIndex(param_id);
        Parameter p = _client.param(idx);
        if (!p)
            return false;

        *out_value = paramValueForHost(p, idx);

        assert(!isnan(*out_value));
        return true;
    }

    final double normalizeParamValue(Parameter p, double value)
    {
        assert(!isnan(value));

        double normalized;
        if (BoolParameter bp = cast(BoolParameter)p)
            normalized = value;
        else if (IntegerParameter ip = cast(IntegerParameter)p)
            normalized = ip.toNormalized(cast(int)value); 
        else if (FloatParameter fp = cast(FloatParameter)p)
        {
            normalized = fp.toNormalized(value);
        }            
        else
            assert(false);
        return normalized;
    }

    // eg: "2.3 kHz"
    bool params_value_to_text(
                       clap_id              param_id,
                       double               value,
                       char                *out_buffer,
                       uint                out_buffer_capacity)
    {
        uint idx = convertParamIDToParamIndex(param_id);
        Parameter p = _client.param(idx);
        if (!p)
            return false;

        // 1. Find corresponding normalized value
        double normalized = value;
        if (!expose_param_as_normalized[idx]) 
            normalized = normalizeParamValue(p, value);

        // 2. Find text corresponding to that
        char[CLAP_NAME_SIZE] str;
        char[CLAP_NAME_SIZE] label;

        p.stringFromNormalizedValue(normalized, str.ptr, CLAP_NAME_SIZE);
        p.toLabelN(label.ptr, CLAP_NAME_SIZE);
        if (strlen(label.ptr))
            snprintf(out_buffer, out_buffer_capacity, "%s %s", str.ptr, label.ptr);
        else
            snprintf(out_buffer, out_buffer_capacity, "%s", str.ptr);
        return true;
    }

    bool params_text_to_value(
                  clap_id              param_id,
                  const(char)         *param_value_text,
                  double              *out_value)
    {
        uint idx = convertParamIDToParamIndex(param_id);
        Parameter p = _client.param(idx);
        if (!p)
            return false;

        size_t len = strlen(param_value_text);

        double normalized;
        if (p.normalizedValueFromString(param_value_text[0..len], normalized))
        {
            if (expose_param_as_normalized[idx])
            {
                *out_value = normalized;
                return true;
            }

            if (BoolParameter bp = cast(BoolParameter)p)
                *out_value = normalized;
            else if (IntegerParameter ip = cast(IntegerParameter)p)
                // in a better Dplug timeline, normalized value wouldn't exist in generic client
                *out_value = ip.fromNormalized(normalized); 
            else if (FloatParameter fp = cast(FloatParameter)p)
                *out_value = fp.fromNormalized(normalized);
            else
                assert(false);
            return true;
        }
        else
            return false;
    }

    // Flushes a set of parameter changes.
    // This method must not be called concurrently to clap_plugin->process().
    //
    // Note: if the plugin is processing, then the process() call will already achieve the
    // parameter update (bi-directional), so a call to flush isn't required, also be aware
    // that the plugin may use the sample offset in process(), while this information would be
    // lost within flush().
    //
    // [active ? audio-thread : main-thread]
    void params_flush(const(clap_input_events_t)  *in_,
                      const(clap_output_events_t) *out_)
    {
        processInputEvents(in_);
        processOutputEvents(out_);
    }

    void processInputEvents(const(clap_input_events_t)  *in_)
    {
        if (in_ == null)
            return;

        if (in_.size == null)
            return;

        // Manage incoming messages from host.
        uint size = in_.size(in_);

        for (uint n = 0; n < size; ++n)
        {
            const(clap_event_header_t)* hdr = in_.get(in_, n);
            if (!hdr) continue;
            if (hdr.space_id != 0) continue; 

            switch(hdr.type)
            {
                case CLAP_EVENT_NOTE_ON: 
                    //TODO
                    break;
                case CLAP_EVENT_NOTE_OFF:
                    //TODO
                    break;
                case CLAP_EVENT_NOTE_CHOKE:
                    //TODO
                    break;
                case CLAP_EVENT_NOTE_END:
                    //TODO
                    break;
                case CLAP_EVENT_PARAM_VALUE:
                    if (hdr.size < clap_event_param_value_t.sizeof) 
                        break;
                    const(clap_event_param_value_t)* ev = cast(const(clap_event_param_value_t)*) hdr;

                    int index = convertParamIDToParamIndex(ev.param_id);
                    Parameter param = _client.param(index);
                    if (!param)
                        break;

                    // Note: assuming wildcard here. For proper handling, Dplug would have to 
                    // maintain values of parameters for many combination, which is ridiculous.
                    // Note: param value is not normalized, so we have to first normalize it.
                    double normalized = ev.value;
                    if (!expose_param_as_normalized[index])
                        normalized = normalizeParamValue(param, ev.value);
                    param.setFromHost(normalized);
                    break;

                case CLAP_EVENT_PARAM_MOD:
                    // Not supported by our CLAP client.
                    break;
                case CLAP_EVENT_PARAM_GESTURE_BEGIN:
                case CLAP_EVENT_PARAM_GESTURE_END: 
                    // something to use rather in output 
                    // FAR FUTURE: should this "hover" the params in the UI?
                    break;

                case CLAP_EVENT_TRANSPORT:
                    // TODO
                    break;
                case CLAP_EVENT_MIDI:
                    // TODO
                    break;
                case CLAP_EVENT_MIDI_SYSEX:
                    // TODO
                    break;
                case CLAP_EVENT_MIDI2:
                    // No support in Dplug
                    break;
                default:
            }
        }
    }

    void processOutputEvents(const(clap_output_events_t)  *out_)
    {
        _pendingEventsMutex.lockLazy();

        size_t len = _pendingEvents.length;
        for (size_t n = 0; n < len; ++n)
        {
            // Note: CLAP doesn't specify who own the sysex buffer
            // and with what lifetime. So no sysex support here.

            clap_event_any_t* any = &_pendingEvents[n];

            // Nothing says the parameters will be copied...
            // But I don't see what to do if they don't.
            bool ok = out_.try_push(out_, cast(clap_event_header_t*) any);
        }
        _pendingEvents.clearContents();
        _pendingEventsMutex.unlock();
    }

    void enqueueParamBeginEdit(Parameter param)
    {
        clap_event_any_t evt;
        evt.param_gesture.header.size     = clap_event_param_gesture_t.sizeof;
        evt.param_gesture.header.time     = 0; // ASAP, those event comes from state chunks or UI
        evt.param_gesture.header.space_id = 0;
        evt.param_gesture.header.type     = CLAP_EVENT_PARAM_GESTURE_BEGIN;
        evt.param_gesture.header.flags    = 0; // record automation, and not a live event
        evt.param_gesture.param_id        = convertParamIndexToParamID(param.index);
        _pendingEventsMutex.lockLazy();
        _pendingEvents.pushBack(evt);
        _pendingEventsMutex.unlock();
    }

    void enqueueParamEndEdit(Parameter param)
    {
        clap_event_any_t evt;
        evt.param_gesture.header.size     = clap_event_param_gesture_t.sizeof;
        evt.param_gesture.header.time     = 0; // ASAP, those event comes from state chunks or UI
        evt.param_gesture.header.space_id = 0;
        evt.param_gesture.header.type     = CLAP_EVENT_PARAM_GESTURE_END;
        evt.param_gesture.header.flags    = 0; // record automation, and not a live event
        evt.param_gesture.param_id        = convertParamIndexToParamID(param.index);
        _pendingEventsMutex.lockLazy();
        _pendingEvents.pushBack(evt);
        _pendingEventsMutex.unlock();
    }

    void enqueueParamChange(Parameter param)
    {
        clap_event_any_t evt;
        evt.param_value.header.size     = clap_event_param_value_t.sizeof;
        evt.param_value.header.time     = 0; // ASAP, those event comes from state chunks or UI
        evt.param_value.header.space_id = 0;
        evt.param_value.header.type     = CLAP_EVENT_PARAM_VALUE;
        evt.param_value.header.flags    = 0; // record automation, and not a live event
        evt.param_value.param_id        = convertParamIndexToParamID(param.index);
        evt.param_value.cookie          = null;
        evt.param_value.note_id         = -1;
        evt.param_value.port_index      = -1;
        evt.param_value.channel         = -1;
        evt.param_value.key             = -1;
        evt.param_value.value           = paramValueForHost(param, param.index);
        _pendingEventsMutex.lockLazy();
        _pendingEvents.pushBack(evt);
        _pendingEventsMutex.unlock();
    }

    // clap.audio-ports utils
    static struct Bus
    {
        bool isMain;
        bool isActive;
        string name;
        int numChannels; // current channel count
    }
    Vec!Bus audioInputs;
    Vec!Bus audioOutputs;
    Bus* getBus(bool is_input, uint index)
    {
        if (is_input)
        {
            if (index >= audioInputs.length) return null;
            return &audioInputs[index];
        }
        else
        {
            if (index >= audioOutputs.length) return null;
            return &audioOutputs[index];
        }
    }
    Bus* getInputBus(int n) { return getBus(true, n); } 
    Bus* getOutputBus(int n) { return getBus(false, n); } 
    Bus* getMainInputBus() { return getBus(true, 0); } 
    Bus* getMainOutputBus() { return getBus(false, 0); } 

    uint convertBusIndexToBusID(uint index) { return index; }
    uint convertBusIDToBusIndex(uint id) { return id; }


    // clap.note-ports utils
    static struct NoteBus
    {
        int dummy;
    }
    Vec!NoteBus noteInputs;
    Vec!NoteBus noteOutputs;
    NoteBus* getNoteBus(bool is_input, uint index)
    {
        if (is_input)
        {
            if (index >= noteInputs.length) return null;
            return &noteInputs[index];
        }
        else
        {
            if (index >= noteOutputs.length) return null;
            return &noteOutputs[index];
        }
    }


    // audio-ports impl

    uint audio_ports_count(bool is_input)
    {
        if (is_input)
            return cast(uint) audioInputs.length;
        else
            return cast(uint) audioOutputs.length;
    }

    bool audio_ports_get(uint index,
                         bool is_input,
                         clap_audio_port_info_t *info)
    {
        Bus* b = getBus(is_input, index);
        if (!b)
            return false;

        info.id = convertBusIndexToBusID(index);
        snprintf(info.name.ptr, CLAP_NAME_SIZE, "%.*s", 
                 cast(int)(b.name.length), b.name.ptr);
        
        info.flags = 0;
        if (b.isMain)
            info.flags |= CLAP_AUDIO_PORT_IS_MAIN;
        info.channel_count = b.numChannels;

        info.port_type = portTypeChans(b.numChannels);
        info.in_place_pair = CLAP_INVALID_ID; // true luxury is letting the host deal with that
        return true;
    }

    // gui implementation
    bool gui_is_api_supported(const(char)*api, bool is_floating)
    {
        if (is_floating) return false;
        version(Windows) return (strcmp(api, CLAP_WINDOW_API_WIN32.ptr) == 0);
        version(OSX)     return (strcmp(api, CLAP_WINDOW_API_COCOA.ptr) == 0);
        version(linux)   return (strcmp(api, CLAP_WINDOW_API_X11.ptr)   == 0);
        return false;
    }

    bool gui_get_preferred_api(const(char)** api, bool* is_floating) 
    {
        *is_floating = false;
        version(Windows) { *api = CLAP_WINDOW_API_WIN32.ptr; return true; }
        version(OSX)     { *api = CLAP_WINDOW_API_COCOA.ptr; return true; }
        version(linux)   { *api = CLAP_WINDOW_API_X11.ptr;   return true; }
        return false;
    }

    GraphicsBackend gui_backend       = GraphicsBackend.autodetect;
    bool gui_apiWorksInPhysicalPixels = false;
    double gui_scale                  = 1.0;
    void* gui_parent_handle           = null;
    UncheckedMutex _graphicsMutex;

    // Note: normally such a mutex is useless, as 
    // all gui extension function are called from main-thread, 
    // says CLAP spec.
    enum string GraphicsMutexLock =
        `_graphicsMutex.lockLazy();
         scope(exit) _graphicsMutex.unlock();`;

    bool gui_create(const(char)* api, bool is_floating)
    {
        mixin(GraphicsMutexLock);
        // This doesn't allocate things, we wait for full information and
        // will only create the window on first open.

        version(Windows)
            if (strcmp(api, CLAP_WINDOW_API_WIN32.ptr) == 0)
            {
                gui_backend = GraphicsBackend.win32;
                gui_apiWorksInPhysicalPixels = true;
                return true;
            }

        version(OSX)
            if (strcmp(api, CLAP_WINDOW_API_COCOA.ptr) == 0)
            {
                gui_backend = GraphicsBackend.cocoa;
                gui_apiWorksInPhysicalPixels = false;
                return true;
            }

        version(linux)
            if (strcmp(api, CLAP_WINDOW_API_X11.ptr) == 0)
            {
                gui_backend = GraphicsBackend.x11;
                gui_apiWorksInPhysicalPixels = true;
                return true;
            }
        return false;
    }

    void gui_destroy()
    {
        mixin(GraphicsMutexLock);
        _client.closeGUI();
    }

    bool gui_set_scale(double scale)
    {
        mixin(GraphicsMutexLock);
        gui_scale = scale; // Note: we currently do nothing with that information.
        return true;
    }

    bool gui_get_size(uint *width, uint *height)
    {
        mixin(GraphicsMutexLock);
        // FUTURE: physical vs logical?
        int widthLogical, heightLogical;
        
        if (!_client.getGUISize(&widthLogical, &heightLogical))
            return false;

        if (widthLogical < 0 || heightLogical < 0)
            return false;

        *width = widthLogical;
        *height = heightLogical;
        return true;
    }

    bool gui_can_resize()
    {
        mixin(GraphicsMutexLock);
        return _client.getGraphics().isResizeable();
    }

    bool gui_get_resize_hints(clap_gui_resize_hints_t *hints)
    {
        mixin(GraphicsMutexLock);
        hints.can_resize_horizontally = _client.getGraphics().isResizeableHorizontally();
        hints.can_resize_vertically = _client.getGraphics().isResizeableVertically();
        hints.preserve_aspect_ratio = _client.getGraphics().isAspectRatioPreserved();
        int[2] AR = _client.getGraphics().getPreservedAspectRatio();
        hints.aspect_ratio_width = AR[0];
        hints.aspect_ratio_height = AR[1];
        return true;
    }

    bool gui_adjust_size(uint *width, uint *height)
    {
        mixin(GraphicsMutexLock);
        // FUTURE: physical vs logical?
        int w = *width;
        int h = *height;
        if (w < 0 || h < 0) return false;
        _client.getGraphics().getMaxSmallerValidSize(&w, &h);
        if (w < 0 || h < 0) return false;
        *width  = w;
        *height = h;
        return true;
    }

    bool gui_set_size(uint width, uint height)
    {
        mixin(GraphicsMutexLock);
        // FUTURE: physical vs logical?
        return _client.getGraphics().nativeWindowResize(width, height);
    }

    bool gui_set_parent(const(clap_window_t)* window)
    {
        mixin(GraphicsMutexLock);
        gui_parent_handle = cast(void*)(window.ptr);
        return true;
    }

    bool gui_set_transient(const(clap_window_t)* window)
    {
        // no support
        return false;
    }

    void gui_suggest_title(const(char)* title)
    {
    }

    bool gui_show()
    {
        mixin(GraphicsMutexLock);
        _client.openGUI(gui_parent_handle, null, gui_backend);
        return true;
    }

    bool gui_hide()
    {
        mixin(GraphicsMutexLock);
        _client.closeGUI();
        return true;
    }

    // state impl

    Vec!ubyte _lastChunkLoad;
    UncheckedMutex _stateMutex; // clap-validator calls save() and load() at the same time
    enum string StateMutexLock =
        `_stateMutex.lockLazy();
        scope(exit) _stateMutex.unlock();`;

    bool state_save(const(clap_ostream_t)* stream)
    {
        mixin(StateMutexLock);
        
        // PERF: could amortize alloc with appendStateChunkFromCurrentState
        assert(stream);
        ubyte[] state = _client.presetBank.getStateChunkFromCurrentState();
        assert(state);

        if (state.length > uint.max)
            return false; // absurd long chunk

        // write size of chunk
        uint size = cast(uint)state.length;
        version(LittleEndian)
            writeExactly(stream, &size, uint.sizeof);
        else
            static assert(false);

        // write chunk
        writeExactly(stream, state.ptr, state.length);

        free(state.ptr);
        return true;
    }

    bool state_load(const(clap_istream_t)* stream)
    {
        mixin(StateMutexLock);
        assert(stream);

        // read size of chunk
        uint size = 0;
        if (readExactly(stream, &size, uint.sizeof) != uint.sizeof)
            return false;

        version(LittleEndian)
        {}
        else
            static assert(false);

        // Note sure if we should load chunk with zero size,
        // OTOH those chunk probably won't ever exist.
        if (size == 0)
            return true;

        // read chunk
        _lastChunkLoad.resize(size);
        if (readExactly(stream, _lastChunkLoad.ptr, size) == size)
        {
            // apply chunk
            bool err = false;

            _client.presetBank.loadStateChunk(_lastChunkLoad[], &err);
            if (err)
                return false;

            // Ask for param value rescan.
            _hostCommand.notifyRequestParamRescan(CLAP_PARAM_RESCAN_VALUES);
            return true;
        }
        else
            return false;
    }

    // preset-load impl

    bool preset_load_from_location(uint location_kind,
                                   const(char)* location,
                                   const(char)* load_key)
    {
        int index;

        if (location_kind != CLAP_PRESET_DISCOVERY_LOCATION_PLUGIN)
            goto error;

        // Same remark as for indexing: MultiTrackStudio sends non-null
        // location, ignore that.

        if (sscanf(load_key, "%d", &index) != 1)
            goto error;
        if (index < 0 || index > _client.presetBank.numPresets)
            goto error;

        _client.presetBank.loadPresetFromHost(index);

        _hostCommand.notifyPresetLoaded(location_kind,
                                        location,
                                        load_key);
        // Ask for param value rescan.
        _hostCommand.notifyRequestParamRescan(CLAP_PARAM_RESCAN_VALUES);
        return true;

    error:
        _hostCommand.notifyPresetError(location_kind,
                                        location,
                                        load_key,
                                        0,
                                        "Couldn't load preset");
        return false;
    }


    // audio-ports-config impl

    uint ports_config_count()
    {   
        LegalIO[] legalIOs = _client.legalIOs();
        return cast(uint) (legalIOs.length);
    }

    bool ports_config_get(uint index,
                          clap_audio_ports_config_t* config)
    {
        LegalIO[] legalIOs = _client.legalIOs();
        if (index >= legalIOs.length)
            return false;

        LegalIO* io = &legalIOs[index];

        with (config)
        {
            id = index;
            // Call that "2-2" for stereo, etc
            snprintf(name.ptr, CLAP_NAME_SIZE, "%d-%d", 
                     io.numInputChannels, io.numOutputChannels);
            int inChannels  = io.numInputChannels;
            int outChannels = io.numOutputChannels;
            input_port_count  = inChannels  ? 1 : 0;
            output_port_count = outChannels ? 1 : 0;
            has_main_input  = (inChannels != 0);
            has_main_output = (outChannels != 0);
            main_input_channel_count  = inChannels;
            main_output_channel_count = outChannels;
            main_input_port_type  = portTypeChans(inChannels);
            main_output_port_type = portTypeChans(outChannels);
        }
        return true;
    }

    static const(char)* portTypeChans(int channels) pure
    {
        switch(channels)
        {
            case 1: return CLAP_PORT_MONO.ptr;
            case 2: return CLAP_PORT_STEREO.ptr;
            default:
                // no support yet for ambisonic or surround
                return null; 
        }
    }

    bool ports_config_select(clap_id config_id)
    {
        LegalIO[] legalIOs = _client.legalIOs();
        uint index = config_id;
        if (index >= legalIOs.length)
            return false;

        LegalIO* io = &legalIOs[index];
        Bus* mainIn = getMainInputBus();
        Bus* mainOut = getMainOutputBus();

        // FUTURE: this would set the number of channels in SC too
        if (mainIn) mainIn.numChannels = io.numInputChannels;
        if (mainOut) mainOut.numChannels = io.numOutputChannels;
        return true;
    }

    clap_id ports_current_config()
    {
        LegalIO[] legalIOs = _client.legalIOs();
        Bus* mainIn = getMainInputBus();
        Bus* mainOut = getMainOutputBus();
        int inChannels = 0;
        int outChannels = 0;
        if (mainIn)  inChannels  = mainIn.numChannels;
        if (mainOut) outChannels = mainOut.numChannels;
        foreach(size_t nth, ref io; legalIOs)
        {
            if ( (io.numInputChannels == inChannels)
              && (io.numOutputChannels == outChannels) )
                return cast(clap_id)nth;
        }
        return CLAP_INVALID_ID;
    }

    bool ports_config_info_get(clap_id config_id,
                               uint    port_index,
                               bool    is_input,
                               clap_audio_port_info_t *info)
    {
        LegalIO[] legalIOs = _client.legalIOs();
        uint index = config_id;
        if (index >= legalIOs.length)
            return false;
        LegalIO* io = &legalIOs[index];
        Bus* b = getBus(is_input, port_index);
        if (!b)
            return false;

        info.id = convertBusIndexToBusID(port_index);
        snprintf(info.name.ptr, CLAP_NAME_SIZE, "%.*s", 
                 cast(int)(b.name.length), b.name.ptr);

        info.flags = 0;
        if (b.isMain)
            info.flags |= CLAP_AUDIO_PORT_IS_MAIN;
        info.channel_count = is_input ? io.numInputChannels
                                      : io.numOutputChannels;

        info.port_type = portTypeChans(info.channel_count);
        info.in_place_pair = CLAP_INVALID_ID; // true luxury is letting the host deal with that
        return true;
    }

    // note-ports impl
    uint note_ports_count(bool is_input)
    {
        if (is_input)
            return cast(uint) noteInputs.length;
        else
            return cast(uint) noteOutputs.length;
    }

    bool note_ports_get(uint index,
                        bool is_input,
                        clap_note_port_info_t *info) 
    {
        NoteBus* bus = getNoteBus(is_input, index);
        if (!bus) 
            return false;
        with(info)
        {
            id = convertBusIndexToBusID(index);
            supported_dialects = CLAP_NOTE_DIALECT_MIDI;
            preferred_dialect = CLAP_NOTE_DIALECT_MIDI;
            snprintf(name.ptr, CLAP_NAME_SIZE, "Events");
        }
        return true;
    }
}

extern(C) static
{
    enum string ClientCallback =
        `ScopedForeignCallback!(false, true) sc;
        sc.enter();
        CLAPClient client = cast(CLAPClient)(plugin.plugin_data);`;

    // plugin callbacks

    bool plugin_init(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        return client.initFun();
    }

    void plugin_destroy(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        client.destroyFun();
    }

    bool plugin_activate(const(clap_plugin_t)* plugin,
                  double                    sample_rate,
                  uint                  min_frames_count,
                  uint                  max_frames_count)
    {
        mixin(ClientCallback);
        return client.activate(sample_rate, min_frames_count, max_frames_count);
    }

    void plugin_deactivate(const(clap_plugin_t)*plugin)
    {
        mixin(ClientCallback);
        return client.deactivate();
    }

    bool plugin_start_processing(const(clap_plugin_t)*plugin) 
    {
        mixin(ClientCallback);
        return client.start_processing();
    }

    void plugin_stop_processing(const(clap_plugin_t)*plugin) 
    {
        mixin(ClientCallback);
        client.stop_processing();
    }

    void plugin_reset(const(clap_plugin_t)*plugin) 
    {
        mixin(ClientCallback);
        client.reset();
    }

    clap_process_status plugin_process(const(clap_plugin_t)*plugin, const(clap_process_t)* processParams)
    {
        mixin(ClientCallback);
        return client.process(processParams);
    }

    const(void)* plugin_get_extension(const(clap_plugin_t)*plugin, const char *id)
    {
        mixin(ClientCallback);
        return client.get_extension(id);
    }

    void plugin_on_main_thread(const(clap_plugin_t)*plugin)
    {
        // do nothing here
    }


    // clap.params callbacks

    uint plugin_params_count(const(clap_plugin_t)*plugin)
    {
        mixin(ClientCallback);
        return client.params_count();
    }

    bool plugin_params_get_info(const(clap_plugin_t)*plugin, uint param_index, clap_param_info_t* param_info)
    {
        mixin(ClientCallback);
        return client.params_get_info(param_index, param_info);
    }

    bool plugin_params_get_value(const(clap_plugin_t)*plugin, clap_id param_id, double *out_value)
    {
        mixin(ClientCallback);
        return client.params_get_value(param_id, out_value);
    }

    // eg: "2.3 kHz"
    bool plugin_params_value_to_text(const(clap_plugin_t)*plugin,
                              clap_id              param_id,
                              double               value,
                              char                *out_buffer,
                              uint                out_buffer_capacity)
    {
        mixin(ClientCallback);
        return client.params_value_to_text(param_id, value, out_buffer, out_buffer_capacity);
    }

    bool plugin_params_text_to_value(const(clap_plugin_t)*plugin,
                              clap_id              param_id,
                              const(char)         *param_value_text,
                              double              *out_value)
    {
        mixin(ClientCallback);
        return client.params_text_to_value(param_id, param_value_text, out_value);
    }

    void plugin_params_flush(const(clap_plugin_t)        *plugin,
                      const(clap_input_events_t)  *in_,
                      const(clap_output_events_t) *out_)
    {
        mixin(ClientCallback);
        return client.params_flush(in_, out_);
    }

    uint plugin_audio_ports_count(const(clap_plugin_t)* plugin, bool is_input)
    {
        mixin(ClientCallback);
        return client.audio_ports_count(is_input);
    }

    bool plugin_audio_ports_get(const(clap_plugin_t)* plugin,
                  uint index,
                  bool is_input,
                  clap_audio_port_info_t *info)
    {
        mixin(ClientCallback);
        return client.audio_ports_get(index, is_input, info);
    }


    // gui callbacks

    bool plugin_gui_is_api_supported(const(clap_plugin_t)* plugin, 
                                     const(char)*api, 
                                     bool is_floating)
    {
        mixin(ClientCallback);
        return client.gui_is_api_supported(api, is_floating);
    }

    bool plugin_gui_get_preferred_api(const(clap_plugin_t)* plugin, const(char)** api, bool* is_floating) 
    {
        mixin(ClientCallback);
        return client.gui_get_preferred_api(api, is_floating);
    }

    bool plugin_gui_create(const(clap_plugin_t)* plugin, const(char)* api, bool is_floating)
    {
        mixin(ClientCallback);
        return client.gui_create(api, is_floating);
    }

    void plugin_gui_destroy(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        return client.gui_destroy();
    }
    
    bool plugin_gui_set_scale(const(clap_plugin_t)* plugin, double scale)
    {
        mixin(ClientCallback);
        return client.gui_set_scale(scale);
    }

    bool plugin_gui_get_size(const(clap_plugin_t)* plugin, uint *width, uint *height)
    {
        mixin(ClientCallback);
        return client.gui_get_size(width, height);
    }

    bool plugin_gui_can_resize(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        return client.gui_can_resize();
    }

    bool plugin_gui_get_resize_hints(const(clap_plugin_t)* plugin, clap_gui_resize_hints_t *hints)
    {
        mixin(ClientCallback);
        return client.gui_get_resize_hints(hints);
    }

    bool plugin_gui_adjust_size(const(clap_plugin_t)* plugin, uint *width, uint *height)
    {
        mixin(ClientCallback);
        return client.gui_adjust_size(width, height);
    }

    bool plugin_gui_set_size(const(clap_plugin_t)* plugin, uint width, uint height)
    {
        mixin(ClientCallback);
        return client.gui_set_size(width, height);
    }

    bool plugin_gui_set_parent(const(clap_plugin_t)* plugin, const(clap_window_t)* window)
    {
        mixin(ClientCallback);
        return client.gui_set_parent(window);
    }

    bool plugin_gui_set_transient(const(clap_plugin_t)* plugin, const(clap_window_t)* window)
    {
        mixin(ClientCallback);
        return client.gui_set_transient(window);
    }

    void plugin_gui_suggest_title(const(clap_plugin_t)* plugin, const(char)* title)
    {
        mixin(ClientCallback);
        return client.gui_suggest_title(title);
    }

    bool plugin_gui_show(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        return client.gui_show();
    }

    bool plugin_gui_hide(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        return client.gui_hide();
    }

    // latency callbacks
    uint plugin_latency_get(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        int samples = client._latencySamples;
        assert(samples >= 0);
        return samples;
    }

    // tail callbacks
    uint plugin_tail_get(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        int samples = client._tailSamples;
        assert(samples >= 0);
        return samples;
    }

    // state callbacks

    bool plugin_state_save(const(clap_plugin_t)* plugin, const(clap_ostream_t)* stream)
    {
        mixin(ClientCallback);
        return client.state_save(stream);
    }

    bool plugin_state_load(const(clap_plugin_t)* plugin, const(clap_istream_t)* stream)
    {
        mixin(ClientCallback);
        return client.state_load(stream);
    }

    // preset-load impl
    bool plugin_preset_load_from_location(
        const(clap_plugin_t)*plugin,
        uint                 location_kind,
        const(char)         *location,
        const(char)         *load_key)
    {
        mixin(ClientCallback);
        return client.preset_load_from_location(location_kind, 
                                                location, load_key);
    }

    // audio-port-config callbacks

    uint plugin_ports_config_count(const(clap_plugin_t)* plugin)
    {
        mixin(ClientCallback);
        return client.ports_config_count();
    }

    bool plugin_ports_config_get(const(clap_plugin_t)* plugin,
                  uint index,
                  clap_audio_ports_config_t* config)
    {
        mixin(ClientCallback);
        return client.ports_config_get(index, config);
    }

    bool plugin_ports_config_select(const(clap_plugin_t)* plugin, 
                                    clap_id config_id)
    {
        mixin(ClientCallback);
        return client.ports_config_select(config_id);
    }

    // clap_plugin_audio_ports_config_info_t

    clap_id plugin_ports_current_config(const(clap_plugin_t)*plugin)
    {
        mixin(ClientCallback);
        return client.ports_current_config();
    }

    bool plugin_ports_config_info_get(const(clap_plugin_t)*plugin,
        clap_id config_id,
        uint    port_index,
        bool    is_input,
        clap_audio_port_info_t *info)
    {
        mixin(ClientCallback);
        return client.ports_config_info_get(config_id, port_index, is_input, info);
    }

    // note-ports callbacks

    uint plugin_note_ports_count(const(clap_plugin_t)* plugin, bool is_input)
    {
        mixin(ClientCallback);
        return client.note_ports_count(is_input);
    }

    // Get info about a note port.
    // Returns true on success and stores the result into info.
    // [main-thread]
    bool plugin_note_ports_get(const(clap_plugin_t)* plugin,
                               uint index,
                               bool is_input,
                               clap_note_port_info_t *info)
    {
        mixin(ClientCallback);
        return client.note_ports_get(index, is_input, info);
    }
}


// CLAP host commands

class CLAPHost : IHostCommand
{
nothrow @nogc:
    this(CLAPClient backRef, const(clap_host_t)* host)
    {
        _backRef      = backRef;
        _host         = host;
        _host_gui     = cast(clap_host_gui_t*)     host.get_extension(host, "clap.gui".ptr);
        _host_latency = cast(clap_host_latency_t*) host.get_extension(host, "clap.latency".ptr);
        _host_params  = cast(clap_host_params_t*)  host.get_extension(host, "clap.params".ptr);
        _host_tail    = cast(clap_host_tail_t*)    host.get_extension(host, "clap.tail".ptr);

        _host_preset  = cast(clap_host_preset_load_t*) host.get_extension(host, CLAP_EXT_PRESET_LOAD.ptr);
        if (!_host_preset)
            _host_preset = cast(clap_host_preset_load_t*) host.get_extension(host, CLAP_EXT_PRESET_LOAD_COMPAT.ptr);
    }

    /// Notifies the host that editing of a parameter has begun from UI side.
    override void beginParamEdit(int paramIndex)
    {
        Parameter p = _backRef._client.param(paramIndex);
        if (!p)
            return;
        _backRef.enqueueParamBeginEdit(p);
        notifyRequestFlush();
    }

    /// Notifies the host that a parameter was edited from the UI side.
    /// This enables the host to record automation.
    /// It is illegal to call `paramAutomate` outside of a `beginParamEdit`/`endParamEdit` pair.
    override void paramAutomate(int paramIndex, float value)
    {
        Parameter p = _backRef._client.param(paramIndex);
        if (!p)
            return;
        _backRef.enqueueParamChange(p);
        notifyRequestFlush();
    }

    /// Notifies the host that editing of a parameter has finished from UI side.
    override void endParamEdit(int paramIndex)
    {
        Parameter p = _backRef._client.param(paramIndex);
        if (!p)
            return;
        _backRef.enqueueParamEndEdit(p);
        notifyRequestFlush();
    }

    /// Requests to the host a resize of the plugin window's PARENT window, given logical pixels of plugin window.
    ///
    /// Note: UI widgets and plugin format clients have different coordinate systems.
    ///
    /// Params:
    ///     width New width of the plugin, in logical pixels.
    ///     height New height of the plugin, in logical pixels.
    /// Returns: `true` if the host parent window has been resized.
    override bool requestResize(int widthLogicalPixels, int heightLogicalPixels)
    {
        if (!_host_gui)
            return false;
        if (widthLogicalPixels < 0 || heightLogicalPixels < 0)
            return false;
        return _host_gui.request_resize(_host, widthLogicalPixels, heightLogicalPixels);
    }

    override bool notifyResized()
    {
        return false;
    }

    void notifyRequestFlush()
    {
        // says to the host to call flush or process, so that input
        // and output events can be processed
        if (_host_params)
            _host_params.request_flush(_host);
    }

    void notifyRequestParamRescan(clap_param_rescan_flags flags)
    {
        // says to the host to rescan parameters
        if (_host_params)
            _host_params.rescan(_host, flags);
    }

    // Tell the host the latency changed while activated.
    bool notifyLatencyChanged()
    {
        if (_host_latency)
        {
            _host_latency.changed(_host);
            return true;
        }
        else
            return false;
    }

    // Tell the host the tail size changed.
    bool notifyTailChanged()
    {
        if (_host_tail)
        {
            _host_tail.changed(_host);
            return true;
        }
        else 
            return false;
    }

    void notifyPresetLoaded(uint location_kind,
                            const(char) *location,
                            const(char) *load_key)
    {
        if (_host_preset)
            _host_preset.loaded(_host, 
                                location_kind, 
                                location, 
                                load_key);
    }

    void notifyPresetError(uint location_kind,
                           const(char) *location,
                           const(char) *load_key,
                           int os_error,
                           const(char)* msg)
    {
        if (_host_preset)
            _host_preset.on_error(_host, 
                                  location_kind, 
                                  location, 
                                  load_key,
                                  os_error,
                                  msg);
    }

    DAW getDAW()
    {
        char[128] dawStr;
        snprintf(dawStr.ptr, 128, "%s", _host.name);

        // Force lowercase
        for (char* p =  dawStr.ptr; *p != '\0'; ++p)
        {
            if (*p >= 'A' && *p <= 'Z')
                *p += ('a' - 'A');
        }

        return identifyDAW(dawStr.ptr);
    }

    PluginFormat getPluginFormat()
    {
        return PluginFormat.clap;
    }

    CLAPClient                      _backRef;
    const(clap_host_t)*             _host;
    const(clap_host_gui_t)*         _host_gui;
    const(clap_host_latency_t)*     _host_latency;
    const(clap_host_params_t)*      _host_params;
    const(clap_host_tail_t)*        _host_tail;
    const(clap_host_preset_load_t)* _host_preset;
}

class CLAPPresetProvider
{
public:
nothrow:
@nogc:

    this(Client client, const(clap_preset_discovery_indexer_t)* indexer)
    {
        _indexer = indexer;
        _client = client;
    }

    ~this()
    {
        destroyFree(_client);
    }

    UncheckedMutex _presetMutex;
    __gshared clap_preset_discovery_filetype_t filetype;
    __gshared clap_universal_plugin_id_t thisPlugin;

    bool init_()
    {
        _presetMutex.lockLazy();
        scope(exit) _presetMutex.unlock();

        clap_preset_discovery_location_t loc;
        loc.flags = CLAP_PRESET_DISCOVERY_IS_FACTORY_CONTENT;
        loc.name  = "Factory presets";
        loc.kind = CLAP_PRESET_DISCOVERY_LOCATION_PLUGIN;
        loc.location = null;

        thisPlugin.abi = "clap";
        thisPlugin.id   = assumeZeroTerminated(_client.CLAPIdentifier);

        // Note: this file extension makes no sense but CLAP
        //       apparently forces us to declare one.
        filetype.name = "Dplug CLAP chunk";
        filetype.description = "Dplug factory preset format";
        filetype.file_extension = "patch";

        // FUTURE: rare error ignored here
        bool res = _indexer.declare_filetype(_indexer, &filetype);
        res = _indexer.declare_location(_indexer, &loc);
        return true;
    }

    bool get_metadata(uint location_kind,
                      const(char)* location,
                      const(clap_preset_discovery_metadata_receiver_t)* metadata_receiver)
    {
        _presetMutex.lockLazy();
        scope(exit) _presetMutex.unlock();

        if (location_kind != CLAP_PRESET_DISCOVERY_LOCATION_PLUGIN)
            return false;

        // Here is a trick, multi-track studio when given a NULL 
        // location, will get back to us with a "" location, and a
        // non-null pointer. Do NOT check location.

        PresetBank bank = _client.presetBank();
        int numPresets = bank.numPresets();

        for (int n = 0; n < numPresets; ++n)
        {
            Preset preset = bank.preset(n);

            // Assuming the load key is copied here.
            // Load key is simply the preset index.
            char[24] load_key;
            snprintf(load_key.ptr, 24, "%d", n);
            const(char)* nameZ = assumeZeroTerminated(preset.name);
            if (!metadata_receiver.begin_preset(metadata_receiver, nameZ, load_key.ptr))
                break;

            // say this preset is for that plugin
            metadata_receiver.add_plugin_id(metadata_receiver, &thisPlugin);
            metadata_receiver.set_flags(metadata_receiver, CLAP_PRESET_DISCOVERY_IS_FACTORY_CONTENT);
        }
        return true;
    }

private:
    const(clap_preset_discovery_indexer_t)* _indexer;
    Client _client;
}

extern(C) static
{
    enum string PresetCallback =
        `ScopedForeignCallback!(false, true) sc;
        sc.enter();
        CLAPPresetProvider provobj = cast(CLAPPresetProvider)cast(Object)(provider.provider_data);`;

    // plugin callbacks

    bool provider_init(const(clap_preset_discovery_provider_t)* provider)
    {
        mixin(PresetCallback);
        return provobj.init_();
    }

    void provider_destroy(const(clap_preset_discovery_provider_t)* provider)
    {
        mixin(PresetCallback);
        destroyFree(provobj);
    }

    // reads metadata from the given file and passes them to the metadata receiver
    // Returns true on success.
    bool provider_get_metadata(const(clap_preset_discovery_provider_t)* provider,
                               uint location_kind,
                               const(char)* location,
                               const(clap_preset_discovery_metadata_receiver_t)* metadata_receiver)
    {
        mixin(PresetCallback);
        return provobj.get_metadata(location_kind, location, metadata_receiver);
    }

    // Query an extension.
    // The returned pointer is owned by the provider.
    // It is forbidden to call it before provider->init().
    // You can call it within provider->init() call, and after.
    const(void)* provider_get_extension(const(clap_preset_discovery_provider_t)* provider,
                                        const(char)* extension_id)
    {
        return null;
    }
}