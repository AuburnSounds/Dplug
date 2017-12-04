/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 - 2017 Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
/**
    DAW identification.
*/
module dplug.client.daw;

import core.stdc.string;

import std.string;
import std.conv;
import std.utf;

nothrow:
@nogc:


///
/// Plug-in categories.
/// For each plug-in format, a format-specific category is obtained from this.
///
/// Important: a `PluginCategory`doesn't affect I/O or MIDI, it's only a
///            hint for the goal of categorizing a plug-in in lists.
///
/// You should use such a category enclosed with quotes in plugin.json, eg:
///
/// Example:
///
///     {
///         "category": "effectAnalysisAndMetering"
///     }
///
enum PluginCategory
{
    // ### Effects

    /// FFT analyzers, phase display, waveform display, meters...
    effectAnalysisAndMetering,

        /// Any kind of delay, but not chorus/flanger types.
        effectDelay,

        /// Any kind of distortion: amp simulations, octavers, wave-shapers, 
        /// clippers, tape simulations...
        effectDistortion,

        /// Compressors, limiters, gates, transient designers...
        effectDynamics,

        /// Any kind of equalization.
        effectEQ,

        /// Stereoizers, panners, stereo manipulation, spatial modeling...
        effectImaging,

        /// Chorus, flanger, any kind of modulation effect...
        effectModulation,

        /// Any kind of pitch processing: shifters, pitch correction, 
        /// vocoder, formant shifting...
        effectPitch,

        /// Any kind of reverb: algorithmic, early reflections, convolution...
        effectReverb,

        /// Effects that don't fit in any other category.
        /// eg: Dither, noise reduction...
        effectOther,


        // ### Instruments

        /// Source that generates sound primarily from drum samples/drum synthesis.
        instrumentDrums,

        /// Source that generates sound primarily from samples, romplers...
        instrumentSampler,

        /// Source that generates sound primarily from synthesis.
        instrumentSynthesizer,

        /// Generates sound, but doesn't fit in any other category.
        instrumentOther,

        // Should never be used, except for parsing.
        invalid = -1,
}

/// From a string, return the PluginCategory enumeration.
/// Should be reasonably fast since it will be called at compile-time.
/// Returns: `PluginCategory.invalid` if parsing failed.
PluginCategory parsePluginCategory(const(char)[] input)
{
    if (input.length >= 6 && input[0..6] == "effect")
    {
        input = input[6..$];
        if (input == "AnalysisAndMetering") return PluginCategory.effectAnalysisAndMetering;
        if (input == "Delay") return PluginCategory.effectDelay;
        if (input == "Distortion") return PluginCategory.effectDistortion;
        if (input == "Dynamics") return PluginCategory.effectDynamics;
        if (input == "EQ") return PluginCategory.effectEQ;
        if (input == "Imaging") return PluginCategory.effectImaging;
        if (input == "Modulation") return PluginCategory.effectModulation;
        if (input == "Pitch") return PluginCategory.effectPitch;
        if (input == "Reverb") return PluginCategory.effectReverb;
        if (input == "Other") return PluginCategory.effectOther;
    }
    else if (input.length >= 10 && input[0..10] == "instrument")
    {
        input = input[10..$];
        if (input == "Drums") return PluginCategory.instrumentDrums;
        if (input == "Sampler") return PluginCategory.instrumentSampler;
        if (input == "Synthesizer") return PluginCategory.instrumentSynthesizer;
        if (input == "Other") return PluginCategory.instrumentOther;
    }
    return PluginCategory.invalid;
}

unittest
{
    assert(parsePluginCategory("effectDelay") == PluginCategory.effectDelay);
    assert(parsePluginCategory("instrumentSynthesizer") == PluginCategory.instrumentSynthesizer);

    assert(parsePluginCategory("does-not-exist") == PluginCategory.invalid);
    assert(parsePluginCategory("effect") == PluginCategory.invalid);
}


enum DAW
{
    Unknown,
    Reaper,
    ProTools,
    Cubase,
    Nuendo,
    Sonar,
    Vegas,
    FLStudio,
    Samplitude,
    AbletonLive,
    Tracktion,
    NTracks,
    MelodyneStudio,
    VSTScanner,
    AULab,
    Forte,
    Chainer,
    Audition,
    Orion,
    Bias,
    SAWStudio,
    Logic,
    GarageBand,
    DigitalPerformer,
    Standalone,
    AudioMulch,
    StudioOne,
    VST3TestHost,
    Ardour
    // These hosts don't report the host name:
    // EnergyXT2
    // MiniHost
}

private bool hasSubstring(const(char*) s, const(char*) sub) pure nothrow @nogc
{
    return strstr(s, sub) != null;
}

DAW identifyDAW(const(char*) s) pure nothrow @nogc
{
    // Warning: this relies on zero terminated string literals
    if (hasSubstring(s, "reaper")) return DAW.Reaper;
    if (hasSubstring(s, "cubase")) return DAW.Cubase;
    if (hasSubstring(s, "reaper")) return DAW.Reaper;
    if (hasSubstring(s, "nuendo")) return DAW.Nuendo;
    if (hasSubstring(s, "cakewalk")) return DAW.Sonar;
    if (hasSubstring(s, "samplitude")) return DAW.Samplitude;
    if (hasSubstring(s, "fruity")) return DAW.FLStudio;
    if (hasSubstring(s, "live")) return DAW.AbletonLive;
    if (hasSubstring(s, "melodyne")) return DAW.MelodyneStudio;
    if (hasSubstring(s, "vstmanlib")) return DAW.VSTScanner;
    if (hasSubstring(s, "aulab")) return DAW.AULab;
    if (hasSubstring(s, "garageband")) return DAW.GarageBand;
    if (hasSubstring(s, "forte")) return DAW.Forte;
    if (hasSubstring(s, "chainer")) return DAW.Chainer;
    if (hasSubstring(s, "audition")) return DAW.Audition;
    if (hasSubstring(s, "orion")) return DAW.Orion;
    if (hasSubstring(s, "sawstudio")) return DAW.SAWStudio;
    if (hasSubstring(s, "logic")) return DAW.Logic;
    if (hasSubstring(s, "digital")) return DAW.DigitalPerformer;
    if (hasSubstring(s, "audiomulch")) return DAW.AudioMulch;
    if (hasSubstring(s, "presonus")) return DAW.StudioOne;
    if (hasSubstring(s, "vst3plugintesthost")) return DAW.VST3TestHost;
    if (hasSubstring(s, "protools")) return DAW.ProTools;
    if (hasSubstring(s, "ardour")) return DAW.Ardour;
    if (hasSubstring(s, "standalone")) return DAW.Standalone;
    return DAW.Unknown;
}

