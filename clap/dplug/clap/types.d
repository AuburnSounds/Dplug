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
module dplug.clap.types;

nothrow @nogc:

import core.stdc.string;
import core.stdc.config;
import dplug.core.runtime;
import dplug.core.nogc;
import dplug.core.sync;
import dplug.client.client;
import dplug.client.daw;
import dplug.clap.client;
import dplug.clap;
import dplug.clap.clapversion;


// CLAP has lots of unsigned integers, meaning we must in theory 
// check for overflows
int assumeNoOverflow(uint x) pure @safe
{
    assert(x <= int.max);
    return x;
}

// id.h

alias clap_id = uint;
enum clap_id CLAP_INVALID_ID = uint.max;
/*
void printfemergency(const(char)* s)
{
    import core.stdc.stdio;
    FILE* fio = fopen(`C:\Users\guill\Desktop\output.txt`, "a");
    fprintf(fio, "%s", s);
    fflush(fio);
    fclose(fio);
}*/


// string-sizes.h

// String capacity for names that can be displayed to the user.
enum CLAP_NAME_SIZE = 256;

// String capacity for describing a path, like a parameter in a module hierarchy or path within a
// set of nested track groups.
//
// This is not suited for describing a file path on the disk, as NTFS allows up to 32K long
// paths.
enum CLAP_PATH_SIZE = 1024;


// fixed-point.h

/// We use fixed point representation of beat time and seconds time
/// Usage:
///   double x = ...; // in beats
///   clap_beattime y = round(CLAP_BEATTIME_FACTOR * x);
// This will never change
enum long CLAP_BEATTIME_FACTOR = (cast(long)1) << 31;
enum long CLAP_SECTIME_FACTOR  = (cast(long)1) << 31;

alias clap_beattime = long;
alias clap_sectime = long;


// plugin-features.h

// Add this feature if your plugin can process note events and then produce audio
static immutable CLAP_PLUGIN_FEATURE_INSTRUMENT = "instrument";

// Add this feature if your plugin is an audio effect
static immutable CLAP_PLUGIN_FEATURE_AUDIO_EFFECT = "audio-effect";

// Add this feature if your plugin is a note effect or a note generator/sequencer
static immutable CLAP_PLUGIN_FEATURE_NOTE_EFFECT = "note-effect";

// Add this feature if your plugin converts audio to notes
static immutable CLAP_PLUGIN_FEATURE_NOTE_DETECTOR = "note-detector";

// Add this feature if your plugin is an analyzer
static immutable CLAP_PLUGIN_FEATURE_ANALYZER = "analyzer";

// Audio Capabilities

static immutable CLAP_PLUGIN_FEATURE_MONO      = "mono";
static immutable CLAP_PLUGIN_FEATURE_STEREO    = "stereo";
static immutable CLAP_PLUGIN_FEATURE_SURROUND  = "surround";
static immutable CLAP_PLUGIN_FEATURE_AMBISONIC = "ambisonic";



// version.h

__gshared UncheckedMutex g_factoryMutex; // FUTURE: sounds like... leaked?

// Get the pointer to a factory. See factory/plugin-factory.h for an example.
//
// Returns null if the factory is not provided.
// The returned pointer must *not* be freed by the caller.
const(void)* clap_factory_templated(ClientClass)(const(char)* factory_id) 
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();
    if (strcmp(factory_id, "clap.plugin-factory") == 0)
    {
        static immutable __gshared clap_plugin_factory_t g_factory
            = clap_plugin_factory_t(&factory_get_plugin_count, 
                                    &factory_get_plugin_descriptor!ClientClass,
                                    &factory_create_plugin!ClientClass);
        return &g_factory;
    }

    if (  (strcmp(factory_id, CLAP_PRESET_DISCOVERY_FACTORY_ID.ptr) == 0)
          || (strcmp(factory_id, CLAP_PRESET_DISCOVERY_FACTORY_ID_COMPAT.ptr) == 0) )
    {
        static immutable __gshared clap_preset_discovery_factory_t g_presetfactory
            = clap_preset_discovery_factory_t(&preset_discovery_count, 
                                              &preset_discovery_get_descriptor!ClientClass,
                                              &preset_discovery_create!ClientClass);
        return &g_presetfactory;
    }
    return null;
}

extern(C)
{
    // plugin factory impl

    uint factory_get_plugin_count(const(clap_plugin_factory_t)* factory)
    {
        return 1;
    }

    const(clap_plugin_descriptor_t)* get_descriptor_from_client(Client client)
    {
        // Fill with information from PluginClass
        __gshared clap_plugin_descriptor_t desc;

        desc.clap_version = CLAP_VERSION;
        desc.id   = assumeZeroTerminated(client.CLAPIdentifier);
        desc.name = assumeZeroTerminated(client.pluginName);
        desc.vendor = assumeZeroTerminated(client.vendorName);
        desc.url = assumeZeroTerminated(client.pluginHomepage);

        // FUTURE: Dplug doesn't have that, same URL as homepage
        desc.manual_url = desc.url; 

        // FUTURE: provide that support URL
        desc.support_url = desc.url; // Weird crash in Windows debug with in ms-encode assumeZeroTerminated(client.getVendorSupportEmail); 

        // Can be __shared, since there is a single plugin in our CLAP client,
        // with a single version.
        __gshared char[64] versionBuf;
        PluginVersion ver = client.getPublicVersion();
        ver.toCLAPVersionString(versionBuf.ptr, 64);
        desc.version_ = versionBuf.ptr;
        desc.description = "No description.".ptr;

        // Build a global array of features.
        enum MAX_FEATURES = 8;
        int nFeatures = 0;
        __gshared const(char)*[MAX_FEATURES] g_features;
        void addFeature(immutable(char)[] feature)
        {
            g_features[nFeatures++] = feature.ptr;
        }
        bool isSynth  =  client.isSynth;
        bool isEffect = !client.isSynth;        
        if (isSynth) addFeature(CLAP_PLUGIN_FEATURE_INSTRUMENT);
        if (isSynth && client.isLegalIO(0, 1)) addFeature( CLAP_PLUGIN_FEATURE_MONO );
        if (isSynth && client.isLegalIO(0, 2)) addFeature( CLAP_PLUGIN_FEATURE_STEREO );
        if (isEffect) addFeature(CLAP_PLUGIN_FEATURE_AUDIO_EFFECT);
        if (isEffect && client.isLegalIO(1, 1)) addFeature( CLAP_PLUGIN_FEATURE_MONO );
        if (isEffect && client.isLegalIO(2, 2)) addFeature( CLAP_PLUGIN_FEATURE_STEREO );

        string clapCategory;
        final switch(client.pluginCategory()) with (PluginCategory)
        {
            case effectAnalysisAndMetering: clapCategory = "analyzer"; break;
            case effectDelay:               clapCategory = "delay"; break;
            case effectDistortion:          clapCategory = "distortion"; break;
            case effectDynamics:            clapCategory = "compressor"; break; // Note: CLAP has 3: compressor, expander, transient shaper
            case effectEQ:                  clapCategory = "equalizer"; break;
            case effectImaging:             clapCategory = "utility"; break;    // No imaging categiry in CLAP
            case effectModulation:          clapCategory = "chorus"; break;     // Note: CLAP has chorus and flanger
            case effectPitch:               clapCategory = "pitch-correction"; break;
            case effectReverb:              clapCategory = "reverb"; break;
            case effectOther:               clapCategory = null; break;
            case instrumentDrums:           clapCategory = "drum-machine"; break;
            case instrumentSampler:         clapCategory = "sampler"; break;
            case instrumentSynthesizer:     clapCategory = "synthesizer"; break;
            case instrumentOther:           clapCategory = null; break;
            case invalid:                   assert(false);
        }
        addFeature(clapCategory);
        addFeature(null);
        desc.features = g_features.ptr;
        return &desc;
    }

    const(clap_plugin_descriptor_t)* factory_get_plugin_descriptor(ClientClass)(const(clap_plugin_factory_t)* factory, uint index)
    {
        ScopedForeignCallback!(false, true) sfc;
        sfc.enter();

        // Only one plug-in supported by CLAP wrapper in Dplug.
        if (index != 0)
            return null;

        g_factoryMutex.lockLazy();
        scope(exit) g_factoryMutex.unlock();

        // Create a client just for the purpose of describing the plug-in
        ClientClass client = mallocNew!ClientClass();
        scope(exit) client.destroyFree();
        return get_descriptor_from_client(client);
    }

    const(clap_plugin_t)* factory_create_plugin(ClientClass)(const(clap_plugin_factory_t)*factory,
                                const(clap_host_t)* host,
                                const(char)* plugin_id)
    {
        ScopedForeignCallback!(false, true) sfc;
        sfc.enter();

        // Note: I don't see what would NOT be thread-safe here.

        // Create a Client and a CLAPClient, who hold that and the CLAP structure
        ClientClass client = mallocNew!ClientClass();

        // Verify that ID match, this is a clap-validator check.
        const(clap_plugin_descriptor_t)* desc = get_descriptor_from_client(client);
        if (strcmp(desc.id, plugin_id) != 0)
        {
            destroyFree(client);
            return null;
        }

        CLAPClient clapClient = mallocNew!CLAPClient(client, host);

        return clapClient.get_clap_plugin();
    }


    // preset factory impl

    uint preset_discovery_count(const(clap_preset_discovery_factory_t)* factory)
    {
        return 1; // always one preset provider
    }

    const(clap_preset_discovery_provider_descriptor_t)*  get_preset_dicovery_from_client(Client client)
    {
        // ID is globally unique, why not. Apparently you can
        // provide presets for other people's products that way.
        __gshared clap_preset_discovery_provider_descriptor_t desc;
        desc.clap_version = CLAP_VERSION;
        desc.id = assumeZeroTerminated(client.CLAPIdentifierFactory);
        desc.name = "Dplug preset provider"; // what an annoying thing to name
        desc.vendor = assumeZeroTerminated(client.vendorName);
        return &desc;
    }

    // Retrieves a preset provider descriptor by its index.
    // Returns null in case of error.
    // The descriptor must not be freed.
    // [thread-safe]
    const(clap_preset_discovery_provider_descriptor_t)* 
        preset_discovery_get_descriptor(ClientClass)(const(clap_preset_discovery_factory_t)* factory, uint index)
    {
        ScopedForeignCallback!(false, true) sfc;
        sfc.enter();

        if (index != 0)
            return null;

        // Create a client just for the purpose of describing its "preset provider"
        ClientClass client = mallocNew!ClientClass();
        scope(exit) client.destroyFree();
        return get_preset_dicovery_from_client(client);
    }

    const(clap_preset_discovery_provider_t)* 
        preset_discovery_create(ClientClass)(const(clap_preset_discovery_factory_t)* factory,
                                             const(clap_preset_discovery_indexer_t)* indexer,
                                             const(char)* provider_id)
    {
        ScopedForeignCallback!(false, true) sfc;
        sfc.enter();

        // Create a client yet again for the purpose of creating its
        // "preset provider"
        ClientClass client = mallocNew!ClientClass();
        const(clap_preset_discovery_provider_descriptor_t)* desc = get_preset_dicovery_from_client(client);

        if (strcmp(provider_id, desc.id) != 0)
            return null;

        // Note: take ownership of that Client
        CLAPPresetProvider provider = mallocNew!CLAPPresetProvider(client, indexer);
        __gshared clap_preset_discovery_provider_t provdesc;
        provdesc.desc          = desc;
        provdesc.provider_data = cast(void*)provider;
        provdesc.init_         = &provider_init;
        provdesc.destroy       = &provider_destroy;
        provdesc.get_metadata  = &provider_get_metadata;
        provdesc.get_extension = &provider_get_extension;
        return &provdesc;   
    }
}

// factory.h

// Every method must be thread-safe.
// It is very important to be able to scan the plugin as quickly as possible.
//
// The host may use clap_plugin_invalidation_factory to detect filesystem changes
// which may change the factory's content.
struct clap_plugin_factory_t 
{
nothrow @nogc extern(C):

    // Get the number of plugins available.
    // [thread-safe]
    uint function(const(clap_plugin_factory_t)*) get_plugin_count;

    // Retrieves a plugin descriptor by its index.
    // Returns null in case of error.
    // The descriptor must not be freed.
    // [thread-safe]
    const(clap_plugin_descriptor_t)* function(const(clap_plugin_factory_t)*, uint) get_plugin_descriptor;

    // Create a clap_plugin by its plugin_id.
    // The returned pointer must be freed by calling plugin->destroy(plugin);
    // The plugin is not allowed to use the host callbacks in the create method.
    // Returns null in case of error.
    // [thread-safe]
    const(clap_plugin_t)* function(const(clap_plugin_factory_t)*, 
                                   const(clap_host_t)*, const(char)*) create_plugin;
}


// plugin.h

struct clap_plugin_descriptor_t 
{
    clap_version_t clap_version; // initialized to CLAP_VERSION

    // Mandatory fields must be set and must not be blank.
    // Otherwise the fields can be null or blank, though it is safer to make them blank.
    //
    // Some indications regarding id and version
    // - id is an arbitrary string which should be unique to your plugin,
    //   we encourage you to use a reverse URI eg: "com.u-he.diva"
    // - version is an arbitrary string which describes a plugin,
    //   it is useful for the host to understand and be able to compare two different
    //   version strings, so here is a regex like expression which is likely to be
    //   understood by most hosts: MAJOR(.MINOR(.REVISION)?)?( (Alpha|Beta) XREV)?
    const(char)* id;          // eg: "com.u-he.diva", mandatory
    const(char)* name;        // eg: "Diva", mandatory
    const(char)* vendor;      // eg: "u-he"
    const(char)* url;         // eg: "https://u-he.com/products/diva/"
    const(char)* manual_url;  // eg: "https://dl.u-he.com/manuals/plugins/diva/Diva-user-guide.pdf"
    const(char)* support_url; // eg: "https://u-he.com/support/"
    const(char)* version_;     // eg: "1.4.4"
    const(char)* description; // eg: "The spirit of analogue"

    // Arbitrary list of keywords.
    // They can be matched by the host indexer and used to classify the plugin.
    // The array of pointers must be null terminated.
    // For some standard features see plugin-features.h
    // Dlang Note: this is a null-terminated array of null-terminated strings.
    const(char)** features;
}


struct clap_plugin_t 
{
    // TODO add back documentation here in the interface instead of client

nothrow @nogc extern(C):

    const(clap_plugin_descriptor_t)* desc;
    void *plugin_data; // reserved pointer for the plugin
    bool function(const(clap_plugin_t)* plugin) init;
    void function(const(clap_plugin_t)* plugin) destroy;


    bool function(const(clap_plugin_t)* plugin,
                  double                sample_rate,
                  uint                  min_frames_count,
                  uint                  max_frames_count) activate;
    void function(const(clap_plugin_t)*plugin) deactivate;


    bool function(const(clap_plugin_t)*plugin) start_processing;
    void function(const(clap_plugin_t)* plugin) stop_processing;

    void function(const(clap_plugin_t)* plugin) reset;

    // process audio, events, ...
    // All the pointers coming from clap_process_t and its nested attributes,
    // are valid until process() returns.
    // [audio-thread & active & processing]
    clap_process_status function(const(clap_plugin_t)*plugin,
                                 const(clap_process_t)* processParams) process;

    // Query an extension.
    // The returned pointer is owned by the plugin.
    // It is forbidden to call it before plugin->init().
    // You can call it within plugin->init() call, and after.
    // [thread-safe]
    const(void)* function(const(clap_plugin_t)*plugin, const char *id) get_extension;

    // Called by the host on the main thread in response to a previous call to:
    //   host->request_callback(host);
    // [main-thread]
    void function(const(clap_plugin_t)*plugin) on_main_thread;
}


// color.h

struct clap_color 
{
    ubyte alpha;
    ubyte red;
    ubyte green;
    ubyte blue;
}

// process.h

alias clap_process_status = int;
enum : clap_process_status
{
    // Processing failed. The output buffer must be discarded.
    CLAP_PROCESS_ERROR = 0,

    // Processing succeeded, keep processing.
    CLAP_PROCESS_CONTINUE = 1,

    // Processing succeeded, keep processing if the output is not quiet.
    CLAP_PROCESS_CONTINUE_IF_NOT_QUIET = 2,

    // Rely upon the plugin's tail to determine if the plugin should continue to process.
    // see clap_plugin_tail
    CLAP_PROCESS_TAIL = 3,

    // Processing succeeded, but no more processing is required,
    // until the next event or variation in audio input.
    CLAP_PROCESS_SLEEP = 4,
}

struct clap_process_t 
{
    // A steady sample time counter.
    // This field can be used to calculate the sleep duration between two process calls.
    // This value may be specific to this plugin instance and have no relation to what
    // other plugin instances may receive.
    //
    // Set to -1 if not available, otherwise the value must be greater or equal to 0,
    // and must be increased by at least `frames_count` for the next call to process.
    ulong steady_time;

    // Number of frames to process
    uint frames_count;

    // time info at sample 0
    // If null, then this is a free running host, no transport events will be provided
    const(void)*/*clap_event_transport_t*/ *transport;

    // Audio buffers, they must have the same count as specified
    // by clap_plugin_audio_ports->count().
    // The index maps to clap_plugin_audio_ports->get().
    // Input buffer and its contents are read-only.
    const(clap_audio_buffer_t)*audio_inputs;
    clap_audio_buffer_t       *audio_outputs;
    uint audio_inputs_count;
    uint audio_outputs_count;

    // The input event list can't be modified.
    // Input read-only event list. The host will deliver these sorted in sample order.
    const(clap_input_events_t)* in_events;

    // Output event list. The plugin must insert events in sample sorted order when inserting events
    const(clap_output_events_t)* out_events;
}

// audiobuffer.h

// Sample code for reading a stereo buffer:
//
// bool isLeftConstant = (buffer->constant_mask & (1 << 0)) != 0;
// bool isRightConstant = (buffer->constant_mask & (1 << 1)) != 0;
//
// for (int i = 0; i < N; ++i) {
//    float l = data32[0][isLeftConstant ? 0 : i];
//    float r = data32[1][isRightConstant ? 0 : i];
// }
//
// Note: checking the constant mask is optional, and this implies that
// the buffer must be filled with the constant value.
// Rationale: if a buffer reader doesn't check the constant mask, then it may
// process garbage samples and in result, garbage samples may be transmitted
// to the audio interface with all the bad consequences it can have.
//
// The constant mask is a hint.
struct clap_audio_buffer_t 
{
    // Either data32 or data64 pointer will be set.
    float  **data32;
    double **data64;
    uint channel_count;
    uint latency; // latency from/to the audio interface
    ulong constant_mask;
}


// params.h

alias clap_param_info_flags = uint;
enum : clap_param_info_flags
{
    // Is this param stepped? (integer values only)
    // if so the double value is converted to integer using a cast (equivalent to trunc).
    CLAP_PARAM_IS_STEPPED = 1 << 0,

    // Useful for periodic parameters like a phase
    CLAP_PARAM_IS_PERIODIC = 1 << 1,

    // The parameter should not be shown to the user, because it is currently not used.
    // It is not necessary to process automation for this parameter.
    CLAP_PARAM_IS_HIDDEN = 1 << 2,

    // The parameter can't be changed by the host.
    CLAP_PARAM_IS_READONLY = 1 << 3,

    // This parameter is used to merge the plugin and host bypass button.
    // It implies that the parameter is stepped.
    // min: 0 -> bypass off
    // max: 1 -> bypass on
    CLAP_PARAM_IS_BYPASS = 1 << 4,

    // When set:
    // - automation can be recorded
    // - automation can be played back
    //
    // The host can send live user changes for this parameter regardless of this flag.
    //
    // If this parameter affects the internal processing structure of the plugin, ie: max delay, fft
    // size, ... and the plugins needs to re-allocate its working buffers, then it should call
    // host->request_restart(), and perform the change once the plugin is re-activated.
    CLAP_PARAM_IS_AUTOMATABLE = 1 << 5,

    // Does this parameter support the modulation signal?
    CLAP_PARAM_IS_MODULATABLE = 1 << 10,

    // Does this parameter support per note modulations?
    CLAP_PARAM_IS_MODULATABLE_PER_NOTE_ID = 1 << 11,

    // Does this parameter support per key modulations?
    CLAP_PARAM_IS_MODULATABLE_PER_KEY = 1 << 12,

    // Does this parameter support per channel modulations?
    CLAP_PARAM_IS_MODULATABLE_PER_CHANNEL = 1 << 13,

    // Does this parameter support per port modulations?
    CLAP_PARAM_IS_MODULATABLE_PER_PORT = 1 << 14,

    // Any change to this parameter will affect the plugin output and requires to be done via
    // process() if the plugin is active.
    //
    // A simple example would be a DC Offset, changing it will change the output signal and must be
    // processed.
    CLAP_PARAM_REQUIRES_PROCESS = 1 << 15,

    // This parameter represents an enumerated value.
    // If you set this flag, then you must set CLAP_PARAM_IS_STEPPED too.
    // All values from min to max must not have a blank value_to_text().
    CLAP_PARAM_IS_ENUM = 1 << 16,
}

struct clap_param_info_t 
{
    // Stable parameter identifier, it must never change.
    clap_id id;

    clap_param_info_flags flags;

    // This value is optional and set by the plugin.
    // Its purpose is to provide fast access to the plugin parameter object by caching its pointer.
    // For instance:
    //
    // in clap_plugin_params.get_info():
    //    Parameter *p = findParameter(param_id);
    //    param_info->cookie = p;
    //
    // later, in clap_plugin.process():
    //
    //    Parameter *p = (Parameter *)event->cookie;
    //    if (!p) [[unlikely]]
    //       p = findParameter(event->param_id);
    //
    // where findParameter() is a function the plugin implements to map parameter ids to internal
    // objects.
    //
    // Important:
    //  - The cookie is invalidated by a call to clap_host_params->rescan(CLAP_PARAM_RESCAN_ALL) or
    //    when the plugin is destroyed.
    //  - The host will either provide the cookie as issued or nullptr in events addressing
    //    parameters.
    //  - The plugin must gracefully handle the case of a cookie which is nullptr.
    //  - Many plugins will process the parameter events more quickly if the host can provide the
    //    cookie in a faster time than a hashmap lookup per param per event.
    void *cookie;

    // The display name. eg: "Volume". This does not need to be unique. Do not include the module
    // text in this. The host should concatenate/format the module + name in the case where showing
    // the name alone would be too vague.
    char[CLAP_NAME_SIZE] name;

    // The module path containing the param, eg: "Oscillators/Wavetable 1".
    // '/' will be used as a separator to show a tree-like structure.
    char[CLAP_PATH_SIZE] module_;

    double min_value;     // Minimum plain value
    double max_value;     // Maximum plain value
    double default_value; // Default plain value
}

struct clap_plugin_params_t 
{
extern(C) nothrow @nogc:
    // Returns the number of parameters.
    // [main-thread]
    uint function (const(clap_plugin_t)*plugin) count;

    // Copies the parameter's info to param_info.
    // Returns true on success.
    // [main-thread]
    bool function(const(clap_plugin_t)*plugin,
                  uint             param_index,
                  clap_param_info_t   *param_info) get_info;

    // Writes the parameter's current value to out_value.
    // Returns true on success.
    // [main-thread]
    bool function(const clap_plugin_t *plugin, clap_id param_id, double *out_value) get_value;

    // Fills out_buffer with a null-terminated UTF-8 string that represents the parameter at the
    // given 'value' argument. eg: "2.3 kHz". The host should always use this to format parameter
    // values before displaying it to the user.
    // Returns true on success.
    // [main-thread]
    bool function(const(clap_plugin_t)*plugin,
                  clap_id              param_id,
                  double               value,
                  char                *out_buffer,
                  uint                 out_buffer_capacity) value_to_text;

    // Converts the null-terminated UTF-8 param_value_text into a double and writes it to out_value.
    // The host can use this to convert user input into a parameter value.
    // Returns true on success.
    // [main-thread]
    bool function(const clap_plugin_t *plugin,
                  clap_id              param_id,
                  const(char)         *param_value_text,
                  double              *out_value) text_to_value;

    // Flushes a set of parameter changes.
    // This method must not be called concurrently to clap_plugin->process().
    //
    // Note: if the plugin is processing, then the process() call will already achieve the
    // parameter update (bi-directional), so a call to flush isn't required, also be aware
    // that the plugin may use the sample offset in process(), while this information would be
    // lost within flush().
    //
    // [active ? audio-thread : main-thread]
    void function(const(clap_plugin_t)        *plugin,
                  const(clap_input_events_t)  *in_,
                  const(clap_output_events_t) *out_) flush;
}

alias clap_param_rescan_flags = uint;
enum : clap_param_rescan_flags
{
    // The parameter values did change, eg. after loading a preset.
    // The host will scan all the parameters value.
    // The host will not record those changes as automation points.
    // New values takes effect immediately.
    CLAP_PARAM_RESCAN_VALUES = 1 << 0,

    // The value to text conversion changed, and the text needs to be rendered again.
    CLAP_PARAM_RESCAN_TEXT = 1 << 1,

    // The parameter info did change, use this flag for:
    // - name change
    // - module change
    // - is_periodic (flag)
    // - is_hidden (flag)
    // New info takes effect immediately.
    CLAP_PARAM_RESCAN_INFO = 1 << 2,

    // Invalidates everything the host knows about parameters.
    // It can only be used while the plugin is deactivated.
    // If the plugin is activated use clap_host->restart() and delay any change until the host calls
    // clap_plugin->deactivate().
    //
    // You must use this flag if:
    // - some parameters were added or removed.
    // - some parameters had critical changes:
    //   - is_per_note (flag)
    //   - is_per_key (flag)
    //   - is_per_channel (flag)
    //   - is_per_port (flag)
    //   - is_readonly (flag)
    //   - is_bypass (flag)
    //   - is_stepped (flag)
    //   - is_modulatable (flag)
    //   - min_value
    //   - max_value
    //   - cookie
    CLAP_PARAM_RESCAN_ALL = 1 << 3,
}

alias clap_param_clear_flags = uint;
enum : clap_param_clear_flags
{
    // Clears all possible references to a parameter
    CLAP_PARAM_CLEAR_ALL = 1 << 0,

    // Clears all automations to a parameter
    CLAP_PARAM_CLEAR_AUTOMATIONS = 1 << 1,

    // Clears all modulations to a parameter
    CLAP_PARAM_CLEAR_MODULATIONS = 1 << 2,
}

struct clap_host_params_t
{
extern(C) nothrow @nogc:
    // Rescan the full list of parameters according to the flags.
    // [main-thread]
    void function(const(clap_host_t)* host, clap_param_rescan_flags flags) rescan;

    // Clears references to a parameter.
    // [main-thread]
    void function(const(clap_host_t)* host, clap_id param_id, clap_param_clear_flags flags) clear;

    // Request a parameter flush.
    //
    // The host will then schedule a call to either:
    // - clap_plugin.process()
    // - clap_plugin_params.flush()
    //
    // This function is always safe to use and should not be called from an [audio-thread] as the
    // plugin would already be within process() or flush().
    //
    // [thread-safe,!audio-thread]
    void function(const(clap_host_t)* host) request_flush;
}


// events.h

// event header
// must be the first attribute of the event
struct clap_event_header_t 
{
    uint size;       // event size including this header, eg: sizeof (clap_event_note)
    uint time;       // sample offset within the buffer for this event
    ushort space_id; // event space, see clap_host_event_registry
    ushort type;     // event type
    uint flags;      // see clap_event_flags
}

// The clap core event space
enum ushort CLAP_CORE_EVENT_SPACE_ID = 0;

alias clap_event_flags = int;
enum : clap_event_flags 
{
    // Indicate a live user event, for example a user turning a physical knob
    // or playing a physical key.
    CLAP_EVENT_IS_LIVE = 1 << 0,

    // Indicate that the event should not be recorded.
    // For example this is useful when a parameter changes because of a MIDI CC,
    // because if the host records both the MIDI CC automation and the parameter
    // automation there will be a conflict.
    CLAP_EVENT_DONT_RECORD = 1 << 1,
}

// Some of the following events overlap, a note on can be expressed with:
// - CLAP_EVENT_NOTE_ON
// - CLAP_EVENT_MIDI
// - CLAP_EVENT_MIDI2
//
// The preferred way of sending a note event is to use CLAP_EVENT_NOTE_*.
//
// The same event must not be sent twice: it is forbidden to send a the same note on
// encoded with both CLAP_EVENT_NOTE_ON and CLAP_EVENT_MIDI.
//
// The plugins are encouraged to be able to handle note events encoded as raw midi or midi2,
// or implement clap_plugin_event_filter and reject raw midi and midi2 events.
enum 
{
    // NOTE_ON and NOTE_OFF represent a key pressed and key released event, respectively.
    // A NOTE_ON with a velocity of 0 is valid and should not be interpreted as a NOTE_OFF.
    //
    // NOTE_CHOKE is meant to choke the voice(s), like in a drum machine when a closed hihat
    // chokes an open hihat. This event can be sent by the host to the plugin. Here are two use
    // cases:
    // - a plugin is inside a drum pad in Bitwig Studio's drum machine, and this pad is choked by
    //   another one
    // - the user double-clicks the DAW's stop button in the transport which then stops the sound on
    //   every track
    //
    // NOTE_END is sent by the plugin to the host. The port, channel, key and note_id are those given
    // by the host in the NOTE_ON event. In other words, this event is matched against the
    // plugin's note input port.
    // NOTE_END is useful to help the host to match the plugin's voice life time.
    //
    // When using polyphonic modulations, the host has to allocate and release voices for its
    // polyphonic modulator. Yet only the plugin effectively knows when the host should terminate
    // a voice. NOTE_END solves that issue in a non-intrusive and cooperative way.
    //
    // CLAP assumes that the host will allocate a unique voice on NOTE_ON event for a given port,
    // channel and key. This voice will run until the plugin will instruct the host to terminate
    // it by sending a NOTE_END event.
    //
    // Consider the following sequence:
    // - process()
    //    Host->Plugin NoteOn(port:0, channel:0, key:16, time:t0)
    //    Host->Plugin NoteOn(port:0, channel:0, key:64, time:t0)
    //    Host->Plugin NoteOff(port:0, channel:0, key:16, t1)
    //    Host->Plugin NoteOff(port:0, channel:0, key:64, t1)
    //    # on t2, both notes did terminate
    //    Host->Plugin NoteOn(port:0, channel:0, key:64, t3)
    //    # Here the plugin finished processing all the frames and will tell the host
    //    # to terminate the voice on key 16 but not 64, because a note has been started at t3
    //    Plugin->Host NoteEnd(port:0, channel:0, key:16, time:ignored)
    //
    // These four events use clap_event_note.
    CLAP_EVENT_NOTE_ON = 0,
    CLAP_EVENT_NOTE_OFF = 1,
    CLAP_EVENT_NOTE_CHOKE = 2,
    CLAP_EVENT_NOTE_END = 3,

    // Represents a note expression.
    // Uses clap_event_note_expression.
    CLAP_EVENT_NOTE_EXPRESSION = 4,

    // PARAM_VALUE sets the parameter's value; uses clap_event_param_value.
    // PARAM_MOD sets the parameter's modulation amount; uses clap_event_param_mod.
    //
    // The value heard is: param_value + param_mod.
    //
    // In case of a concurrent global value/modulation versus a polyphonic one,
    // the voice should only use the polyphonic one and the polyphonic modulation
    // amount will already include the monophonic signal.
    CLAP_EVENT_PARAM_VALUE = 5,
    CLAP_EVENT_PARAM_MOD = 6,

    // Indicates that the user started or finished adjusting a knob.
    // This is not mandatory to wrap parameter changes with gesture events, but this improves
    // the user experience a lot when recording automation or overriding automation playback.
    // Uses clap_event_param_gesture.
    CLAP_EVENT_PARAM_GESTURE_BEGIN = 7,
    CLAP_EVENT_PARAM_GESTURE_END = 8,

    CLAP_EVENT_TRANSPORT = 9,   // update the transport info; clap_event_transport
    CLAP_EVENT_MIDI = 10,       // raw midi event; clap_event_midi
    CLAP_EVENT_MIDI_SYSEX = 11, // raw midi sysex event; clap_event_midi_sysex
    CLAP_EVENT_MIDI2 = 12,      // raw midi 2 event; clap_event_midi2
}

// Note on, off, end and choke events.
//
// Clap addresses notes and voices using the 4-value tuple
// (port, channel, key, note_id). Note on/off/end/choke
// events and parameter modulation messages are delivered with
// these values populated.
//
// Values in a note and voice address are either >= 0 if they
// are specified, or -1 to indicate a wildcard. A wildcard
// means a voice with any value in that part of the tuple
// matches the message.
//
// For instance, a (PCKN) of (0, 3, -1, -1) will match all voices
// on channel 3 of port 0. And a PCKN of (-1, 0, 60, -1) will match
// all channel 0 key 60 voices, independent of port or note id.
//
// Especially in the case of note-on note-off pairs, and in the
// absence of voice stacking or polyphonic modulation, a host may
// choose to issue a note id only at note on. So you may see a
// message stream like
//
// CLAP_EVENT_NOTE_ON  [0,0,60,184]
// CLAP_EVENT_NOTE_OFF [0,0,60,-1]
//
// and the host will expect the first voice to be released.
// Well constructed plugins will search for voices and notes using
// the entire tuple.
//
// In the case of note on events:
// - The port, channel and key must be specified with a value >= 0
// - A note-on event with a '-1' for port, channel or key is invalid and
//   can be rejected or ignored by a plugin or host.
// - A host which does not support note ids should set the note id to -1.
//
// In the case of note choke or end events:
// - the velocity is ignored.
// - key and channel are used to match active notes
// - note_id is optionally provided by the host
struct clap_event_note_t 
{
    clap_event_header_t header;
    int note_id; // host provided note id >= 0, or -1 if unspecified or wildcard
    short port_index; // port index from ext/note-ports; -1 for wildcard
    short channel;  // 0..15, same as MIDI1 Channel Number, -1 for wildcard
    short key;      // 0..127, same as MIDI1 Key Number (60==Middle C), -1 for wildcard
    double  velocity; // 0..1
}

// Note Expressions are well named modifications of a voice targeted to
// voices using the same wildcard rules described above. Note Expressions are delivered
// as sample accurate events and should be applied at the sample when received.
//
// Note expressions are a statement of value, not cumulative. A PAN event of 0 followed by 1
// followed by 0.5 would pan hard left, hard right, and center. They are intended as
// an offset from the non-note-expression voice default. A voice which had a volume of
// -20db absent note expressions which received a +4db note expression would move the
// voice to -16db.
//
// A plugin which receives a note expression at the same sample as a NOTE_ON event
// should apply that expression to all generated samples. A plugin which receives
// a note expression after a NOTE_ON event should initiate the voice with default
// values and then apply the note expression when received. A plugin may make a choice
// to smooth note expression streams.
enum 
{
    // with 0 < x <= 4, plain = 20 * log(x)
    CLAP_NOTE_EXPRESSION_VOLUME = 0,

    // pan, 0 left, 0.5 center, 1 right
    CLAP_NOTE_EXPRESSION_PAN = 1,

    // Relative tuning in semitones, from -120 to +120. Semitones are in
    // equal temperament and are doubles; the resulting note would be
    // retuned by `100 * evt->value` cents.
    CLAP_NOTE_EXPRESSION_TUNING = 2,

    // 0..1
    CLAP_NOTE_EXPRESSION_VIBRATO = 3,
    CLAP_NOTE_EXPRESSION_EXPRESSION = 4,
    CLAP_NOTE_EXPRESSION_BRIGHTNESS = 5,
    CLAP_NOTE_EXPRESSION_PRESSURE = 6,
}
alias clap_note_expression = int;

struct clap_event_note_expression_t 
{
    clap_event_header_t header;

    clap_note_expression expression_id;

    // target a specific note_id, port, key and channel, with
    // -1 meaning wildcard, per the wildcard discussion above
    int note_id;
    short port_index;
    short channel;
    short key;

    double value; // see expression for the range
}

struct clap_event_param_value_t 
{
    clap_event_header_t header;

    // target parameter
    clap_id param_id; // @ref clap_param_info.id
    void   *cookie;   // @ref clap_param_info.cookie

    // target a specific note_id, port, key and channel, with
    // -1 meaning wildcard, per the wildcard discussion above
    int note_id;
    short port_index;
    short channel;
    short key;

    double value;
}

struct clap_event_param_mod_t
{
    clap_event_header_t header;

    // target parameter
    clap_id param_id; // @ref clap_param_info.id
    void   *cookie;   // @ref clap_param_info.cookie

    // target a specific note_id, port, key and channel, with
    // -1 meaning wildcard, per the wildcard discussion above
    int note_id;
    short port_index;
    short channel;
    short key;

    double amount; // modulation amount
}

struct clap_event_param_gesture_t 
{
    clap_event_header_t header;

    // target parameter
    clap_id param_id; // @ref clap_param_info.id
}

alias clap_transport_flags = int;
enum : clap_transport_flags 
{
    CLAP_TRANSPORT_HAS_TEMPO = 1 << 0,
    CLAP_TRANSPORT_HAS_BEATS_TIMELINE = 1 << 1,
    CLAP_TRANSPORT_HAS_SECONDS_TIMELINE = 1 << 2,
    CLAP_TRANSPORT_HAS_TIME_SIGNATURE = 1 << 3,
    CLAP_TRANSPORT_IS_PLAYING = 1 << 4,
    CLAP_TRANSPORT_IS_RECORDING = 1 << 5,
    CLAP_TRANSPORT_IS_LOOP_ACTIVE = 1 << 6,
    CLAP_TRANSPORT_IS_WITHIN_PRE_ROLL = 1 << 7,
}

struct clap_event_transport_t 
{
    clap_event_header_t header;

    uint flags; // see clap_transport_flags

    clap_beattime song_pos_beats;   // position in beats
    clap_sectime  song_pos_seconds; // position in seconds

    double tempo;     // in bpm
    double tempo_inc; // tempo increment for each sample and until the next
    // time info event

    clap_beattime loop_start_beats;
    clap_beattime loop_end_beats;
    clap_sectime  loop_start_seconds;
    clap_sectime  loop_end_seconds;

    clap_beattime bar_start;  // start pos of the current bar
    int           bar_number; // bar at song pos 0 has the number 0

    ushort tsig_num;   // time signature numerator
    ushort tsig_denom; // time signature denominator
}

struct clap_event_midi_t 
{
    clap_event_header_t header;

    ushort port_index;
    ubyte[3]  data;
}

struct clap_event_midi_sysex_t
{
    clap_event_header_t header;
    ushort port_index;
    const(ubyte)* buffer; // midi buffer
    uint size;
}

// While it is possible to use a series of midi2 event to send a sysex,
// prefer clap_event_midi_sysex if possible for efficiency.
struct clap_event_midi2_t 
{
    clap_event_header_t header;
    ushort port_index;
    uint[4] data;
}

// A CLAP event that is a union of any type of event
union clap_event_any_t
{
    clap_event_note_t            event_note;
    clap_event_note_expression_t note_expression;
    clap_event_param_value_t     param_value;
    clap_event_param_mod_t       param_mod;
    clap_event_param_gesture_t   param_gesture;
    clap_event_transport_t       transport;
    clap_event_midi_t            midi;
    clap_event_midi_sysex_t      midi_sysex;
    clap_event_midi2_t           midi2;
}

// A.Bique said: "If you are using non standard events, you should 
// make the event a single block of memory if possible, and use 
// relative pointers instead, I mean offsets from the start of the 
// struct.
// Cross process events could happen, for example if we have an intel
// 32 bits plugin and a 64 bits one, and one plugin is sending an 
// output event, we'd have to pass it to the other plugin host, via 
// IPC, so it has to work with memcpy()"


// Input event list. The host will deliver these sorted in sample order.
struct clap_input_events_t 
{
extern(C) nothrow @nogc:
    void *ctx; // reserved pointer for the list

    // returns the number of events in the list
    uint function(const(clap_input_events_t) *list) size;

    // Don't free the returned event, it belongs to the list
    const(clap_event_header_t)* function(const(clap_input_events_t)*list, uint index) get;
}

// Output event list. The plugin must insert events in sample sorted order when inserting events
struct clap_output_events_t 
{
extern(C) nothrow @nogc:
    void *ctx; // reserved pointer for the list

    // Pushes a copy of the event
    // returns false if the event could not be pushed to the queue (out of memory?)
    bool function(const(clap_output_events_t)* list,
                  const(clap_event_header_t)* event) try_push;
}


// audio-ports
// another name for "buses"

//
// This extension provides a way for the plugin to describe its current audio ports.
//
// If the plugin does not implement this extension, it won't have audio ports.
//
// 32 bits support is required for both host and plugins. 64 bits audio is optional.
//
// The plugin is only allowed to change its ports configuration while it is deactivated.

static immutable string CLAP_EXT_AUDIO_PORTS = "clap.audio-ports";
static immutable string CLAP_PORT_MONO = "mono";
static immutable string CLAP_PORT_STEREO = "stereo";

enum
{
    // This port is the main audio input or output.
    // There can be only one main input and main output.
    // Main port must be at index 0.
    CLAP_AUDIO_PORT_IS_MAIN = 1 << 0,

    // This port can be used with 64 bits audio
    CLAP_AUDIO_PORT_SUPPORTS_64BITS = 1 << 1,

    // 64 bits audio is preferred with this port
    CLAP_AUDIO_PORT_PREFERS_64BITS = 1 << 2,

    // This port must be used with the same sample size as all the other ports which have this flag.
    // In other words if all ports have this flag then the plugin may either be used entirely with
    // 64 bits audio or 32 bits audio, but it can't be mixed.
    CLAP_AUDIO_PORT_REQUIRES_COMMON_SAMPLE_SIZE = 1 << 3,
}

struct clap_audio_port_info_t 
{
    // id identifies a port and must be stable.
    // id may overlap between input and output ports.
    clap_id id;
    char[CLAP_NAME_SIZE] name; // displayable name

    uint flags;
    uint channel_count;

    // If null or empty then it is unspecified (arbitrary audio).
    // This field can be compared against:
    // - CLAP_PORT_MONO
    // - CLAP_PORT_STEREO
    // - CLAP_PORT_SURROUND (defined in the surround extension)
    // - CLAP_PORT_AMBISONIC (defined in the ambisonic extension)
    //
    // An extension can provide its own port type and way to inspect the channels.
    const(char)* port_type;

    // in-place processing: allow the host to use the same buffer for input and output
    // if supported set the pair port id.
    // if not supported set to CLAP_INVALID_ID
    clap_id in_place_pair;
}

// The audio ports scan has to be done while the plugin is deactivated.
struct clap_plugin_audio_ports_t 
{
extern(C) nothrow @nogc:

    // Number of ports, for either input or output
    // [main-thread]
    uint function(const(clap_plugin_t)* plugin, bool is_input) count;

    // Get info about an audio port.
    // Returns true on success and stores the result into info.
    // [main-thread]
    bool function(const(clap_plugin_t)* plugin,
                        uint index,
                        bool is_input,
                        clap_audio_port_info_t *info) get;
}

// gui.h

/// @page GUI
///
/// This extension defines how the plugin will present its GUI.
///
/// There are two approaches:
/// 1. the plugin creates a window and embeds it into the host's window
/// 2. the plugin creates a floating window
///
/// Embedding the window gives more control to the host, and feels more integrated.
/// Floating window are sometimes the only option due to technical limitations.
///
/// Showing the GUI works as follow:
///  1. clap_plugin_gui->is_api_supported(), check what can work
///  2. clap_plugin_gui->create(), allocates gui resources
///  3. if the plugin window is floating
///  4.    -> clap_plugin_gui->set_transient()
///  5.    -> clap_plugin_gui->suggest_title()
///  6. else
///  7.    -> clap_plugin_gui->set_scale()
///  8.    -> clap_plugin_gui->can_resize()
///  9.    -> if resizable and has known size from previous session, clap_plugin_gui->set_size()
/// 10.    -> else clap_plugin_gui->get_size(), gets initial size
/// 11.    -> clap_plugin_gui->set_parent()
/// 12. clap_plugin_gui->show()
/// 13. clap_plugin_gui->hide()/show() ...
/// 14. clap_plugin_gui->destroy() when done with the gui
///
/// Resizing the window (initiated by the plugin, if embedded):
/// 1. Plugins calls clap_host_gui->request_resize()
/// 2. If the host returns true the new size is accepted,
///    the host doesn't have to call clap_plugin_gui->set_size().
///    If the host returns false, the new size is rejected.
///
/// Resizing the window (drag, if embedded)):
/// 1. Only possible if clap_plugin_gui->can_resize() returns true
/// 2. Mouse drag -> new_size
/// 3. clap_plugin_gui->adjust_size(new_size) -> working_size
/// 4. clap_plugin_gui->set_size(working_size)

// If your windowing API is not listed here, please open an issue and we'll figure it out.
// https://github.com/free-audio/clap/issues/new

// uses physical size
// embed using https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setparent
static immutable string CLAP_WINDOW_API_WIN32 = "win32";

// uses logical size, don't call clap_plugin_gui->set_scale()
static immutable string CLAP_WINDOW_API_COCOA = "cocoa";

// uses physical size
// embed using https://specifications.freedesktop.org/xembed-spec/xembed-spec-latest.html
static immutable string CLAP_WINDOW_API_X11 = "x11";

// uses physical size
// embed is currently not supported, use floating windows
static immutable string CLAP_WINDOW_API_WAYLAND = "wayland";

alias clap_hwnd = void*;
alias clap_nsview = void*;
alias clap_xwnd = c_ulong;

// Represent a window reference.
struct clap_window_t 
{
    const(char) *api; // one of CLAP_WINDOW_API_XXX
    union 
    {
        clap_nsview cocoa;
        clap_xwnd   x11;
        clap_hwnd   win32;
        void       *ptr; // for anything defined outside of clap
    }
}

// Information to improve window resizing when initiated by the host or window manager.
struct clap_gui_resize_hints_t 
{
    bool can_resize_horizontally;
    bool can_resize_vertically;

    // only if can resize horizontally and vertically
    bool preserve_aspect_ratio;
    uint aspect_ratio_width;
    uint aspect_ratio_height;
}

// Size (width, height) is in pixels; the corresponding windowing system extension is
// responsible for defining if it is physical pixels or logical pixels.
struct clap_plugin_gui_t 
{
extern(C) nothrow @nogc:

    // Returns true if the requested gui api is supported
    // [main-thread]
    bool function(const clap_plugin_t *plugin, const char *api, bool is_floating) is_api_supported;

    // Returns true if the plugin has a preferred api.
    // The host has no obligation to honor the plugin preference, this is just a hint.
    // The const char **api variable should be explicitly assigned as a pointer to
    // one of the CLAP_WINDOW_API_ constants defined above, not strcopied.
    // [main-thread]
    bool function(const clap_plugin_t *plugin,
                  const(char)  **api,
                  bool *is_floating) get_preferred_api;

    // Create and allocate all resources necessary for the gui.
    //
    // If is_floating is true, then the window will not be managed by the host. The plugin
    // can set its window to stays above the parent window, see set_transient().
    // api may be null or blank for floating window.
    //
    // If is_floating is false, then the plugin has to embed its window into the parent window, see
    // set_parent().
    //
    // After this call, the GUI may not be visible yet; don't forget to call show().
    //
    // Returns true if the GUI is successfully created.
    // [main-thread]
    bool function(const clap_plugin_t *plugin, const char *api, bool is_floating) create;

    // Free all resources associated with the gui.
    // [main-thread]
    void function(const clap_plugin_t *plugin) destroy;

    // Set the absolute GUI scaling factor, and override any OS info.
    // Should not be used if the windowing api relies upon logical pixels.
    //
    // If the plugin prefers to work out the scaling factor itself by querying the OS directly,
    // then ignore the call.
    //
    // scale = 2 means 200% scaling.
    //
    // Returns true if the scaling could be applied
    // Returns false if the call was ignored, or the scaling could not be applied.
    // [main-thread]
    bool function(const clap_plugin_t *plugin, double scale) set_scale;

    // Get the current size of the plugin UI.
    // clap_plugin_gui->create() must have been called prior to asking the size.
    //
    // Returns true if the plugin could get the size.
    // [main-thread]
    bool function(const clap_plugin_t *plugin, uint *width, uint *height) get_size;

    // Returns true if the window is resizeable (mouse drag).
    // [main-thread & !floating]
    bool function(const clap_plugin_t *plugin) can_resize;

    // Returns true if the plugin can provide hints on how to resize the window.
    // [main-thread & !floating]
    bool function(const clap_plugin_t *plugin, clap_gui_resize_hints_t *hints) get_resize_hints;

    // If the plugin gui is resizable, then the plugin will calculate the closest
    // usable size which fits in the given size.
    // This method does not change the size.
    //
    // Returns true if the plugin could adjust the given size.
    // [main-thread & !floating]
    bool function(const clap_plugin_t *plugin, uint *width, uint *height) adjust_size;

    // Sets the window size.
    //
    // Returns true if the plugin could resize its window to the given size.
    // [main-thread & !floating]
    bool function(const clap_plugin_t *plugin, uint width, uint height) set_size;

    // Embeds the plugin window into the given window.
    //
    // Returns true on success.
    // [main-thread & !floating]
    bool function(const clap_plugin_t *plugin, const clap_window_t *window) set_parent;

    // Set the plugin floating window to stay above the given window.
    //
    // Returns true on success.
    // [main-thread & floating]
    bool function(const clap_plugin_t *plugin, const clap_window_t *window) set_transient;

    // Suggests a window title. Only for floating windows.
    //
    // [main-thread & floating]
    void function(const clap_plugin_t *plugin, const char *title) suggest_title;

    // Show the window.
    //
    // Returns true on success.
    // [main-thread]
    bool function(const clap_plugin_t *plugin) show;

    // Hide the window, this method does not free the resources, it just hides
    // the window content. Yet it may be a good idea to stop painting timers.
    //
    // Returns true on success.
    // [main-thread]
    bool function(const clap_plugin_t *plugin) hide;
}

struct clap_host_gui_t 
{
extern(C) nothrow @nogc:

    // The host should call get_resize_hints() again.
    // [thread-safe & !floating]
    void function(const clap_host_t *host) resize_hints_changed; 

    // Request the host to resize the client area to width, height.
    // Return true if the new size is accepted, false otherwise.
    // The host doesn't have to call set_size().
    //
    // Note: if not called from the main thread, then a return value simply means that the host
    // acknowledged the request and will process it asynchronously. If the request then can't be
    // satisfied then the host will call set_size() to revert the operation.
    // [thread-safe & !floating]
    bool function(const clap_host_t *host, uint width, uint height) request_resize;

    // Request the host to show the plugin gui.
    // Return true on success, false otherwise.
    // [thread-safe]
    bool function(const clap_host_t *host) request_show;

    // Request the host to hide the plugin gui.
    // Return true on success, false otherwise.
    // [thread-safe]
    bool function(const clap_host_t *host) request_hide;

    // The floating window has been closed, or the connection to the gui has been lost.
    //
    // If was_destroyed is true, then the host must call clap_plugin_gui->destroy() to acknowledge
    // the gui destruction.
    // [thread-safe]
    void function(const clap_host_t *host, bool was_destroyed) closed;
}

// host.h

struct clap_host_t 
{
extern(C) nothrow @nogc:
    clap_version_t clap_version; // initialized to CLAP_VERSION

    void* host_data; // reserved pointer for the host

    // name and version are mandatory.
    const(char) *name;    // eg: "Bitwig Studio"
    const(char) *vendor;  // eg: "Bitwig GmbH"
    const(char) *url;     // eg: "https://bitwig.com"
    const(char) *version_; // eg: "4.3", see plugin.h for advice on how to format the version

    // Query an extension.
    // The returned pointer is owned by the host.
    // It is forbidden to call it before plugin->init().
    // You can call it within plugin->init() call, and after.
    // [thread-safe]
    const(void)* function(const(clap_host_t) *host, const(char)* extension_id) get_extension;

    // Request the host to deactivate and then reactivate the plugin.
    // The operation may be delayed by the host.
    // [thread-safe]
    void function(const(clap_host_t)*host) request_restart;

    // Request the host to activate and start processing the plugin.
    // This is useful if you have external IO and need to wake up the plugin from "sleep".
    // [thread-safe]
    void function(const(clap_host_t)*host) request_process;

    // Request the host to schedule a call to plugin->on_main_thread(plugin) on the main thread.
    // [thread-safe]
    void function(const(clap_host_t)*host) request_callback;
}

// latency.h

struct clap_plugin_latency_t
{
extern(C) nothrow @nogc:
    // Returns the plugin latency in samples.
    // [main-thread & (being-activated | active)]
    uint function(const(clap_plugin_t)* plugin) get;
}

struct clap_host_latency_t 
{
extern(C) nothrow @nogc:
    // Tell the host that the latency changed.
    // The latency is only allowed to change during plugin->activate.
    // If the plugin is activated, call host->request_restart()
    // [main-thread & being-activated]
    void function(const(clap_host_t)* host) changed;
}

// state.h

struct clap_plugin_state_t 
{
extern(C) nothrow @nogc:
    // Saves the plugin state into stream.
    // Returns true if the state was correctly saved.
    // [main-thread]
    bool function(const(clap_plugin_t)* plugin, const(clap_ostream_t)* stream) save;

    // Loads the plugin state from stream.
    // Returns true if the state was correctly restored.
    // [main-thread]
    bool function(const(clap_plugin_t)* plugin, const(clap_istream_t)* stream) load;
}

struct clap_host_state_t 
{
extern(C) nothrow @nogc:
    // Tell the host that the plugin state has changed and should be saved again.
    // If a parameter value changes, then it is implicit that the state is dirty.
    // [main-thread]
    void function(const(clap_host_t)* host) mark_dirty;
}


// stream.h

/// @page Streams
///
/// ## Notes on using streams
///
/// When working with `clap_istream` and `clap_ostream` objects to load and save
/// state, it is important to keep in mind that the host may limit the number of
/// bytes that can be read or written at a time. The return values for the
/// stream read and write functions indicate how many bytes were actually read
/// or written. You need to use a loop to ensure that you read or write the
/// entirety of your state. Don't forget to also consider the negative return
/// values for the end of file and IO error codes.

struct clap_istream_t 
{
extern(C) nothrow @nogc:
    void *ctx; // reserved pointer for the stream

    // returns the number of bytes read; 0 indicates end of file and -1 a read error
    long function(const(clap_istream_t)* stream, void *buffer, ulong size) read;
}

struct clap_ostream_t 
{
extern(C) nothrow @nogc:
    void *ctx; // reserved pointer for the stream

    // returns the number of bytes written; -1 on write error
    long function(const(clap_ostream_t)* stream, const(void)* buffer, ulong size) write;
}

// Helper function to perform a whole read in a loop.
// Return `size` if `size` bytes were read.
// -1 on error or if less bytes were read than `size`.
// There is no end-of-file indication.
long readExactly(const(clap_istream_t)* stream, void *buffer, ulong size)
{
    ulong remain = size;
    ubyte* bbuf = cast(ubyte*) buffer;
    while (remain > 0)
    {
        long read = stream.read(stream, bbuf, remain);
        if (read == -1)
            return -1;

        remain -= read;
        assert(remain >= 0);
        bbuf   += read;

        if (read == 0) // end of file
            break;
    }
    return (remain == 0) ? size : -1;
}

// Helper function to perform a whole read in a loop.
// Return `size` if `size` bytes were read.
// -1 on error or if less bytes were read than `size`.
// There is no end-of-file indication.
long writeExactly(const(clap_ostream_t)* stream, void *buffer, ulong size)
{
    ulong remain = size;
    ubyte* bbuf = cast(ubyte*) buffer;
    while (remain > 0)
    {
        long written = stream.write(stream, bbuf, remain);
        if (written == -1)
            return -1;

        remain -= written;
        assert(remain >= 0);
        bbuf   += written;

        if (written == 0) // nothing written, exit
            break;
    }
    return (remain == 0) ? size : -1;
}


// tail.h

struct clap_plugin_tail_t 
{
extern(C) nothrow @nogc:
    // Returns tail length in samples.
    // Any value greater or equal to INT32_MAX implies infinite tail.
    // [main-thread,audio-thread]
    uint function(const(clap_plugin_t)* plugin) get;
}

struct clap_host_tail_t 
{
extern(C) nothrow @nogc:
    // Tell the host that the tail has changed.
    // [audio-thread]
    void function(const(clap_host_t)* host) changed;
}


// universal-id.h

// Pair of plugin ABI and plugin identifier.
//
// If you want to represent other formats please send us an update to the comment with the
// name of the abi and the representation of the id.
struct clap_universal_plugin_id_t 
{
    // The plugin ABI name, in lowercase and null-terminated.
    // eg: "clap", "vst3", "vst2", "au", ...
    const(char)* abi;

    // The plugin ID, null-terminated and formatted as follows:
    //
    // CLAP: use the plugin id
    //   eg: "com.u-he.diva"
    //
    // AU: format the string like "type:subt:manu"
    //   eg: "aumu:SgXT:VmbA"
    //
    // VST2: print the id as a signed 32-bits integer
    //   eg: "-4382976"
    //
    // VST3: print the id as a standard UUID
    //   eg: "123e4567-e89b-12d3-a456-426614174000"
    const(char)* id;
}

// timestamp.h

// This type defines a timestamp: the number of seconds since UNIX EPOCH.
// See C's time_t time(time_t *).
alias clap_timestamp = ulong;


// preset-discovery.h

/*
Preset Discovery API.

Preset Discovery enables a plug-in host to identify where presets are found, what
extensions they have, which plug-ins they apply to, and other metadata associated with the
presets so that they can be indexed and searched for quickly within the plug-in host's browser.

This has a number of advantages for the user:
- it allows them to browse for presets from one central location in a consistent way
- the user can browse for presets without having to commit to a particular plug-in first

The API works as follow to index presets and presets metadata:
1. clap_plugin_entry.get_factory(CLAP_PRESET_DISCOVERY_FACTORY_ID)
2. clap_preset_discovery_factory_t.create(...)
3. clap_preset_discovery_provider.init() (only necessary the first time, declarations
can be cached)
`-> clap_preset_discovery_indexer.declare_filetype()
`-> clap_preset_discovery_indexer.declare_location()
`-> clap_preset_discovery_indexer.declare_soundpack() (optional)
`-> clap_preset_discovery_indexer.set_invalidation_watch_file() (optional)
4. crawl the given locations and monitor file system changes
`-> clap_preset_discovery_indexer.get_metadata() for each presets files

Then to load a preset, use ext/draft/preset-load.h.
TODO: create a dedicated repo for other plugin abi preset-load extension.

The design of this API deliberately does not define a fixed set tags or categories. It is the
plug-in host's job to try to intelligently map the raw list of features that are found for a
preset and to process this list to generate something that makes sense for the host's tagging and
categorization system. The reason for this is to reduce the work for a plug-in developer to add
Preset Discovery support for their existing preset file format and not have to be concerned with
all the different hosts and how they want to receive the metadata.

VERY IMPORTANT:
- the whole indexing process has to be **fast**
- clap_preset_provider->get_metadata() has to be fast and avoid unnecessary operations
- the whole indexing process must not be interactive
- don't show dialogs, windows, ...
- don't ask for user input
*/

// Use it to retrieve const clap_preset_discovery_factory_t* from
// clap_plugin_entry.get_factory()
enum string CLAP_PRESET_DISCOVERY_FACTORY_ID = "clap.preset-discovery-factory/2";

// The latest draft is 100% compatible.
// This compat ID may be removed in 2026.
enum string CLAP_PRESET_DISCOVERY_FACTORY_ID_COMPAT = "clap.preset-discovery-factory/draft-2";

alias clap_preset_discovery_location_kind = int;
enum : clap_preset_discovery_location_kind 
{
    // The preset are located in a file on the OS filesystem.
    // The location is then a path which works with the OS file system functions (open, stat, ...)
    // So both '/' and '\' shall work on Windows as a separator.
    CLAP_PRESET_DISCOVERY_LOCATION_FILE = 0,

    // The preset is bundled within the plugin DSO itself.
    // The location must then be null, as the preset are within the plugin itself and then the plugin
    // will act as a preset container.
    CLAP_PRESET_DISCOVERY_LOCATION_PLUGIN = 1,
}

alias clap_preset_discovery_flags = int;
enum : clap_preset_discovery_flags 
{
    // This is for factory or sound-pack presets.
    CLAP_PRESET_DISCOVERY_IS_FACTORY_CONTENT = 1 << 0,

    // This is for user presets.
    CLAP_PRESET_DISCOVERY_IS_USER_CONTENT = 1 << 1,

    // This location is meant for demo presets, those are preset which may trigger
    // some limitation in the plugin because they require additional features which the user
    // needs to purchase or the content itself needs to be bought and is only available in
    // demo mode.
    CLAP_PRESET_DISCOVERY_IS_DEMO_CONTENT = 1 << 2,

    // This preset is a user's favorite
    CLAP_PRESET_DISCOVERY_IS_FAVORITE = 1 << 3,
}


// Receiver that receives the metadata for a single preset file.
// The host would define the various callbacks in this interface and the preset parser function
// would then call them.
//
// This interface isn't thread-safe.
struct clap_preset_discovery_metadata_receiver_t 
{
extern(C) nothrow @nogc:

    void *receiver_data; // reserved pointer for the metadata receiver

    // If there is an error reading metadata from a file this should be called with an error
    // message.
    // os_error: the operating system error, if applicable. If not applicable set it to a non-error
    // value, eg: 0 on unix and Windows.
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  int os_error,
                  const(char) *error_message) on_error;

    // This must be called for every preset in the file and before any preset metadata is
    // sent with the calls below.
    //
    // If the preset file is a preset container then name and load_key are mandatory, otherwise
    // they are optional.
    //
    // The load_key is a machine friendly string used to load the preset inside the container via a
    // the preset-load plug-in extension. The load_key can also just be the subpath if that's what
    // the plugin wants but it could also be some other unique id like a database primary key or a
    // binary offset. It's use is entirely up to the plug-in.
    //
    // If the function returns false, then the provider must stop calling back into the receiver.
    bool function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  const(char)*name,
                  const(char)*load_key) begin_preset;

    // Adds a plug-in id that this preset can be used with.
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  const(clap_universal_plugin_id_t)* plugin_id) add_plugin_id;

    // Sets the sound pack to which the preset belongs to.
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  const(char)* soundpack_id) set_soundpack_id;

    // Sets the flags, see clap_preset_discovery_flags.
    // If unset, they are then inherited from the location.
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  uint flags) set_flags;

    // Adds a creator name for the preset.
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  const(char)* creator) add_creator;

    // Sets a description of the preset.
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  const(char)* description) set_description;

    // Sets the creation time and last modification time of the preset.
    // If one of the times isn't known, set it to CLAP_TIMESTAMP_UNKNOWN.
    // If this function is not called, then the indexer may look at the file's creation and
    // modification time.
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  clap_timestamp creation_time,
                  clap_timestamp modification_time) set_timestamps;

    // Adds a feature to the preset.
    //
    // The feature string is arbitrary, it is the indexer's job to understand it and remap it to its
    // internal categorization and tagging system.
    //
    // However, the strings from plugin-features.h should be understood by the indexer and one of the
    // plugin category could be provided to determine if the preset will result into an audio-effect,
    // instrument, ...
    //
    // Examples:
    // kick, drum, tom, snare, clap, cymbal, bass, lead, metalic, hardsync, crossmod, acid,
    // distorted, drone, pad, dirty, etc...
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  const(char)* feature) add_feature;

    // Adds extra information to the metadata.
    void function(const(clap_preset_discovery_metadata_receiver_t)* receiver,
                  const(char)* key,
                  const(char)* value) add_extra_info;
}

struct clap_preset_discovery_filetype_t 
{
    const(char)* name;
    const(char)* description; // optional

    // `.' isn't included in the string.
    // If empty or NULL then every file should be matched.
    const(char)* file_extension;
}

// Defines a place in which to search for presets
struct clap_preset_discovery_location_t 
{
    uint         flags; // see enum clap_preset_discovery_flags
    const(char)* name;  // name of this location
    uint         kind;  // See clap_preset_discovery_location_kind

    // Actual location in which to crawl presets.
    // For FILE kind, the location can be either a path to a directory or a file.
    // For PLUGIN kind, the location must be null.
    const(char)* location;
}

// Describes an installed sound pack.
struct clap_preset_discovery_soundpack_t 
{
    uint          flags;              // see enum clap_preset_discovery_flags
    const(char)   *id;                // sound pack identifier
    const(char)   *name;              // name of this sound pack
    const(char)   *description;       // optional, reasonably short description of the sound pack
    const(char)   *homepage_url;      // optional, url to the pack's homepage
    const(char)   *vendor;            // optional, sound pack's vendor
    const(char)   *image_path;        // optional, an image on disk
    clap_timestamp release_timestamp; // release date, CLAP_TIMESTAMP_UNKNOWN if unavailable
}

// Describes a preset provider
struct clap_preset_discovery_provider_descriptor_t 
{
    clap_version_t clap_version; // initialized to CLAP_VERSION
    const(char)   *id;           // see plugin.h for advice on how to choose a good identifier
    const(char)   *name;         // eg: "Diva's preset provider"
    const(char)   *vendor;       // optional, eg: u-he
}

// This interface isn't thread-safe.
struct clap_preset_discovery_provider_t 
{
extern(C) nothrow @nogc:

    const(clap_preset_discovery_provider_descriptor_t)* desc;

    void* provider_data; // reserved pointer for the provider

    // Initialize the preset provider.
    // It should declare all its locations, filetypes and sound packs.
    // Returns false if initialization failed.
    bool function(const(clap_preset_discovery_provider_t)* provider) init_;

    // Destroys the preset provider
    void function(const(clap_preset_discovery_provider_t)* provider) destroy;

    // reads metadata from the given file and passes them to the metadata receiver
    // Returns true on success.
    bool function(const(clap_preset_discovery_provider_t)* provider,
                  uint location_kind,
                  const(char)* location,
                  const(clap_preset_discovery_metadata_receiver_t)* metadata_receiver) get_metadata;

    // Query an extension.
    // The returned pointer is owned by the provider.
    // It is forbidden to call it before provider->init().
    // You can call it within provider->init() call, and after.
    const(void)* function(const(clap_preset_discovery_provider_t)* provider,
                          const(char)* extension_id) get_extension;
}

// This interface isn't thread-safe
struct clap_preset_discovery_indexer_t
{
extern(C) nothrow @nogc:

    clap_version_t clap_version; // initialized to CLAP_VERSION
    const(char) *name;     // eg: "Bitwig Studio"
    const(char) *vendor;   // optional, eg: "Bitwig GmbH"
    const(char) *url;      // optional, eg: "https://bitwig.com"
    const(char) *version_; // optional, eg: "4.3", see plugin.h for advice on how to format the version

    void *indexer_data; // reserved pointer for the indexer

    // Declares a preset filetype.
    // Don't callback into the provider during this call.
    // Returns false if the filetype is invalid.
    bool function(const(clap_preset_discovery_indexer_t)* indexer,
                  const(clap_preset_discovery_filetype_t)* filetype) declare_filetype;

    // Declares a preset location.
    // Don't callback into the provider during this call.
    // Returns false if the location is invalid.
    bool function(const(clap_preset_discovery_indexer_t)* indexer,
                  const(clap_preset_discovery_location_t)* location) declare_location;

    // Declares a sound pack.
    // Don't callback into the provider during this call.
    // Returns false if the sound pack is invalid.
    bool function(const(clap_preset_discovery_indexer_t)* indexer,
                  const(clap_preset_discovery_soundpack_t)* soundpack) declare_soundpack;

    // Query an extension.
    // The returned pointer is owned by the indexer.
    // It is forbidden to call it before provider->init().
    // You can call it within provider->init() call, and after.
    const(void)* function(const(clap_preset_discovery_indexer_t)* indexer,
                          const(char)* extension_id) get_extension;
}

// Every methods in this factory must be thread-safe.
// It is encouraged to perform preset indexing in background threads, maybe even in background
// process.
//
// The host may use clap_plugin_invalidation_factory to detect filesystem changes
// which may change the factory's content.
struct clap_preset_discovery_factory_t 
{
extern(C) nothrow @nogc:

    // Get the number of preset providers available.
    // [thread-safe]
    uint function(const(clap_preset_discovery_factory_t)* factory) count;

    // Retrieves a preset provider descriptor by its index.
    // Returns null in case of error.
    // The descriptor must not be freed.
    // [thread-safe]
    const(clap_preset_discovery_provider_descriptor_t)* 
        function(const(clap_preset_discovery_factory_t)* factory, uint index) get_descriptor;

    // Create a preset provider by its id.
    // The returned pointer must be freed by calling preset_provider->destroy(preset_provider);
    // The preset provider is not allowed to use the indexer callbacks in the create method.
    // It is forbidden to call back into the indexer before the indexer calls provider->init().
    // Returns null in case of error.
    // [thread-safe]
    const(clap_preset_discovery_provider_t)* 
        function(const(clap_preset_discovery_factory_t)* factory,
                 const(clap_preset_discovery_indexer_t)* indexer,
                 const(char)* provider_id) create;
}


// preset-load.h

enum string CLAP_EXT_PRESET_LOAD = "clap.preset-load/2";

// The latest draft is 100% compatible.
// This compat ID may be removed in 2026.
enum string CLAP_EXT_PRESET_LOAD_COMPAT = "clap.preset-load.draft/2";

struct clap_plugin_preset_load_t 
{
extern(C) nothrow @nogc:

    // Loads a preset in the plugin native preset file format from a location.
    // The preset discovery provider defines the location and load_key to be passed to this function.
    // Returns true on success.
    // [main-thread]
    bool                 function(const(clap_plugin_t)*plugin,
                                  uint                 location_kind,
                                  const(char)         *location,
                                  const(char)         *load_key) from_location;
}

struct clap_host_preset_load_t 
{
extern(C) nothrow @nogc:

    // Called if clap_plugin_preset_load.load() failed.
    // os_error: the operating system error, if applicable. If not applicable set it to a non-error
    // value, eg: 0 on unix and Windows.
    //
    // [main-thread]
    void            function(const(clap_host_t)*host,
                             uint               location_kind,
                             const(char)       *location,
                             const(char)       *load_key,
                             int                os_error,
                             const(char)       *msg) on_error;

    // Informs the host that the following preset has been loaded.
    // This contributes to keep in sync the host preset browser and plugin preset browser.
    // If the preset was loaded from a container file, then the load_key must be set, otherwise it
    // must be null.
    //
    // [main-thread]
    void           function(const(clap_host_t)*host,
                            uint               location_kind,
                            const(char)       *location,
                            const(char)       *load_key) loaded;
}

// audio-port-config.h

/// @page Audio Ports Config
///
/// This extension let the plugin provide port configurations presets.
/// For example mono, stereo, surround, ambisonic, ...
///
/// After the plugin initialization, the host may scan the list of configurations and eventually
/// select one that fits the plugin context. The host can only select a configuration if the plugin
/// is deactivated.
///
/// A configuration is a very simple description of the audio ports:
/// - it describes the main input and output ports
/// - it has a name that can be displayed to the user
///
/// The idea behind the configurations, is to let the user choose one via a menu.
///
/// Plugins with very complex configuration possibilities should let the user configure the ports
/// from the plugin GUI, and call @ref clap_host_audio_ports.rescan(CLAP_AUDIO_PORTS_RESCAN_ALL).
///
/// To inquire the exact bus layout, the plugin implements the clap_plugin_audio_ports_config_info_t
/// extension where all busses can be retrieved in the same way as in the audio-port extension.

enum string CLAP_EXT_AUDIO_PORTS_CONFIG = "clap.audio-ports-config";

enum string CLAP_EXT_AUDIO_PORTS_CONFIG_INFO = "clap.audio-ports-config-info/1";

// The latest draft is 100% compatible.
// This compat ID may be removed in 2026.
enum string CLAP_EXT_AUDIO_PORTS_CONFIG_INFO_COMPAT =
    "clap.audio-ports-config-info/draft-0";

// Minimalistic description of ports configuration
struct clap_audio_ports_config_t 
{
    clap_id id;
    char[CLAP_NAME_SIZE] name;

    uint input_port_count;
    uint output_port_count;

    // main input info
    bool        has_main_input;
    uint        main_input_channel_count;
    const(char)*main_input_port_type;

    // main output info
    bool        has_main_output;
    uint        main_output_channel_count;
    const(char)*main_output_port_type;
}

// The audio ports config scan has to be done while the plugin is deactivated.
struct clap_plugin_audio_ports_config_t 
{
extern(C) nothrow @nogc:
    // Gets the number of available configurations
    // [main-thread]
    uint function(const(clap_plugin_t)* plugin) count;

    // Gets information about a configuration
    // Returns true on success and stores the result into config.
    // [main-thread]
    bool function(const(clap_plugin_t)* plugin,
                  uint index,
                  clap_audio_ports_config_t* config) get;

    // Selects the configuration designated by id
    // Returns true if the configuration could be applied.
    // Once applied the host should scan again the audio ports.
    // [main-thread & plugin-deactivated]
    bool function(const(clap_plugin_t)* plugin, clap_id config_id) select;
}

// Extended config info
struct clap_plugin_audio_ports_config_info_t 
{
extern(C) nothrow @nogc:
    // Gets the id of the currently selected config, or CLAP_INVALID_ID if the current port
    // layout isn't part of the config list.
    //
    // [main-thread]
    clap_id function(const clap_plugin_t *plugin) current_config;

    // Get info about an audio port, for a given config_id.
    // This is analogous to clap_plugin_audio_ports.get().
    // Returns true on success and stores the result into info.
    // [main-thread]
    bool function(const(clap_plugin_t)* plugin,
                  clap_id                 config_id,
                  uint                    port_index,
                  bool                    is_input,
                  clap_audio_port_info_t *info) get;
}

struct clap_host_audio_ports_config_t 
{
extern(C) nothrow @nogc:
    // Rescan the full list of configs.
    // [main-thread]
    void function(const(clap_host_t)*host) rescan;
}
