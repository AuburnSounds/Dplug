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
module dplug.lv2.lv2_init;

import dplug.lv2.lv2,
       dplug.lv2.midi,
       dplug.lv2.ui,
       dplug.lv2.options,
       dplug.lv2.state;

import dplug.core.vec,
       dplug.core.nogc,
       dplug.core.math,
       dplug.core.lockedqueue,
       dplug.core.runtime,
       dplug.core.fpcontrol,
       dplug.core.thread,
       dplug.core.sync,
       dplug.core.map;

import dplug.client;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.stdint;

import dplug.lv2.lv2client;
import dplug.lv2.urid;
import dplug.lv2.options;

//debug = debugLV2Client;

extern(C) alias generateManifestFromClientCallback = void function(const(ubyte)* fileContents, size_t len, const(char)[] buildDir);

/**
 * Main entry point for LV2 plugins.
 */
template LV2EntryPoint(alias ClientClass)
{
    static immutable enum lv2_descriptor =
        "export extern(C) const(void)* lv2_descriptor(uint index) nothrow @nogc" ~
        "{" ~
        "    return lv2_descriptor_templated!" ~ ClientClass.stringof ~ "(index);" ~
        "}\n";

    static immutable enum lv2_ui_descriptor =
        "export extern(C) const(void)* lv2ui_descriptor(uint index)nothrow @nogc" ~
        "{" ~
        "    return lv2ui_descriptor_templated!" ~ ClientClass.stringof ~ "(index);" ~
        "}\n";

    static immutable enum generate_manifest_from_client =
        "export extern(C) void GenerateManifestFromClient(generateManifestFromClientCallback callback, const(char)[] binaryFileName, const(char)[] buildDir)"  ~
        "{" ~
        "    GenerateManifestFromClient_templated!" ~ ClientClass.stringof ~ "(callback, binaryFileName, buildDir);" ~
        "}\n";

    const char[] LV2EntryPoint = lv2_descriptor ~ lv2_ui_descriptor ~ generate_manifest_from_client;
}

const(LV2_Descriptor)* lv2_descriptor_templated(ClientClass)(uint index) nothrow @nogc
{
    debug(debugLV2Client) debugLog(">lv2_descriptor_templated");
    build_all_lv2_descriptors!ClientClass();
    if(index >= cast(int)(lv2Descriptors.length))
        return null;

    debug(debugLV2Client) debugLog("<lv2_descriptor_templated");
    return &lv2Descriptors[index];
}

const (LV2UI_Descriptor)* lv2ui_descriptor_templated(ClientClass)(uint index) nothrow @nogc
{
    debug(debugLV2Client) debugLog(">lv2ui_descriptor_templated");
    build_all_lv2_descriptors!ClientClass();
    if (hasUI && index == 0)
    {
        debug(debugLV2Client) debugLog("<lv2ui_descriptor_templated");
        return &lv2UIDescriptor;
    }
    else
        return null;
}

extern(C) static LV2_Handle instantiate(ClientClass)(const(LV2_Descriptor)* descriptor,
                                                     double rate,
                                                     const(char)* bundle_path,
                                                     const(LV2_Feature*)* features)
{
    debug(debugLV2Client) debugLog(">instantiate");
    LV2_Handle handle = cast(LV2_Handle)myLV2EntryPoint!ClientClass(descriptor, rate, bundle_path, features);
    debug(debugLV2Client) debugLog("<instantiate");
    return handle;
}


private:

// These are initialized lazily by `build_all_lv2_descriptors`
__gshared bool descriptorsAreInitialized = false;
__gshared LV2_Descriptor[] lv2Descriptors;
__gshared bool hasUI;
__gshared LV2UI_Descriptor lv2UIDescriptor;

// build all needed LV2_Descriptors and LV2UI_Descriptor lazily
void build_all_lv2_descriptors(ClientClass)() nothrow @nogc
{
    if (descriptorsAreInitialized)
        return;

    debug(debugLV2Client) debugLog(">build_all_lv2_descriptors");

    // Build a client
    auto client = mallocNew!ClientClass();
    scope(exit) client.destroyFree();

    LegalIO[] legalIOs = client.legalIOs();

    lv2Descriptors = mallocSlice!LV2_Descriptor(legalIOs.length); // Note: leaked

    char[256] uriBuf;

    for(int io = 0; io < cast(int)(legalIOs.length); io++)
    {
        // Make an URI for this I/O configuration
        sprintPluginURI_IO(uriBuf.ptr, 256, client.pluginHomepage(), client.getPluginUniqueID(), legalIOs[io]);

        lv2Descriptors[io] = LV2_Descriptor.init;

        lv2Descriptors[io].URI = stringDup(uriBuf.ptr).ptr;
        lv2Descriptors[io].instantiate = &instantiate!ClientClass;
        lv2Descriptors[io].connect_port = &connect_port;
        lv2Descriptors[io].activate = &activate;
        lv2Descriptors[io].run = &run;
        lv2Descriptors[io].deactivate = &deactivate;
        lv2Descriptors[io].cleanup = &cleanup;
        lv2Descriptors[io].extension_data = null;//extension_data; support it for real
    }


    if (client.hasGUI())
    {
        hasUI = true;

        // Make an URI for this the UI
        sprintPluginURI_UI(uriBuf.ptr, 256, client.pluginHomepage(), client.getPluginUniqueID());

        LV2UI_Descriptor descriptor =
        {
            URI:            stringDup(uriBuf.ptr).ptr,
            instantiate:    &instantiateUI,
            cleanup:        &cleanupUI,
            port_event:     &port_eventUI,
            extension_data: null// &extension_dataUI TODO support it for real
        };
        lv2UIDescriptor = descriptor;
    }
    else
    {
        hasUI = false;
    }
    descriptorsAreInitialized = true;
    debug(debugLV2Client) debugLog("<build_all_lv2_descriptors");
}



LV2Client myLV2EntryPoint(alias ClientClass)(const LV2_Descriptor* descriptor,
                                             double rate,
                                             const char* bundle_path,
                                             const(LV2_Feature*)* features) nothrow @nogc
{
    debug(debugLV2Client) debugLog(">myLV2EntryPoint");
    auto client = mallocNew!ClientClass();

    // Find which decsriptor was used using pointer offset
    int legalIOIndex = cast(int)(descriptor - lv2Descriptors.ptr);
    auto lv2client = mallocNew!LV2Client(client, legalIOIndex);

    lv2client.instantiate(descriptor, rate, bundle_path, features);
    debug(debugLV2Client) debugLog("<myLV2EntryPoint");
    return lv2client;
}

void sprintPluginURI(char* buf, size_t maxChars, string pluginHomepage, char[4] pluginID) nothrow @nogc
{
    CString pluginHomepageZ = CString(pluginHomepage);
    snprintf(buf, maxChars, "%s%2X%2X%2X%2X", pluginHomepageZ.storage, pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
}

void sprintPluginURI_UI(char* buf, size_t maxChars, string pluginHomepage, char[4] pluginID) nothrow @nogc
{
    CString pluginHomepageZ = CString(pluginHomepage);
    snprintf(buf, maxChars, "%s%2X%2X%2X%2X/ui", pluginHomepageZ.storage, pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
}

void sprintPluginURI_IO(char* buf, size_t maxChars, string pluginHomepage, char[4] pluginID, LegalIO io) nothrow @nogc
{
    CString pluginHomepageZ = CString(pluginHomepage);
    int ins = io.numInputChannels;
    int outs = io.numOutputChannels;

    // give user-friendly names
    if (ins == 1 && outs == 1)
    {
        snprintf(buf, maxChars, "%s%2X%2X%2X%2X/mono", pluginHomepageZ.storage,
                 pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
    }
    else if (ins == 2 && outs == 2)
    {
        snprintf(buf, maxChars, "%s%2X%2X%2X%2X/stereo", pluginHomepageZ.storage,
                 pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
    }
    else
    {
        snprintf(buf, maxChars, "%s%2X%2X%2X%2X/%din%dout", pluginHomepageZ.storage,
                                                            pluginID[0], pluginID[1], pluginID[2], pluginID[3],
                                                            ins, outs);
    }
}

public void GenerateManifestFromClient_templated(alias ClientClass)(generateManifestFromClientCallback callback,
                                                                    const(char)[] binaryFileName,
                                                                    const(char)[] buildDir)
{
    // Note: this function is called by D, so it reuses the runtime from dplug-build on Linux
    // FUTURE: make this function nothrow @nogc, to avoid relying on dplug-build runtime
    version(Windows)
    {
        import core.runtime;
        Runtime.initialize();
    }

    version(OSX)
    {
        import core.runtime;
        Runtime.initialize();
    }

    ClientClass client = mallocNew!ClientClass();
    scope(exit) client.destroyFree();

    LegalIO[] legalIOs = client.legalIOs();
    Parameter[] params = client.params();
    string manifest = "";

    manifest ~= "@prefix lv2:     <http://lv2plug.in/ns/lv2core#> .\n";
    manifest ~= "@prefix atom:    <http://lv2plug.in/ns/ext/atom#> .\n";
    manifest ~= "@prefix doap:    <http://usefulinc.com/ns/doap#> .\n";
    manifest ~= "@prefix foaf:    <http://xmlns.com/foaf/0.1/> .\n";
    manifest ~= "@prefix rdf:     <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .\n";
    manifest ~= "@prefix rdfs:    <http://www.w3.org/2000/01/rdf-schema#> .\n";
    manifest ~= "@prefix urid:    <http://lv2plug.in/ns/ext/urid#> .\n";
    manifest ~= "@prefix ui:      <http://lv2plug.in/ns/extensions/ui#>.\n";
    manifest ~= "@prefix opts:    <http://lv2plug.in/ns/ext/options#> .\n\n";

    // Make an URI for the GUI
    char[256] uriBuf;

    string uriGUI = null;
    if(client.hasGUI)
    {
        sprintPluginURI_UI(uriBuf.ptr, 256, client.pluginHomepage(), client.getPluginUniqueID());
        uriGUI = stringIDup(uriBuf.ptr);
    }

    foreach(legalIO; legalIOs)
    {
        // Make an URI for this I/O configuration
        sprintPluginURI_IO(uriBuf.ptr, 256, client.pluginHomepage(), client.getPluginUniqueID(), legalIO);
        string uriIO = stringIDup(uriBuf.ptr);

        manifest ~= escapeRDF_IRI(uriIO) ~ "\n";
        manifest ~= "    a lv2:Plugin" ~ lv2PluginCategory(client.pluginCategory) ~ " ;\n";
        manifest ~= "    lv2:binary " ~ escapeRDF_IRI(binaryFileName) ~ " ;\n";
        manifest ~= "    doap:name " ~ escapeRDFString(client.pluginName) ~ " ;\n";
        manifest ~= "    doap:maintainer [ foaf:name " ~ escapeRDFString(client.vendorName) ~ " ] ;\n";
        manifest ~= "    lv2:requiredFeature opts:options ,\n";
        manifest ~= "                        urid:map ;\n";

        // We do not provide such an interface
        //manifest ~= "    lv2:extensionData <" ~ LV2_OPTIONS__interface ~ "> ; \n";

        if(client.hasGUI)
        {
            manifest ~= "    ui:ui " ~ escapeRDF_IRI(uriGUI) ~ ";\n";
        }

        manifest ~= buildParamPortConfiguration(client.params(), legalIO, client.receivesMIDI);
        // auto presetBank = client.presetBank();
        // for(int i = 0; i < presetBank.numPresets(); ++i)
        // {
        //     auto preset = presetBank.preset(i);
        //     manifest ~= "    eg:" ~ preset.name() ~ "\n";
        //     manifest ~= "        a pset:Preset ;\n";
        //     manifest ~= "        rdfs:label \"" ~ preset.name() ~ "\" ;\n";
        //     manifest ~= "        lv2:appliesTo eg:" ~ pluginURI ~ ";\n";
        //     foreach()
        //     // Set up preset values here
        // }
    }

    // describe UI
    if(client.hasGUI)
    {
        manifest ~= "\n" ~ escapeRDF_IRI(uriGUI) ~ "\n";

        version(OSX)
            manifest ~= "    a ui:CocoaUI;\n";
        else version(Windows)
            manifest ~= "    a ui:WindowsUI;\n";
        else version(linux)
            manifest ~= "    a ui:X11UI;\n";
        else
            static assert("unsupported OS");

        manifest ~= "    lv2:optionalFeature ui:noUserResize ,\n";
        manifest ~= "                        ui:resize ,\n";
        manifest ~= "                        ui:touch ;\n";
        manifest ~= "    lv2:requiredFeature opts:options ,\n";
        manifest ~= "                        urid:map ,\n";
        manifest ~= "                        <http://lv2plug.in/ns/ext/instance-access> ;\n";
        manifest ~= "    ui:binary "  ~ escapeRDF_IRI(binaryFileName) ~ " .\n";
    }

    callback(cast(const(ubyte)*)manifest, manifest.length, buildDir);
}

string lv2PluginCategory(PluginCategory category)
{
    string lv2Category = ", lv2:";
    with(PluginCategory)
    {
        switch(category)
        {
            case effectAnalysisAndMetering:
                lv2Category ~= "AnalyserPlugin";
                break;
            case effectDelay:
                lv2Category ~= "DelayPlugin";
                break;
            case effectDistortion:
                lv2Category ~= "DistortionPlugin";
                break;
            case effectDynamics:
                lv2Category ~= "DynamicsPlugin";
                break;
            case effectEQ:
                lv2Category ~= "EQPlugin";
                break;
            case effectImaging:
                lv2Category ~= "SpatialPlugin";
                break;
            case effectModulation:
                lv2Category ~= "ModulatorPlugin";
                break;
            case effectPitch:
                lv2Category ~= "PitchPlugin";
                break;
            case effectReverb:
                lv2Category ~= "ReverbPlugin";
                break;
            case effectOther:
                lv2Category ~= "UtilityPlugin";
                break;
            case instrumentDrums:
            case instrumentSampler:
            case instrumentSynthesizer:
            case instrumentOther:
                lv2Category ~= "InstrumentPlugin";
                break;
            case invalid:
            default:
                return "";
        }
    }
    return lv2Category;
}

/// escape a UTF-8 string for UTF-8 RDF
/// See_also: https://www.w3.org/TR/turtle/
string escapeRDFString(string s)
{
    string r = "\"";

    foreach(char ch; s)
    {
        switch(ch)
        {
           // escape some whitespace chars
           case '\t': r ~= `\t`; break;
           case '\b': r ~= `\b`; break;
           case '\n': r ~= `\n`; break;
           case '\r': r ~= `\r`; break;
           case '\f': r ~= `\f`; break;
           case '\"': r ~= `\"`; break;
           case '\'': r ~= `\'`; break;
           case '\\': r ~= `\\`; break;
           default:
               r ~= ch;
        }
    }
    r ~= "\"";
    return r;
}

/// Escape a UTF-8 string for UTF-8 IRI literal
/// See_also: https://www.w3.org/TR/turtle/
string escapeRDF_IRI(const(char)[] s)
{
    // We actually remove all characters, because it seems not all hosts properly decode escape sequences
    string r = "<";

    foreach(char ch; s)
    {
        switch(ch)
        {
            // escape some whitespace chars
            case '\0': .. case ' ':
            case '<':
            case '>':
            case '"':
            case '{':
            case '}':
            case '|':
            case '^':
            case '`':
            case '\\':
                break; // skip that character
            default:
                r ~= ch;
        }
    }
    r ~= ">";
    return r;
}

const(char)[] buildParamPortConfiguration(Parameter[] params, LegalIO legalIO, bool hasMIDIInput)
{
    import std.conv: to;
    import std.uni: toLower;

    string paramString = "    lv2:port\n";
    foreach(index, param; params)
    {
        paramString ~= "    [ \n";
        paramString ~= "        a lv2:InputPort , lv2:ControlPort ;\n";
        paramString ~= "        lv2:index " ~ to!string(index) ~ " ;\n";
        paramString ~= "        lv2:symbol " ~ escapeRDFString(param.name).toLower() ~ " ;\n"; // TODO: needed?
        paramString ~= "        lv2:name " ~ escapeRDFString(param.name) ~ " ;\n";
        paramString ~= "        lv2:default " ~ to!string(param.getNormalized()) ~ " ;\n";
        paramString ~= "        lv2:minimum 0.0 ;\n";
        paramString ~= "        lv2:maximum 1.0 ;\n";
        paramString ~= "    ]";
        if(index < params.length -1 || legalIO.numInputChannels > 0 || legalIO.numOutputChannels > 0)
            paramString ~= " , ";
        else
            paramString ~= " . \n";
    }

    foreach(input; 0..legalIO.numInputChannels)
    {
        paramString ~= "    [ \n";
        paramString ~= "        a lv2:AudioPort , lv2:InputPort ;\n";
        paramString ~= "        lv2:index " ~ to!string(params.length + input) ~ ";\n";
        paramString ~= "        lv2:symbol \"Input" ~ to!string(input) ~ "\" ;\n";
        paramString ~= "        lv2:name \"Input" ~ to!string(input) ~ "\" ;\n";
        paramString ~= "    ]";
        if(input < legalIO.numInputChannels - 1 || legalIO.numOutputChannels > 0)
            paramString ~= " , ";
        else
            paramString ~= " . \n";
    }

    foreach(output; 0..legalIO.numOutputChannels)
    {
        paramString ~= "    [ \n";
        paramString ~= "        a lv2:AudioPort , lv2:OutputPort ;\n";
        paramString ~= "        lv2:index " ~ to!string(params.length + legalIO.numInputChannels + output) ~ ";\n";
        paramString ~= "        lv2:symbol \"Output" ~ to!string(output) ~ "\" ;\n";
        paramString ~= "        lv2:name \"Output" ~ to!string(output) ~ "\" ;\n";
        paramString ~= "    ]";
        if(output < legalIO.numOutputChannels - 1 || hasMIDIInput)
            paramString ~= " , ";
        else
            paramString ~= " . \n";
    }

    paramString ~= "    [ \n";
    paramString ~= "        a lv2:InputPort, atom:AtomPort ;\n";
    paramString ~= "        atom:bufferType atom:Sequence ;\n";

    if(hasMIDIInput)
        paramString ~= "        atom:supports <http://lv2plug.in/ns/ext/midi#MidiEvent> ;\n";

    paramString ~= "        atom:supports <http://lv2plug.in/ns/ext/time#Position> ;\n";
    paramString ~= "        lv2:designation lv2:control ;\n";
    paramString ~= "        lv2:index " ~ to!string(params.length + legalIO.numInputChannels + legalIO.numOutputChannels) ~ ";\n";
    paramString ~= "        lv2:symbol \"lv2_events_in\" ;\n";
    paramString ~= "        lv2:name \"Events Input\"\n";
    paramString ~= "    ]";
    paramString ~= " . \n";

    return paramString;
}

/*
    LV2 Callback funtion implementations
*/
extern(C) nothrow @nogc
{
    void connect_port(LV2_Handle instance, uint32_t   port, void* data)
    {
        debug(debugLV2Client) debugLog(">connect_port");
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.connect_port(port, data);
        debug(debugLV2Client) debugLog("<connect_port");
    }

    void activate(LV2_Handle instance)
    {
        debug(debugLV2Client) debugLog(">activate");
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.activate();
        debug(debugLV2Client) debugLog("<activate");
    }

    void run(LV2_Handle instance, uint32_t n_samples)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.run(n_samples);
    }

    void deactivate(LV2_Handle instance)
    {
        debug(debugLV2Client) debugLog(">deactivate");
        debug(debugLV2Client) debugLog("<deactivate");
    }

    void cleanup(LV2_Handle instance)
    {
        debug(debugLV2Client) debugLog(">cleanup");
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.destroyFree();
        debug(debugLV2Client) debugLog("<cleanup");
    }

    const (void)* extension_data(const char* uri)
    {
        debug(debugLV2Client) debugLog(">extension_data");
        debug(debugLV2Client) debugLog("<extension_data");
        return null;
    }

    LV2UI_Handle instantiateUI(const LV2UI_Descriptor* descriptor,
                               const char*             plugin_uri,
                               const char*             bundle_path,
                               LV2UI_Write_Function    write_function,
                               LV2UI_Controller        controller,
                               LV2UI_Widget*           widget,
                               const (LV2_Feature*)*   features)
    {
        debug(debugLV2Client) debugLog(">instantiateUI");
        void* instance_access = lv2_features_data(features, "http://lv2plug.in/ns/ext/instance-access");
        if (instance_access)
        {
            LV2Client lv2client = cast(LV2Client)instance_access;
            lv2client.instantiateUI(descriptor, plugin_uri, bundle_path, write_function, controller, widget, features);
            debug(debugLV2Client) debugLog("<instantiateUI");
            return cast(LV2UI_Handle)instance_access;
        }
        else
        {
            debug(debugLV2Client) debugLog("Error: Instance access is not available\n");
            return null;
        }
    }

    void write_function(LV2UI_Controller controller,
                              uint32_t         port_index,
                              uint32_t         buffer_size,
                              uint32_t         port_protocol,
                              const void*      buffer)
    {
        debug(debugLV2Client) debugLog(">write_function");
        debug(debugLV2Client) debugLog("<write_function");
    }

    void cleanupUI(LV2UI_Handle ui)
    {
        debug(debugLV2Client) debugLog(">cleanupUI");
        LV2Client lv2client = cast(LV2Client)ui;
        lv2client.cleanupUI();
        debug(debugLV2Client) debugLog("<cleanupUI");
    }

    void port_eventUI(LV2UI_Handle ui,
                      uint32_t     port_index,
                      uint32_t     buffer_size,
                      uint32_t     format,
                      const void*  buffer)
    {
        debug(debugLV2Client) debugLog(">port_event");
        LV2Client lv2client = cast(LV2Client)ui;
        lv2client.portEventUI(port_index, buffer_size, format, buffer);
        debug(debugLV2Client) debugLog("<port_event");
    }

    const (void)* extension_dataUI(const char* uri)
    {
/*
        if (strcmp(uri, "http://lv2plug.in/ns/extensions/ui#idleInterface"))
        {

        }
*/
        debug(debugLV2Client) debugLog(">extension_dataUI");
        debug(debugLV2Client) debugLog("<extension_dataUI");
        return null;
    }
}