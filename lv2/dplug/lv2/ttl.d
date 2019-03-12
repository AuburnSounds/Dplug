/**
* LV2 Client implementation
*
* Copyright: Ethan Reker 2018-2019.
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

/// TTL generation.
module dplug.lv2.ttl;

import core.stdc.stdio;
import std.conv;

import dplug.core.nogc;

import dplug.client.client;
import dplug.client.params;
import dplug.client.daw;


extern(C) alias generateManifestFromClientCallback = void function(const(ubyte)* fileContents, size_t len, const(char)[] buildDir);

void GenerateManifestFromClient_templated(alias ClientClass)(generateManifestFromClientCallback callback,
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

    // Make an URI for the GUI
    char[256] uriBuf;
    sprintVendorPrefix(uriBuf.ptr, 256, client.pluginHomepage(), client.getPluginUniqueID());
    string uriVendor = stringIDup(uriBuf.ptr); // TODO leak here

    manifest ~= "@prefix lv2:  <http://lv2plug.in/ns/lv2core#>.\n";
    manifest ~= "@prefix atom: <http://lv2plug.in/ns/ext/atom#>.\n";
    manifest ~= "@prefix doap: <http://usefulinc.com/ns/doap#>.\n";
    manifest ~= "@prefix foaf: <http://xmlns.com/foaf/0.1/>.\n";
    manifest ~= "@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#>.\n";
    manifest ~= "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>.\n";
    manifest ~= "@prefix urid: <http://lv2plug.in/ns/ext/urid#>.\n";
    manifest ~= "@prefix ui:   <http://lv2plug.in/ns/extensions/ui#>.\n";
    manifest ~= "@prefix pset: <http://lv2plug.in/ns/ext/presets#>.\n";
    manifest ~= "@prefix opts: <http://lv2plug.in/ns/ext/options#>.\n";
    manifest ~= "@prefix vendor: " ~ escapeRDF_IRI(uriVendor) ~ ".\n\n"; // this prefix abbreviate the ttl with our own URL base

    

    string uriGUI = null;
    if(client.hasGUI)
    {
        sprintPluginURI_UI(uriBuf.ptr, 256, client.pluginHomepage(), client.getPluginUniqueID());
        uriGUI = stringIDup(uriBuf.ptr); // TODO leak here
    }

    foreach(legalIO; legalIOs)
    {
        // Make an URI for this I/O configuration
        sprintPluginURI_IO_short(uriBuf.ptr, 256, legalIO);
        string uriIO = stringIDup(uriBuf.ptr); // TODO leak here

        manifest ~= uriIO ~ "\n";
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
            manifest ~= "    ui:ui vendor:ui;\n";
        }

        manifest ~= buildParamPortConfiguration(client.params(), legalIO, client.receivesMIDI);
    }

    // add presets information

    auto presetBank = client.presetBank();
    for(int presetIndex = 0; presetIndex < presetBank.numPresets(); ++presetIndex)
    {
        // Make an URI for this preset
        sprintPluginURI_preset_short(uriBuf.ptr, 256, presetIndex);
        auto preset = presetBank.preset(presetIndex);
        manifest ~= "\n" ~ stringIDup(uriBuf.ptr) ~ "\n"; // TODO leak here
        manifest ~= "        a pset:Preset ;\n";
        manifest ~= "        rdfs:label " ~ escapeRDFString(preset.name) ~ " ;\n";

        manifest ~= "        lv2:port [\n";     

        const(float)[] paramValues = preset.getNormalizedParamValues();

        for (int p = 0; p < paramValues.length; ++p)
        {
            string paramSymbol = "p" ~ to!string(p);
            manifest ~= "            lv2:symbol " ~ paramSymbol ~ " ;\n";
            manifest ~= "            pset:value " ~ to!string(paramValues[p]) ~ " \n";
            if (p + 1 == paramValues.length)
                manifest ~= "        ] .\n";
            else
                manifest ~= "        ] , [\n";
        }

        // Each preset applies to every plugin I/O configuration
        manifest ~= "        lv2:appliesTo ";
        foreach(size_t n, legalIO; legalIOs)
        {
            // Make an URI for this I/O configuration
            sprintPluginURI_IO_short(uriBuf.ptr, 256, legalIO);
            string uriIO = stringIDup(uriBuf.ptr); // TODO leak here
            manifest ~= uriIO;
            if (n + 1 == legalIOs.length)
                manifest ~= " . \n";
            else
                manifest ~= " , ";
        }
    }

    // describe UI
    if(client.hasGUI)
    {
        manifest ~= "\nvendor:ui\n";

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

        // No DSP separated from UI for us
        manifest ~= "                        <http://lv2plug.in/ns/ext/instance-access> ;\n";

        manifest ~= "    ui:binary "  ~ escapeRDF_IRI(binaryFileName) ~ " .\n";
    }

    callback(cast(const(ubyte)*)manifest, manifest.length, buildDir);
}

package:

void sprintVendorPrefix(char* buf, size_t maxChars, string pluginHomepage, char[4] pluginID) nothrow @nogc
{
    CString pluginHomepageZ = CString(pluginHomepage);
    snprintf(buf, maxChars, "%s%2X%2X%2X%2X#", pluginHomepageZ.storage, pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
}

void sprintPluginURI(char* buf, size_t maxChars, string pluginHomepage, char[4] pluginID) nothrow @nogc
{
    CString pluginHomepageZ = CString(pluginHomepage);
    snprintf(buf, maxChars, "%s%2X%2X%2X%2X", pluginHomepageZ.storage, pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
}
/*
void sprintPluginURI(char* buf, size_t maxChars, string pluginHomepage, char[4] pluginID) nothrow @nogc
{
    CString pluginHomepageZ = CString(pluginHomepage);
    snprintf(buf, maxChars, "%s%2X%2X%2X%2X", pluginHomepageZ.storage, pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
}*/

void sprintPluginURI_UI(char* buf, size_t maxChars, string pluginHomepage, char[4] pluginID) nothrow @nogc
{
    CString pluginHomepageZ = CString(pluginHomepage);
    snprintf(buf, maxChars, "%s%2X%2X%2X%2X#ui", pluginHomepageZ.storage, pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
}

void sprintPluginURI_preset_short(char* buf, size_t maxChars, int presetIndex) nothrow @nogc
{
    snprintf(buf, maxChars, "vendor:preset%d", presetIndex);
}

void sprintPluginURI_IO_short(char* buf, size_t maxChars, LegalIO io) nothrow @nogc
{
    int ins = io.numInputChannels;
    int outs = io.numOutputChannels;

    // give user-friendly names
    if (ins == 1 && outs == 1)
    {
        snprintf(buf, maxChars, "vendor:mono");
    }
    else if (ins == 2 && outs == 2)
    {
        snprintf(buf, maxChars, "vendor:stereo");
    }
    else
    {
        snprintf(buf, maxChars, "vendor:in%dout%d", ins, outs);
    }
}

void sprintPluginURI_IO(char* buf, size_t maxChars, string pluginHomepage, char[4] pluginID, LegalIO io) nothrow @nogc
{
    CString pluginHomepageZ = CString(pluginHomepage);
    int ins = io.numInputChannels;
    int outs = io.numOutputChannels;

    // give user-friendly names
    if (ins == 1 && outs == 1)
    {
        snprintf(buf, maxChars, "%s%2X%2X%2X%2X#mono", pluginHomepageZ.storage,
                 pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
    }
    else if (ins == 2 && outs == 2)
    {
        snprintf(buf, maxChars, "%s%2X%2X%2X%2X#stereo", pluginHomepageZ.storage,
                 pluginID[0], pluginID[1], pluginID[2], pluginID[3]);
    }
    else
    {
        snprintf(buf, maxChars, "%s%2X%2X%2X%2X#in%dout%d", pluginHomepageZ.storage,
                                                            pluginID[0], pluginID[1], pluginID[2], pluginID[3],
                                                            ins, outs);
    }
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
string escapeRDFString(const(char)[] s)
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

    // Note: parameters symbols should be consistent across versions
    // Can't change them without issuing a major version change.
    // We choose to have symbol "p<n>" for parameter n (Dplug assume we can append parameters in minor versions)
    // We choose to have symbol "input_<n>" for input channel n
    // We choose to have symbol "output_<n>" for output channel n

    string paramString = "    lv2:port\n";
    foreach(index, param; params)
    {
        string paramSymbol = "p" ~ to!string(index);
        paramString ~= "    [ \n";
        paramString ~= "        a lv2:InputPort , lv2:ControlPort ;\n";
        paramString ~= "        lv2:index " ~ to!string(index) ~ " ;\n";
        paramString ~= "        lv2:symbol \"p" ~ to!string(index) ~ "\" ;\n";
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
        paramString ~= "        lv2:symbol \"input_" ~ to!string(input) ~ "\" ;\n";
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
        paramString ~= "        lv2:symbol \"output_" ~ to!string(output) ~ "\" ;\n";
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
