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

import core.stdc.string: strcmp;

import dplug.core.nogc;
import dplug.core.runtime;

import dplug.client.client;
import dplug.client.params;
import dplug.client.graphics;
import dplug.client.daw;
import dplug.client.midi;


import dplug.clap.types;

nothrow @nogc:

class CLAPClient
{
public:
nothrow:
@nogc:

    this(Client client, const(void)* host)
    {
        _client = client;

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
    }

    const(clap_plugin_t)* get_clap_plugin()
    {
        return &_plugin;
    }

private:
    Client _client;
    clap_plugin_t _plugin;

    // plugin is "activated" (status of activate / deactivate sequence)
    bool activated;

    // plugin is "processing" (status of activate / deactivate sequence)
    bool processing;

    // true if resetFromHost must be called before next block
    bool _mustReset;

    // Last hint at sampleRate, -1 if not specified yet
    float _sampleRate = -1;

    // Max frames in block., -1 if not specified yet.
    int _maxFrames = -1;

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
        // First place where we can query the host completely.
        // However, I don't see what we could do here anyway.
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

        // No synchronization needed, since
        // the plugin is deactivated.
        // Delay that reset, since we don't know for sure the buses configuration here.
        _sampleRate = sample_rate;
        _maxFrames = cast(int) max_frames_count;
        _mustReset = true;
        activated = true;
        return true;
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
        // Dplug doesn't have that semantic (it's just initialize + process, no separate reset call)
        // Since activate can potentially change sample-rate and allocate, we assume that state 
        // may be cleared there as well without too much issues.
        _mustReset = true; // force a reset
    }

    clap_process_status process(const(clap_process_t)* processParams)
    {
        // It seems the number of ports and channels is discovered here
        // as last resort.

        if (_mustReset)
        {
            _mustReset = false;
            int numInputs = 2;
            int numOutputs = 2;
            _client.resetFromHost(_sampleRate, _maxFrames, numInputs, numOutputs);
        }

        //TODO: processing


        // Note: CLAP can expose more internal state, such as tail, process only non-silence etc.
        // However a realistic plug-in will implment silence detection for the other formats as well.
        return CLAP_PROCESS_CONTINUE;
    }

    // aka QueryInterface for the people
    void* get_extension(const(char)* name)
    {
        if (strcmp(name, "clap.params") == 0)
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
        
        //import core.stdc.stdio;
        //printf("get_extension(%s)\n", name);
        
        // no extension support
        return null;
    }

    // clap.params interface implementation


    uint params_count()
    {
        return cast(uint) _client.params().length;
    }

    bool params_get_info(uint param_index, clap_param_info_t* param_info)
    {
        // TODO
        return false;
    }

    bool params_get_value(clap_id param_id, double *out_value)
    {
        // TODO
        return false;
    }

    // eg: "2.3 kHz"
    bool params_value_to_text(
                       clap_id              param_id,
                       double               value,
                       char                *out_buffer,
                       uint                out_buffer_capacity)
    {
        // TODO
        return false;
    }

    bool params_text_to_value(
                  clap_id              param_id,
                  const(char)         *param_value_text,
                  double              *out_value)
    {
        //TODO
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


    // ext clap.params callbacks

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
}


