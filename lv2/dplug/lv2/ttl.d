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
import core.stdc.stdlib;
import core.stdc.string;
import std.conv;

import dplug.core.nogc;

import dplug.client.client;
import dplug.client.params;
import dplug.client.daw;


// TODO: this is bad and breaks often.
// Needs something like an output range, writing to a growable buffer so that no strange limitations exist.

int GenerateManifestFromClient_templated(alias ClientClass)(char[] outputBuffer,
                                                            const(char)[] binaryFileName) nothrow @nogc
{
    ClientClass client = mallocNew!ClientClass();
    scope(exit) client.destroyFree();

    LegalIO[] legalIOs = client.legalIOs();
    Parameter[] params = client.params();

    char[] manifest = outputBuffer;
    manifest[] = '\0';

    // Make an URI for the GUI
    char[256] uriBuf;
    sprintVendorPrefix(uriBuf.ptr, 256, client.pluginHomepage(), client.getPluginUniqueID());
    string uriVendor = stringIDup(uriBuf.ptr); // TODO leak here

    strcat(manifest.ptr, "@prefix lv2:  <http://lv2plug.in/ns/lv2core#>.\n".ptr);
    strcat(manifest.ptr, "@prefix atom: <http://lv2plug.in/ns/ext/atom#>.\n".ptr);
    strcat(manifest.ptr, "@prefix doap: <http://usefulinc.com/ns/doap#>.\n".ptr);
    strcat(manifest.ptr, "@prefix foaf: <http://xmlns.com/foaf/0.1/>.\n".ptr);
    strcat(manifest.ptr, "@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#>.\n".ptr);
    strcat(manifest.ptr, "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>.\n".ptr);
    strcat(manifest.ptr, "@prefix urid: <http://lv2plug.in/ns/ext/urid#>.\n".ptr);
    strcat(manifest.ptr, "@prefix ui:   <http://lv2plug.in/ns/extensions/ui#>.\n".ptr);
    strcat(manifest.ptr, "@prefix pset: <http://lv2plug.in/ns/ext/presets#>.\n".ptr);
    strcat(manifest.ptr, "@prefix opts: <http://lv2plug.in/ns/ext/options#>.\n".ptr);
    if (client.sendsMIDI)
    {
        strcat(manifest.ptr, "@prefix rsz:  <http://lv2plug.in/ns/ext/resize-port#>.\n".ptr);
    }
    strcat(manifest.ptr, "@prefix pprops: <http://lv2plug.in/ns/ext/port-props#>.\n".ptr);
    strcat(manifest.ptr, "@prefix vendor: ".ptr); // this prefix abbreviate the ttl with our own URL base
    strcat(manifest.ptr, escapeRDF_IRI(uriVendor).ptr);
    strcat(manifest.ptr, ".\n\n".ptr);

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

        strcat(manifest.ptr, uriIO.ptr);
        strcat(manifest.ptr, "\n".ptr);
        strcat(manifest.ptr, "    a lv2:Plugin");
        strcat(manifest.ptr, lv2PluginCategory(client.pluginCategory).ptr);
        strcat(manifest.ptr, " ;\n".ptr);
        strcat(manifest.ptr, "    lv2:binary ".ptr);
        strcat(manifest.ptr, escapeRDF_IRI(binaryFileName).ptr);
        strcat(manifest.ptr, " ;\n".ptr);
        strcat(manifest.ptr, "    doap:name ".ptr);
        strcat(manifest.ptr, escapeRDFString(client.pluginName).ptr);
        strcat(manifest.ptr, " ;\n".ptr);
        strcat(manifest.ptr, "    doap:maintainer [ foaf:name ".ptr);
        strcat(manifest.ptr, escapeRDFString(client.vendorName).ptr);
        strcat(manifest.ptr, " ] ;\n".ptr);
        strcat(manifest.ptr, "    lv2:requiredFeature opts:options ,\n".ptr);
        strcat(manifest.ptr, "                        urid:map ;\n".ptr);

        // We do not provide such an interface
        //manifest ~= "    lv2:extensionData <" ~ LV2_OPTIONS__interface ~ "> ; \n";

        if(client.hasGUI)
        {
            strcat(manifest.ptr, "    ui:ui vendor:ui;\n".ptr);
        }

        strcat(manifest.ptr, buildParamPortConfiguration(client.params(), legalIO, client.receivesMIDI, client.sendsMIDI).ptr);
    }

    // add presets information

    auto presetBank = client.presetBank();
    for(int presetIndex = 0; presetIndex < presetBank.numPresets(); ++presetIndex)
    {
        // Make an URI for this preset
        sprintPluginURI_preset_short(uriBuf.ptr, 256, presetIndex);
        auto preset = presetBank.preset(presetIndex);
        strcat(manifest.ptr, "\n".ptr);
        strcat(manifest.ptr, stringIDup(uriBuf.ptr).ptr);
        strcat(manifest.ptr, "\n".ptr); // TODO leak here
        strcat(manifest.ptr, "        a pset:Preset ;\n".ptr);
        strcat(manifest.ptr, "        rdfs:label ".ptr);
        strcat(manifest.ptr, escapeRDFString(preset.name).ptr);
        strcat(manifest.ptr, " ;\n".ptr);

        strcat(manifest.ptr, "        lv2:port [\n".ptr);     

        const(float)[] paramValues = preset.getNormalizedParamValues();

        for (int p = 0; p < paramValues.length; ++p)
        {
            char[] paramSymbol = cast(char[])malloc(char.sizeof * 256)[0..256];
            paramSymbol[0] = '\0';
            sprintf(paramSymbol.ptr, "p%d", p);
            char[] paramValue = cast(char[])malloc(char.sizeof * 10)[0..10];
            snprintf(paramValue.ptr, 10, "%f", paramValues[p]);

            strcat(manifest.ptr, "            lv2:symbol \"".ptr);
            strcat(manifest.ptr, paramSymbol.ptr);
            strcat(manifest.ptr, "\"; pset:value ".ptr);
            strcat(manifest.ptr, paramValue[0..strlen(paramValue.ptr)].ptr);
            strcat(manifest.ptr, " \n".ptr);
            if (p + 1 == paramValues.length)
                strcat(manifest.ptr, "        ] ;\n".ptr);
            else
                strcat(manifest.ptr, "        ] , [\n".ptr);
        }

        // Each preset applies to every plugin I/O configuration
        strcat(manifest.ptr, "        lv2:appliesTo ".ptr);
        foreach(size_t n, legalIO; legalIOs)
        {
            // Make an URI for this I/O configuration
            sprintPluginURI_IO_short(uriBuf.ptr, 256, legalIO);
            string uriIO = stringIDup(uriBuf.ptr); // TODO leak here
            strcat(manifest.ptr, uriIO.ptr);
            if (n + 1 == legalIOs.length)
                strcat(manifest.ptr, " . \n".ptr);
            else
                strcat(manifest.ptr, " , ".ptr);
        }
    }

    // describe UI
    if(client.hasGUI)
    {
        strcat(manifest.ptr, "\nvendor:ui\n".ptr);

        version(OSX)
            strcat(manifest.ptr, "    a ui:CocoaUI;\n".ptr);
        else version(Windows)
            strcat(manifest.ptr, "    a ui:WindowsUI;\n".ptr);
        else version(linux)
            strcat(manifest.ptr, "    a ui:X11UI;\n".ptr);
        else
            static assert("unsupported OS");

        strcat(manifest.ptr, "    lv2:optionalFeature ui:noUserResize ,\n".ptr);
        strcat(manifest.ptr, "                        ui:resize ,\n".ptr);
        strcat(manifest.ptr, "                        ui:touch ;\n".ptr);
        strcat(manifest.ptr, "    lv2:requiredFeature opts:options ,\n".ptr);
        strcat(manifest.ptr, "                        urid:map ,\n".ptr);

        // No DSP separated from UI for us
        strcat(manifest.ptr, "                        <http://lv2plug.in/ns/ext/instance-access> ;\n".ptr);

        strcat(manifest.ptr, "    ui:binary ".ptr);
        strcat(manifest.ptr, escapeRDF_IRI(binaryFileName).ptr);
        strcat(manifest.ptr, " .\n".ptr);
    }

    const int manifestFinalLength = cast(int)strlen(manifest.ptr);
    return manifestFinalLength;
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

const(char)[] lv2PluginCategory(PluginCategory category) nothrow @nogc
{
    char[] lv2Category = cast(char[])malloc(char.sizeof * 30)[0..30];
    lv2Category[] = '\0';
    strcat(lv2Category.ptr, ", lv2:");
    with(PluginCategory)
    {
        switch(category)
        {
            case effectAnalysisAndMetering:
                strcat(lv2Category.ptr, "AnalyserPlugin");
                break;
            case effectDelay:
                strcat(lv2Category.ptr, "DelayPlugin");
                break;
            case effectDistortion:
                strcat(lv2Category.ptr, "DistortionPlugin");
                break;
            case effectDynamics:
                strcat(lv2Category.ptr, "DynamicsPlugin");
                break;
            case effectEQ:
                strcat(lv2Category.ptr, "EQPlugin");
                break;
            case effectImaging:
                strcat(lv2Category.ptr, "SpatialPlugin");
                break;
            case effectModulation:
                strcat(lv2Category.ptr, "ModulatorPlugin");
                break;
            case effectPitch:
                strcat(lv2Category.ptr, "PitchPlugin");
                break;
            case effectReverb:
                strcat(lv2Category.ptr, "ReverbPlugin");
                break;
            case effectOther:
                strcat(lv2Category.ptr, "UtilityPlugin");
                break;
            case instrumentDrums:
            case instrumentSampler:
            case instrumentSynthesizer:
            case instrumentOther:
                strcat(lv2Category.ptr, "InstrumentPlugin");
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
const(char)[] escapeRDFString(const(char)[] s) nothrow @nogc
{
    // Note: over-allocate, in case the string is made up of only escaped chars
    const int len = cast(int)(s.length) * 2 + 3; 
    char[] r = (cast(char*)malloc(len))[0..len];
    r[0] = '\"';

    int index = 1;

    foreach(char ch; s)
    {
        switch(ch)
        {
           // Escape some whitespace chars
           case '\t': r[index++] = '\\'; r[index++] = 't'; break;
           case '\b': r[index++] = '\\'; r[index++] = 'b'; break;
           case '\n': r[index++] = '\\'; r[index++] = 'n'; break;
           case '\r': r[index++] = '\\'; r[index++] = 'r'; break;
           case '\f': r[index++] = '\\'; r[index++] = 'f'; break;
           case '\"': r[index++] = '\\'; r[index++] = '\"'; break;
           case '\'': r[index++] = '\\'; r[index++] = '\''; break;
           case '\\': r[index++] = '\\'; r[index++] = '\\'; break;
           default:
               r[index++] = ch;
        }
    }
    r[index++] = '\"';
    r[index++] = '\0';
    return r[0..index-1];
}
unittest
{
    assert(escapeRDFString("Stereo Link") == "\"Stereo Link\"");
}

/// Escape a UTF-8 string for UTF-8 IRI literal
/// See_also: https://www.w3.org/TR/turtle/
const(char)[] escapeRDF_IRI(const(char)[] s) nothrow @nogc
{
    const int len = cast(int)(s.length) + 3;
    char[] escapedRDF_IRI = (cast(char*)malloc(char.sizeof * len))[0..len];
    // We actually remove all special characters, because it seems not all hosts properly decode escape sequences
    escapedRDF_IRI[0] = '<';
    int index = 1;
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
                escapedRDF_IRI[index++] = ch;
        }
    }
    escapedRDF_IRI[index++] = '>';
    escapedRDF_IRI[index++] = '\0';
    return escapedRDF_IRI[0..index];
}

const(char)[] buildParamPortConfiguration(Parameter[] params, LegalIO legalIO, bool hasMIDIInput, bool hasMIDIOutput) nothrow @nogc
{
    import std.conv: to;
    import std.uni: toLower;

    int portIndex = 0;

    const paramStringLen = 10_000;
    char[] paramString = cast(char[])malloc(char.sizeof * paramStringLen)[0..paramStringLen];
    paramString[0] = '\0';

    // Note: parameters symbols should be consistent across versions
    // Can't change them without issuing a major version change.
    // We choose to have symbol "p<n>" for parameter n (Dplug assume we can append parameters in minor versions)
    // We choose to have symbol "input_<n>" for input channel n
    // We choose to have symbol "output_<n>" for output channel n

    {
        char[256] indexString;
        char[256] paramSymbol;

        strcat(paramString.ptr, "    lv2:port\n".ptr);
        foreach(paramIndex, param; params)
        {
            sprintf(indexString.ptr, "%d", portIndex);
            sprintf(paramSymbol.ptr, "p%d", cast(int)paramIndex);
            strcat(paramString.ptr, "    [\n".ptr);
            strcat(paramString.ptr, "        a lv2:InputPort , lv2:ControlPort ;\n".ptr);
            strcat(paramString.ptr, "        lv2:index ".ptr);
            strcat(paramString.ptr, indexString.ptr);
            strcat(paramString.ptr, " ;\n".ptr);
            strcat(paramString.ptr, "        lv2:symbol \"".ptr);
            strcat(paramString.ptr, paramSymbol.ptr);
            strcat(paramString.ptr, "\" ;\n".ptr);
            strcat(paramString.ptr, "        lv2:name ".ptr);
            strcat(paramString.ptr, escapeRDFString(param.name).ptr);
            strcat(paramString.ptr, " ;\n".ptr);
            strcat(paramString.ptr, "        lv2:default ".ptr);

            char[] paramNormalized = cast(char[])malloc(char.sizeof * 10)[0..10];
            snprintf(paramNormalized.ptr, 10, "%f", param.getNormalized());

            strcat(paramString.ptr, paramNormalized.ptr);
            strcat(paramString.ptr, " ;\n".ptr);
            strcat(paramString.ptr, "        lv2:minimum 0.0 ;\n".ptr);
            strcat(paramString.ptr, "        lv2:maximum 1.0 ;\n".ptr);
            if (!param.isAutomatable) {
                strcat(paramString.ptr, "        lv2:portProperty <http://kxstudio.sf.net/ns/lv2ext/props#NonAutomable> ;\n".ptr);
            }
            strcat(paramString.ptr, "    ] ,\n".ptr);
            ++portIndex;
        }
    }

    {
        char[256] indexString;
        char[256] inputString;
        foreach(input; 0..legalIO.numInputChannels)
        {
            sprintf(indexString.ptr, "%d", portIndex);
        
            static if (false)
                sprintf(inputString.ptr, "%d", input);
            else
            {
                // kept for backward compatibility; however this breaks if the
                // number of parameters change in the future.
                sprintf(inputString.ptr, "%d", cast(int)(input + params.length));
            }

            strcat(paramString.ptr, "    [\n".ptr);
            strcat(paramString.ptr, "        a lv2:AudioPort , lv2:InputPort ;\n".ptr);
            strcat(paramString.ptr, "        lv2:index ".ptr);
            strcat(paramString.ptr, indexString.ptr);
            strcat(paramString.ptr, ";\n".ptr);
            strcat(paramString.ptr, "        lv2:symbol \"input_".ptr);
            strcat(paramString.ptr, inputString.ptr);
            strcat(paramString.ptr, "\" ;\n".ptr);
            strcat(paramString.ptr, "        lv2:name \"Input".ptr);
            strcat(paramString.ptr, inputString.ptr);
            strcat(paramString.ptr, "\" ;\n".ptr);
            strcat(paramString.ptr, "    ] ,\n".ptr);
            ++portIndex;
        }
    }

    {
        char[256] indexString;
        char[256] outputString;
        foreach(output; 0..legalIO.numOutputChannels)
        {
            sprintf(indexString.ptr, "%d", portIndex);
            sprintf(outputString.ptr, "%d", output);

            strcat(paramString.ptr, "    [\n".ptr);
            strcat(paramString.ptr, "        a lv2:AudioPort , lv2:OutputPort ;\n".ptr);
            strcat(paramString.ptr, "        lv2:index ".ptr);
            strcat(paramString.ptr, indexString.ptr);
            strcat(paramString.ptr, ";\n".ptr);
            strcat(paramString.ptr, "        lv2:symbol \"output_".ptr);
            strcat(paramString.ptr, outputString.ptr);
            strcat(paramString.ptr, "\" ;\n".ptr);
            strcat(paramString.ptr, "        lv2:name \"Output".ptr);
            strcat(paramString.ptr, outputString.ptr);
            strcat(paramString.ptr, "\" ;\n".ptr);
            strcat(paramString.ptr, "    ] ,\n".ptr);
            if(output == legalIO.numOutputChannels - 1)
            {
                ++portIndex;
                sprintf(indexString.ptr, "%d", portIndex);
                strcat(paramString.ptr, "    [\n".ptr);
                strcat(paramString.ptr, "        a lv2:ControlPort , lv2:OutputPort ;\n".ptr);
                strcat(paramString.ptr, "        lv2:index ".ptr);
                strcat(paramString.ptr, indexString.ptr);
                strcat(paramString.ptr, ";\n".ptr);
                strcat(paramString.ptr, "        lv2:designation lv2:latency ;\n".ptr);
                strcat(paramString.ptr, "        lv2:symbol \"latency\" ;\n".ptr);
                strcat(paramString.ptr, "        lv2:name \"Latency\" ;\n".ptr);
                strcat(paramString.ptr, "        lv2:portProperty lv2:reportsLatency, lv2:connectionOptional, pprops:notOnGUI ;\n".ptr);
                strcat(paramString.ptr, "    ] ,\n".ptr);
            }
            ++portIndex;
        }
    }

    strcat(paramString.ptr, "    [\n".ptr);
    strcat(paramString.ptr, "        a lv2:InputPort, atom:AtomPort ;\n".ptr);
    strcat(paramString.ptr, "        atom:bufferType atom:Sequence ;\n".ptr);
    strcat(paramString.ptr, "        lv2:portProperty lv2:connectionOptional ;\n".ptr);

    if(hasMIDIInput)
        strcat(paramString.ptr, "        atom:supports <http://lv2plug.in/ns/ext/midi#MidiEvent> ;\n".ptr);

    char[16] indexBuf;
    snprintf(indexBuf.ptr, 16, "%d", portIndex);

    strcat(paramString.ptr, "        atom:supports <http://lv2plug.in/ns/ext/time#Position> ;\n".ptr);
    strcat(paramString.ptr, "        lv2:designation lv2:control ;\n".ptr);
    strcat(paramString.ptr, "        lv2:index ".ptr);
    strcat(paramString.ptr, indexBuf.ptr);
    strcat(paramString.ptr, ";\n".ptr);
    strcat(paramString.ptr, "        lv2:symbol \"lv2_events_in\" ;\n".ptr);
    strcat(paramString.ptr, "        lv2:name \"Events Input\"\n".ptr);
    strcat(paramString.ptr, "    ]".ptr);
    ++portIndex;

    if (hasMIDIOutput)
    {
        strcat(paramString.ptr, " ,\n    [\n".ptr);
        strcat(paramString.ptr, "        a lv2:OutputPort, atom:AtomPort ;\n".ptr);
        strcat(paramString.ptr, "        atom:bufferType atom:Sequence ;\n".ptr);
        strcat(paramString.ptr, "        lv2:portProperty lv2:connectionOptional ;\n".ptr);
        strcat(paramString.ptr, "        atom:supports <http://lv2plug.in/ns/ext/midi#MidiEvent> ;\n".ptr);
        strcat(paramString.ptr, "        lv2:designation lv2:control ;\n".ptr);
        snprintf(indexBuf.ptr, 16, "%d", portIndex);
        strcat(paramString.ptr, "        lv2:index ".ptr);
        strcat(paramString.ptr, indexBuf.ptr);
        strcat(paramString.ptr, ";\n".ptr);
        strcat(paramString.ptr, "        lv2:symbol \"lv2_events_out\" ;\n".ptr);
        strcat(paramString.ptr, "        lv2:name \"Events Output\" ;\n".ptr);
        strcat(paramString.ptr, "        rsz:minimumSize 2048 ;\n".ptr);
        strcat(paramString.ptr, "    ]".ptr);
    }
    ++portIndex;

    strcat(paramString.ptr, " .\n".ptr);

    return paramString;
}
