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
module dplug.lv2.lv2_init;

import dplug.lv2.lv2,
       dplug.lv2.lv2util,
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
import core.stdc.string;
import core.stdc.stdint;

import dplug.lv2.lv2client;
import dplug.lv2.urid;
import dplug.lv2.options;

extern(C) alias generateManifestFromClientCallback = void function(const(ubyte)* fileContents, size_t len, const(char)[] buildDir);

/**
 * Main entry point for LV2 plugins.
 */
template LV2EntryPoint(alias ClientClass)
{

    static immutable enum instantiate = "export extern(C) static LV2_Handle instantiate (const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)" ~
                                        "{" ~
                                        "    return cast(LV2_Handle)myLV2EntryPoint!" ~ ClientClass.stringof ~ "(descriptor, rate, bundle_path, features);" ~
                                        "}\n";

    static immutable enum lv2_descriptor =  "import core.stdc.stdint; import core.stdc.stdio; import core.stdc.string;\n" ~
                                            "export extern(C) const (LV2_Descriptor)* lv2_descriptor(uint32_t index)" ~
                                            "{" ~
                                            "    buildDescriptor(index);" ~
                                            "    return &lv2Descriptors[index];" ~
                                            "}\n";

    static immutable enum lv2_ui_descriptor = "export extern(C) const (LV2UI_Descriptor)* lv2ui_descriptor(uint32_t index)\n" ~
                                               "{" ~
                                               "    switch(index) {" ~
                                               "        case 0:" ~
                                               "            return &lv2UIDescriptor;" ~
                                               "        default: return null;" ~
                                               "    }" ~
                                               "}\n";

    static immutable enum build_descriptor =  "nothrow void buildDescriptor(uint32_t index) {" ~
                                              "    const(char)* uri = pluginURIFromClient!" ~ ClientClass.stringof ~ "(index);" ~
                                              "    LV2_Descriptor descriptor = { uri, &instantiate, &connect_port, &activate, &run, &deactivate, &cleanup, &extension_data };" ~
                                              "    lv2Descriptors[index] = descriptor;" ~
                                              "}\n";

    static immutable enum generate_manifest_from_client = "export extern(C) void GenerateManifestFromClient(generateManifestFromClientCallback callback, const(char)[] binaryFileName, const(char)[] licensePath, const(char)[] buildDir)"  ~
                                                       "{" ~
                                                       "    GenerateManifestFromClientInternal!" ~ ClientClass.stringof ~ "(callback, binaryFileName, licensePath, buildDir);" ~
                                                       "}\n";

    const char[] LV2EntryPoint = instantiate ~ lv2_descriptor ~ lv2_ui_descriptor ~ build_descriptor ~ generate_manifest_from_client;
}

extern(C)
{
    __gshared Map!(string, int) uriMap;
    __gshared LV2_Descriptor[] lv2Descriptors;
    __gshared LV2UI_Descriptor lv2UIDescriptor;
}

nothrow LV2Client myLV2EntryPoint(alias ClientClass)(const LV2_Descriptor* descriptor, double rate, const char* bundle_path, const(LV2_Feature*)* features)
{
    auto client = mallocNew!ClientClass();
    auto lv2client = mallocNew!LV2Client(client, &uriMap);
    lv2client.instantiate(descriptor, rate, bundle_path, features);
    return lv2client;
}

nothrow @nogc const(char)* pluginURIFromClient(alias ClientClass)(int index)
{
    uriMap = makeMap!(string, int);
    auto client = mallocNew!ClientClass();
    auto legalIOs = client.buildLegalIO();
    lv2Descriptors = mallocSlice!LV2_Descriptor(legalIOs.length);
    PluginInfo pluginInfo = client.buildPluginInfo();

    size_t baseURILen = pluginInfo.pluginHomepage.length + pluginInfo.pluginUniqueID.length + 1;
    char[] baseURI = mallocSlice!char(baseURILen);

    baseURI[0..pluginInfo.pluginHomepage.length] = pluginInfo.pluginHomepage;
    size_t pos = pluginInfo.pluginHomepage.length;
    baseURI[pos..pos+1] = ":";
    pos += 1;
    baseURI[pos..pos+pluginInfo.pluginUniqueID.length] = pluginInfo.pluginUniqueID;

    auto uri = uriFromIOConfiguration(cast(char*)baseURI, legalIOs[index]);
    uriMap[cast(string)uri] = index;

    if(pluginInfo.hasGUI)
    {
        buildUIDescriptor(baseURI.ptr);
    }

    client.destroyFree();
    return uri.ptr;
}

void GenerateManifestFromClientInternal(alias ClientClass)(generateManifestFromClientCallback callback, const(char)[] binaryFileName, const(char)[] licensePath, const(char)[] buildDir)
{
    // Note: this function is called by D, so it reuses the runtime from dplug-build!

    import core.stdc.stdio;
    import std.string: toStringz;
    import std.string: fromStringz;
    import std.string: replace;

    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    ClientClass client = mallocNew!ClientClass();
    scope(exit) client.destroyFree();
    LegalIO[] legalIOs = client.legalIOs();
    PluginInfo pluginInfo = client.buildPluginInfo();
    Parameter[] params = client.params();
    string manifest = "";

    //  BUG: this line crashes on Windows
    string baseURI = cast(string)(pluginInfo.pluginHomepage ~ ":" ~ pluginInfo.pluginUniqueID);
    manifest ~= "@prefix lv2:  <http://lv2plug.in/ns/lv2core#> .\n";
    manifest ~= "@prefix atom: <http://lv2plug.in/ns/ext/atom#> .\n";
    manifest ~= "@prefix doap: <http://usefulinc.com/ns/doap#> .\n";
    manifest ~= "@prefix midi: <http://lv2plug.in/ns/ext/midi#> .\n";
    manifest ~= "@prefix rdf:   <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .\n";
    manifest ~= "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n";
    manifest ~= "@prefix urid: <http://lv2plug.in/ns/ext/urid#> .\n";
    manifest ~= "@prefix units: <http://lv2plug.in/ns/extensions/units#> .\n";
    manifest ~= "@prefix ui:    <http://lv2plug.in/ns/extensions/ui#>.\n";
    manifest ~= "@prefix bufsz:   <http://lv2plug.in/ns/ext/buf-size#> .\n";
    manifest ~= "@prefix time: <http://lv2plug.in/ns/ext/time#> .\n";
    manifest ~= "@prefix opts:  <http://lv2plug.in/ns/ext/options#> .\n";
    manifest ~= "@prefix eg: <" ~ pluginInfo.pluginHomepage ~ "> .\n\n";
    

    if(legalIOs.length > 0)
    {

        foreach(legalIO; legalIOs)
        {
            fprintf(stderr, "Configuration: %d Inputs, %d Outputs\n", legalIO.numInputChannels, legalIO.numOutputChannels);
            auto pluginURI = uriFromIOConfiguration(cast(char*)baseURI, legalIO);
            manifest ~= "<" ~ pluginURI ~ ">\n";
            manifest ~= "    a lv2:Plugin" ~ lv2PluginCategory(pluginInfo.category) ~ " ;\n";
            manifest ~= "    lv2:binary <" ~ binaryFileName[0..$].replace(" ", "%20") ~ "> ;\n";
            manifest ~= "    doap:name \"" ~ pluginInfo.pluginName ~ "\" ;\n";
            manifest ~= "    doap:license <" ~ licensePath[0..$] ~ "> ;\n";
            manifest ~= "    lv2:project <" ~ pluginInfo.pluginHomepage ~ "> ;\n";
            manifest ~= "    lv2:extensionData <" ~ LV2_OPTIONS__interface ~ "> ; \n";

            if(pluginInfo.hasGUI)
            {
                manifest ~= "    ui:ui <" ~ baseURI ~ "#ui>;\n";
            }

            manifest ~= buildParamPortConfiguration(client.params(), legalIO, pluginInfo.receivesMIDI);
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
    }

    // describe UI
    if(pluginInfo.hasGUI)
    {
        manifest ~= "\n<" ~ baseURI~ "#ui>\n";
        manifest ~= "    a ui:X11UI;\n";
        manifest ~= "    lv2:optionalFeature ui:noUserResize ,\n";
        manifest ~= "                        ui:resize ,\n";
        manifest ~= "                        ui:touch ;\n";
        manifest ~= "    lv2:requiredFeature <" ~ LV2_OPTIONS__options ~ "> ,\n";
        manifest ~= "                        <" ~ LV2_URID__map ~ "> ;\n";
        manifest ~= "    ui:binary <"  ~ binaryFileName[0..$].replace(" ", "%20") ~ "> .\n";
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

char[] uriFromIOConfiguration(char* baseURI, LegalIO legalIO) nothrow @nogc
{
    char[256] buf;
    snprintf(buf.ptr, 256, "%s%dIn%dOut", baseURI, legalIO.numInputChannels, legalIO.numOutputChannels);
    return stringDup(buf.ptr); // has to be free somewhere
}

void buildUIDescriptor(char* baseURI) nothrow @nogc
{
    char[256] buf;
    snprintf(buf.ptr, 260, "%s%s", baseURI, "#ui".ptr);
    LV2UI_Descriptor descriptor = {
        URI: stringDup(buf.ptr).ptr, 
        instantiate: &instantiateUI, 
        cleanup: &cleanupUI, 
        port_event: &port_event, 
        extension_data: &extension_dataUI
    };
    lv2UIDescriptor = descriptor;
}

const(char)[] buildParamPortConfiguration(Parameter[] params, LegalIO legalIO, bool hasMIDIInput)
{
    import std.conv: to;
    import std.string: replace;
    import std.regex: regex, replaceAll;
    import std.uni: toLower;

    auto re = regex(r"(\s+|@|&|'|\(|\)|<|>|#|:)");

    string paramString = "    lv2:port\n";
    foreach(index, param; params)
    {
        paramString ~= "    [ \n";
        paramString ~= "        a lv2:InputPort , lv2:ControlPort ;\n";
        paramString ~= "        lv2:index " ~ to!string(index) ~ " ;\n";
        paramString ~= "        lv2:symbol \"" ~ replaceAll(param.name, re, "").toLower() ~ "\" ;\n";
        paramString ~= "        lv2:name \"" ~ param.name ~ "\" ;\n";
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
    paramString ~= "        a lv2:InputPort , atom:AtomPort ;\n";
    paramString ~= "        atom:bufferType atom:Sequence ;\n";
    
    if(hasMIDIInput)
        paramString ~= "        atom:supports midi:MidiEvent ;\n";

    paramString ~= "        atom:supports time:Position ;\n";
    paramString ~= "        lv2:designation lv2:control ;\n";
    paramString ~= "        lv2:index " ~ to!string(params.length + legalIO.numInputChannels + legalIO.numOutputChannels) ~ ";\n";
    paramString ~= "        lv2:symbol \"midiinput\" ;\n";
    paramString ~= "        lv2:name \"MIDI Input\"\n";
    paramString ~= "    ]";
    paramString ~= " . \n";

    return paramString;
}

/*
    LV2 Callback funtion implementations
    note that instatiate is a template mixin. 
*/
extern(C)
{
    static void
    connect_port(LV2_Handle instance,
                uint32_t   port,
                void*      data)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.connect_port(port, data);
    }


    static void
    activate(LV2_Handle instance)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.activate();
    }

    static void
    run(LV2_Handle instance, uint32_t n_samples)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.run(n_samples);
    }

    static void
    deactivate(LV2_Handle instance)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.deactivate();
    }

    static void
    cleanup(LV2_Handle instance)
    {
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.cleanup();
        lv2client.destroyFree();
    }

    static const (void)*
    extension_data(const char* uri)
    {
        return null;
    }

    // export const (LV2UI_Descriptor)* lv2ui_descriptor(uint32_t index)
    // {
    //     switch(index) {
    //         case 0: 
    //             return &lv2UIDescriptor;
    //         default: return null;
    //     }
    // }

    LV2UI_Handle instantiateUI(const LV2UI_Descriptor* descriptor,
									const char*                     plugin_uri,
									const char*                     bundle_path,
									LV2UI_Write_Function            write_function,
									LV2UI_Controller                controller,
									LV2UI_Widget*                   widget,
									const (LV2_Feature*)*       features)
    {
        void* instance_access = cast(char*)assumeNothrowNoGC(&lv2_features_data)(features, "http://lv2plug.in/ns/ext/instance-access");
        if(instance_access)
        {
            LV2Client lv2client = cast(LV2Client)instance_access;
            lv2client.instantiateUI(descriptor, plugin_uri, bundle_path, write_function, controller, widget, features);
            return cast(LV2UI_Handle)instance_access;
        }
        else
        {
            printf("Error: Instance access is not available\n");
            return null;
        }
    }

    void write_function(LV2UI_Controller controller,
										uint32_t         port_index,
										uint32_t         buffer_size,
										uint32_t         port_protocol,
										const void*      buffer)
    {
        
    }

    void cleanupUI(LV2UI_Handle ui)
    {
        LV2Client lv2client = cast(LV2Client)ui;
        lv2client.cleanupUI();
    }

    void port_event(LV2UI_Handle ui,
						uint32_t     port_index,
						uint32_t     buffer_size,
						uint32_t     format,
						const void*  buffer)
    {
        LV2Client lv2client = cast(LV2Client)ui;
        lv2client.port_event(port_index, buffer_size, format, buffer);
    }

    const (void)* extension_dataUI(const char* uri)
    {
        return null;
    }
}