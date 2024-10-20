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
module dplug.clap.entry;

nothrow @nogc:

import core.stdc.string;
import dplug.core.runtime;
import dplug.core.nogc;
import dplug.client.client;
import dplug.client.daw;
import dplug.clap.client;


// plugin-features.h


// Plugin category 

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

static immutable CLAP_PLUGIN_FEATURE_MONO = "mono";
static immutable CLAP_PLUGIN_FEATURE_STEREO = "stereo";
static immutable CLAP_PLUGIN_FEATURE_SURROUND = "surround";
static immutable CLAP_PLUGIN_FEATURE_AMBISONIC = "ambisonic";



// Plugin 

// version.h

import dplug.clap;
import dplug.clap.clapversion;

import core.stdc.stdio;
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
        __gshared clap_plugin_factory_t g_factory;
        g_factory.get_plugin_count = &factory_get_plugin_count;
        g_factory.get_plugin_descriptor = &factory_get_plugin_descriptor!ClientClass;
        g_factory.create_plugin = &factory_create_plugin!ClientClass;
        return &g_factory;
    }
    return null;
}

extern(C)
{
    // Get the number of plugins available.
    uint factory_get_plugin_count(const(clap_plugin_factory_t)* factory)
    {
        return 1;
    }

    // help function to be used by both factory_get_plugin_descriptor and create_plugin
    const(clap_plugin_descriptor_t)* get_descriptor_from_client(Client client)
    {
        // Fill with information from PluginClass
        __gshared clap_plugin_descriptor_t desc;

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
            case effectImaging:             clapCategory = "utility"; break; // No imaging categiry in CLAP
            case effectModulation:          clapCategory = "chorus"; break; // Note: CLAP has chorus and flanger
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

        // Create a client just for the purpose of describing the plug-in
        ClientClass client = mallocNew!ClientClass();
        scope(exit) client.destroyFree();
        return get_descriptor_from_client(client);
    }

    const(clap_plugin_t)* factory_create_plugin(ClientClass)(const(clap_plugin_factory_t)*factory,
                                const(void)* host, //TODO IHostCommand
                                const(char)* plugin_id)
    {
        ScopedForeignCallback!(false, true) sfc;
        sfc.enter();

        // Create a Client and a CLAPClient, who hold that and the CLAP structure        
        ClientClass client = mallocNew!ClientClass();
        CLAPClient clapClient = mallocNew!CLAPClient(client, host);

        return clapClient.get_clap_plugin();
    }
}

// factory.h

struct clap_plugin_factory_t 
{
nothrow @nogc extern(C):
   uint function(const(clap_plugin_factory_t)*) get_plugin_count;
   const(clap_plugin_descriptor_t)* function(const(clap_plugin_factory_t)*,uint) get_plugin_descriptor;
   const(clap_plugin_t)* function(const(clap_plugin_factory_t)*, const(void)*, const(char)*) create_plugin;
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
nothrow @nogc extern(C):

    const(clap_plugin_descriptor_t)* desc;

    void *plugin_data; // reserved pointer for the plugin

    // Must be called after creating the plugin.
    // If init returns false, the host must destroy the plugin instance.
    // If init returns true, then the plugin is initialized and in the deactivated state.
    // Unlike in `plugin-factory::create_plugin`, in init you have complete access to the host 
    // and host extensions, so clap related setup activities should be done here rather than in
    // create_plugin.
    // [main-thread]
    bool function(const(clap_plugin_t)* plugin) init;

    // Free the plugin and its resources.
    // It is required to deactivate the plugin prior to this call.
    // [main-thread & !active]
    void function(const(clap_plugin_t)* plugin) destroy;

    // Activate and deactivate the plugin.
    // In this call the plugin may allocate memory and prepare everything needed for the process
    // call. The process's sample rate will be constant and process's frame count will included in
    // the [min, max] range, which is bounded by [1, INT32_MAX].
    // Once activated the latency and port configuration must remain constant, until deactivation.
    // Returns true on success.
    // [main-thread & !active]
    bool function(const(clap_plugin_t)* plugin,
                  double                    sample_rate,
                  uint                  min_frames_count,
                  uint                  max_frames_count) activate;

    // [main-thread & active]
    void function(const(clap_plugin_t)*plugin) deactivate;

    // Call start processing before processing.
    // Returns true on success.
    // [audio-thread & active & !processing]
    bool function(const(clap_plugin_t)*plugin) start_processing;

    // Call stop processing before sending the plugin to sleep.
    // [audio-thread & active & processing]
    void function(const(clap_plugin_t)* plugin) stop_processing;

    // - Clears all buffers, performs a full reset of the processing state (filters, oscillators,
    //   envelopes, lfo, ...) and kills all voices.
    // - The parameter's value remain unchanged.
    // - clap_process.steady_time may jump backward.
    //
    // [audio-thread & active]
    void function(const(clap_plugin_t)* plugin) reset;

    // process audio, events, ...
    // All the pointers coming from clap_process_t and its nested attributes,
    // are valid until process() returns.
    // [audio-thread & active & processing]
    clap_process_status function(const(clap_plugin_t)*plugin,
                                 const(/*clap_process_t*/void)* processParams) process;

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


alias clap_process_status = int;//TODO wrong