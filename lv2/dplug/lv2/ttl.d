/**
* LV2 Client implementation
*
* Copyright: Ethan Reker 2018-2019.
*            Guillaume Piolat 2019-2022.
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

version(LV2):


import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import std.conv;

import dplug.core.nogc;
import dplug.core.vec;
import dplug.core.string;

import dplug.client.client;
import dplug.client.params;
import dplug.client.daw;

/// Generate a manifest. Used by dplug-build, for LV2 builds.
/// - to ask needed size in bytes, pass null as outputBuffer
/// - else, pass as much bytes or more than necessary. Result manifest in outputBuffer[0..returned-value]
/// outputBuffer can be null, in which case it makes no copy.
int GenerateManifestFromClient_templated(alias ClientClass)(char[] outputBuffer,
                                                            const(char)[] binaryFileName) nothrow @nogc
{
    // Create a temporary client just to know its properties.
    ClientClass client = mallocNew!ClientClass();
    scope(exit) client.destroyFree();    

    LegalIO[] legalIOs = client.legalIOs();
    Parameter[] params = client.params();

    String manifest;

    // Make an URI for the GUI
    char[256] uriBuf; // this one variable reused quite a lot
    sprintVendorPrefix(uriBuf.ptr, 256, client.pluginHomepage(), client.getPluginUniqueID());
    
    String strUriVendor;
    {
        const(char)[] uriVendor = uriBuf[0..strlen(uriBuf.ptr)];
        escapeRDF_IRI2(uriVendor, strUriVendor);
    }

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
    version(futureBinState)
    {
        manifest ~= "@prefix owl: <http://www.w3.org/2002/07/owl#> .\n";
        manifest ~= "@prefix state: <http://lv2plug.in/ns/ext/state#>.\n";
        manifest ~= "@prefix xsd:   <http://www.w3.org/2001/XMLSchema#> .\n";
    }

    if (client.sendsMIDI)
    {
        manifest ~= "@prefix rsz:  <http://lv2plug.in/ns/ext/resize-port#>.\n";
    }
    manifest ~= "@prefix pprops: <http://lv2plug.in/ns/ext/port-props#>.\n";
    manifest ~= "@prefix vendor: "; // this prefix abbreviate the ttl with our own URL base
    manifest ~= strUriVendor;
    manifest ~= ".\n\n";

    String strCategory;
    lv2PluginCategory(client.pluginCategory, strCategory);

    String strBinaryFile;
    escapeRDF_IRI2(binaryFileName, strBinaryFile);

    String strPluginName;
    escapeRDFString(client.pluginName, strPluginName);

    String strVendorName;
    escapeRDFString(client.vendorName, strVendorName);

    String paramString;

    version(futureBinState)
    {

    manifest ~=
`
vendor:stateBinary
    a owl:DatatypeProperty ;
    rdfs:label "Dplug plugin state as base64-encoded string" ;
    rdfs:domain state:State ;
    rdfs:range xsd:string .

`;

    }

    foreach(legalIO; legalIOs)
    {
        // Make an URI for this I/O configuration
        sprintPluginURI_IO_short(uriBuf.ptr, 256, legalIO);

        manifest.appendZeroTerminatedString(uriBuf.ptr);
        manifest ~= "\n";
        manifest ~= "    a lv2:Plugin";
        manifest ~= strCategory;
        manifest ~= " ;\n";
        manifest ~= "    lv2:binary ";
        manifest ~= strBinaryFile;
        manifest ~= " ;\n";
        manifest ~= "    doap:name ";
        manifest ~= strPluginName;
        manifest ~= " ;\n";
        manifest ~= "    doap:maintainer [ foaf:name ";
        manifest ~= strVendorName;
        manifest ~= " ] ;\n";
        manifest ~= "    lv2:requiredFeature opts:options ,\n";
    /*    version(futureBinState)
        {
            manifest ~= "    state:loadDefaultState ,\n";
        } */
        manifest ~= "                        urid:map ;\n";

        // We do not provide such an interface
        //manifest ~= "    lv2:extensionData <" ~ LV2_OPTIONS__interface ~ "> ; \n";

        version(futureBinState)
        {
            manifest ~= "    lv2:extensionData <http://lv2plug.in/ns/ext/state#interface> ;\n";
        }

        if(client.hasGUI)
        {
            manifest ~= "    ui:ui vendor:ui;\n";
        }

        buildParamPortConfiguration(client.params(), legalIO, client.receivesMIDI, client.sendsMIDI, paramString);
        manifest ~= paramString;
    }

    // add presets information

    auto presetBank = client.presetBank();
    String strPresetName;

    for(int presetIndex = 0; presetIndex < presetBank.numPresets(); ++presetIndex)
    {
        // Make an URI for this preset
        sprintPluginURI_preset_short(uriBuf.ptr, 256, presetIndex);
        auto preset = presetBank.preset(presetIndex);
        manifest ~= "\n";
        manifest.appendZeroTerminatedString(uriBuf.ptr);
        manifest ~= "\n"; 
        manifest ~= "        a pset:Preset ;\n";
        manifest ~= "        rdfs:label ";
        escapeRDFString(preset.name, strPresetName);
        manifest ~= strPresetName;
        manifest ~= " ;\n";


        version(futureBinState)
        {
            manifest ~= "        state:state [\n";
            manifest ~= "            vendor:stateBinary \"\"\"this is test\"\"\"^^xsd:base64Binary ;\n";
            manifest ~= "        ] ;\n";
        }

        manifest ~= "        lv2:port [\n";

        const(float)[] paramValues = preset.getNormalizedParamValues();

        char[32] paramSymbol;
        char[32] paramValue;

        for (int p = 0; p < paramValues.length; ++p)
        {
            snprintf(paramSymbol.ptr, 32, "p%d", p);
            snprintf(paramValue.ptr, 32, "%g", paramValues[p]);

            manifest ~= "            lv2:symbol \"";
            manifest.appendZeroTerminatedString( paramSymbol.ptr );
            manifest ~= "\"; pset:value ";
            manifest.appendZeroTerminatedString( paramValue.ptr );
            manifest ~= " \n";
            if (p + 1 == paramValues.length)
                manifest ~= "        ] ;\n";
            else
                manifest ~= "        ] , [\n";
        }

        // Each preset applies to every plugin I/O configuration
        manifest ~= "        lv2:appliesTo ";
        foreach(size_t n, legalIO; legalIOs)
        {
            // Make an URI for this I/O configuration
            sprintPluginURI_IO_short(uriBuf.ptr, 256, legalIO);
            manifest.appendZeroTerminatedString(uriBuf.ptr);
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

        manifest ~= "    ui:binary ";
        manifest ~= strBinaryFile;
        manifest ~= " .\n";
    }

    assert(manifest.length < int.max); // now that would be a very big .ttl

    const int manifestFinalLength = cast(int) manifest.length;

    if (outputBuffer !is null)
    {
        outputBuffer[0..manifestFinalLength] = manifest[0..manifestFinalLength];
    }

    return manifestFinalLength; // Always return manifest length, but you can pass null to get the needed size.
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

void lv2PluginCategory(PluginCategory category, ref String lv2Category) nothrow @nogc
{
    lv2Category.makeEmpty();
    lv2Category ~= ", lv2:";
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
                lv2Category.makeEmpty();
        }
    }
}

/// escape a UTF-8 string for UTF-8 RDF
/// See_also: https://www.w3.org/TR/turtle/
void escapeRDFString(const(char)[] s, ref String r) nothrow @nogc
{   
    r = '\"';

    int index = 1;

    foreach(char ch; s)
    {
        switch(ch)
        {
           // Escape some whitespace chars
           case '\t': r ~= '\\'; r ~= 't'; break;
           case '\b': r ~= '\\'; r ~= 'b'; break;
           case '\n': r ~= '\\'; r ~= 'n'; break;
           case '\r': r ~= '\\'; r ~= 'r'; break;
           case '\f': r ~= '\\'; r ~= 'f'; break;
           case '\"': r ~= '\\'; r ~= '\"'; break;
           case '\'': r ~= '\\'; r ~= '\''; break;
           case '\\': r ~= '\\'; r ~= '\\'; break;
           default:
               r ~= ch;
        }
    }
    r ~= '\"';
}
unittest
{
    String r;
    escapeRDFString("Stereo Link", r);
    assert(r == "\"Stereo Link\"");
}

/// Escape a UTF-8 string for UTF-8 IRI literal
/// See_also: https://www.w3.org/TR/turtle/
void escapeRDF_IRI2(const(char)[] s, ref String outString) nothrow @nogc
{
    outString.makeEmpty();
    outString ~= '<';

    // We actually remove all special characters, because it seems not all hosts properly decode escape sequences
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
                outString ~= ch;
        }
    }
    outString ~= '>';
}

void buildParamPortConfiguration(Parameter[] params, 
                                 LegalIO legalIO, 
                                 bool hasMIDIInput, 
                                 bool hasMIDIOutput,
                                 ref String paramString) nothrow @nogc
{
    int portIndex = 0;

    paramString = "";

    // Note: parameters symbols should be consistent across versions
    // Can't change them without issuing a major version change.
    // We choose to have symbol "p<n>" for parameter n (Dplug assume we can append parameters in minor versions)
    // We choose to have symbol "input_<n>" for input channel n
    // We choose to have symbol "output_<n>" for output channel n

    {
        char[256] indexString;
        char[256] paramSymbol;

        String strParamName;

        paramString ~= "    lv2:port\n";
        foreach(paramIndex, param; params)
        {
            sprintf(indexString.ptr, "%d", portIndex);
            sprintf(paramSymbol.ptr, "p%d", cast(int)paramIndex);
            paramString ~= "    [\n";
            paramString ~= "        a lv2:InputPort , lv2:ControlPort ;\n";
            paramString ~= "        lv2:index ";
            paramString.appendZeroTerminatedString(indexString.ptr);
            paramString ~= " ;\n";
            paramString ~= "        lv2:symbol \"";
            paramString.appendZeroTerminatedString(paramSymbol.ptr);
            paramString ~= "\" ;\n";

            paramString ~= "        lv2:name ";
            escapeRDFString(param.name, strParamName);
            paramString ~= strParamName;

            paramString ~= " ;\n";
            paramString ~= "        lv2:default ";

            char[10] paramNormalized;
            snprintf(paramNormalized.ptr, 10, "%g", param.getNormalized());

            paramString.appendZeroTerminatedString(paramNormalized.ptr);

            paramString ~= " ;\n";
            paramString ~= "        lv2:minimum 0.0 ;\n";
            paramString ~= "        lv2:maximum 1.0 ;\n";
            if (!param.isAutomatable) {
                paramString ~= "        lv2:portProperty <http://kxstudio.sf.net/ns/lv2ext/props#NonAutomable> ;\n";
            }
            paramString ~= "    ] ,\n";
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

            paramString ~= "    [\n";
            paramString ~= "        a lv2:AudioPort , lv2:InputPort ;\n";
            paramString ~= "        lv2:index ";
            paramString.appendZeroTerminatedString(indexString.ptr);
            paramString ~= ";\n";
            paramString ~= "        lv2:symbol \"input_";
            paramString.appendZeroTerminatedString(inputString.ptr);
            paramString ~= "\" ;\n";
            paramString ~= "        lv2:name \"Input";
            paramString.appendZeroTerminatedString(inputString.ptr);
            paramString ~= "\" ;\n";
            paramString ~= "    ] ,\n";
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

            paramString ~= "    [\n";
            paramString ~= "        a lv2:AudioPort , lv2:OutputPort ;\n";
            paramString ~= "        lv2:index ";
            paramString.appendZeroTerminatedString(indexString.ptr);
            paramString ~= ";\n";
            paramString ~= "        lv2:symbol \"output_";
            paramString.appendZeroTerminatedString(outputString.ptr);
            paramString ~= "\" ;\n";
            paramString ~= "        lv2:name \"Output";
            paramString.appendZeroTerminatedString(outputString.ptr);
            paramString ~= "\" ;\n";
            paramString ~= "    ] ,\n";

            if(output == legalIO.numOutputChannels - 1)
            {
                ++portIndex;
                sprintf(indexString.ptr, "%d", portIndex);
                paramString ~= "    [\n";
                paramString ~= "        a lv2:ControlPort , lv2:OutputPort ;\n";
                paramString ~= "        lv2:index ";
                paramString.appendZeroTerminatedString(indexString.ptr);
                paramString ~= ";\n";
                paramString ~= "        lv2:designation lv2:latency ;\n";
                paramString ~= "        lv2:symbol \"latency\" ;\n";
                paramString ~= "        lv2:name \"Latency\" ;\n";
                paramString ~= "        lv2:portProperty lv2:reportsLatency, lv2:connectionOptional, pprops:notOnGUI ;\n";
                paramString ~= "    ] ,\n";
            }
            ++portIndex;
        }
    }

    paramString ~= "    [\n";
    paramString ~= "        a lv2:InputPort, atom:AtomPort ;\n";
    paramString ~= "        atom:bufferType atom:Sequence ;\n";
    paramString ~= "        lv2:portProperty lv2:connectionOptional ;\n";

    if(hasMIDIInput)
        paramString ~= "        atom:supports <http://lv2plug.in/ns/ext/midi#MidiEvent> ;\n";

    char[16] indexBuf;
    snprintf(indexBuf.ptr, 16, "%d", portIndex);

    paramString ~= "        atom:supports <http://lv2plug.in/ns/ext/time#Position> ;\n";
    paramString ~= "        lv2:designation lv2:control ;\n";
    paramString ~= "        lv2:index ";
    paramString.appendZeroTerminatedString(indexBuf.ptr);
    paramString ~= ";\n";
    paramString ~= "        lv2:symbol \"lv2_events_in\" ;\n";
    paramString ~= "        lv2:name \"Events Input\"\n";
    paramString ~= "    ]";
    ++portIndex;

    if (hasMIDIOutput)
    {
        paramString ~= " ,\n    [\n";
        paramString ~= "        a lv2:OutputPort, atom:AtomPort ;\n";
        paramString ~= "        atom:bufferType atom:Sequence ;\n";
        paramString ~= "        lv2:portProperty lv2:connectionOptional ;\n";
        paramString ~= "        atom:supports <http://lv2plug.in/ns/ext/midi#MidiEvent> ;\n";
        paramString ~= "        lv2:designation lv2:control ;\n";
        snprintf(indexBuf.ptr, 16, "%d", portIndex);
        paramString ~= "        lv2:index ";
        paramString.appendZeroTerminatedString(indexBuf.ptr);
        paramString ~= ";\n";
        paramString ~= "        lv2:symbol \"lv2_events_out\" ;\n";
        paramString ~= "        lv2:name \"Events Output\" ;\n";
        paramString ~= "        rsz:minimumSize 2048 ;\n";
        paramString ~= "    ]";
    }
    ++portIndex;

    paramString ~= " .\n";
}
