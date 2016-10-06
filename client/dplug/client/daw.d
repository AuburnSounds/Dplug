/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 and later Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
module dplug.client.daw;

import core.stdc.string;

import std.string,
       std.utf;

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
