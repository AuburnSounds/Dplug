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
import dplug.core.runtime;
import dplug.core.nogc;
import dplug.client.client;
import dplug.client.daw;
import dplug.clap.client;
import dplug.clap;
import dplug.clap.clapversion;


// id.h

alias clap_id = uint;
enum clap_id CLAP_INVALID_ID = uint.max;


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
    const(void /*clap_audio_buffer_t*/)*audio_inputs;
    void /*clap_audio_buffer_t*/       *audio_outputs;
    uint audio_inputs_count;
    uint audio_outputs_count;

    // The input event list can't be modified.
    // Input read-only event list. The host will deliver these sorted in sample order.
    const void /*clap_input_events_t*/  *in_events;

    // Output event list. The plugin must insert events in sample sorted order when inserting events
    const void /*clap_output_events_t*/ *out_events;
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
                  uint                out_buffer_capacity) value_to_text;

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

struct clap_event_param_mod 
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

struct clap_event_midi_sysex 
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

// Input event list. The host will deliver these sorted in sample order.
struct clap_input_events_t 
{
    void *ctx; // reserved pointer for the list

    // returns the number of events in the list
    uint function(const(clap_input_events_t) *list) size;

    // Don't free the returned event, it belongs to the list
    const(clap_event_header_t)* function(const(clap_input_events_t)*list, uint index) get;
}

// Output event list. The plugin must insert events in sample sorted order when inserting events
struct clap_output_events_t 
{
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

