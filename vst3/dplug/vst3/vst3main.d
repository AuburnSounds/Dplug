//-----------------------------------------------------------------------------
// LICENSE
// (c) 2018, Steinberg Media Technologies GmbH, All Rights Reserved
// (c) 2018, Guillaume Piolat (contact@auburnsounds.com)
//-----------------------------------------------------------------------------
//
// This Software Development Kit is licensed under the terms of the General
// Public License (GPL) Version 3.
//
// This source is part of the "Auburn Sounds (Guillaume Piolat) extension to the 
// Steinberg VST 3 Plug-in SDK".
//
// Details of that license can be found at: www.gnu.org/licenses/gpl-3.0.html
//
// Dual-licence:
// 
// The "Auburn Sounds (Guillaume Piolat) extension to the Steinberg VST 3 Plug-in
// SDK", hereby referred to as DPLUG:VST3, is a language translation of the VST3 
// SDK suitable for usage in Dplug. Any Licensee of a currently valid Steinberg 
// VST 3 Plug-In SDK Licensing Agreement (version 2.2.4 or ulterior, hereby referred
// to as the AGREEMENT), is granted by Auburn Sounds (Guillaume Piolat) a non-exclusive, 
// worldwide, nontransferable license during the term the AGREEMENT to use parts
// of DPLUG:VST3 not covered by the AGREEMENT, as if they were originally 
// inside the Licensed Software Developer Kit mentionned in the AGREEMENT. 
// Under this licence all conditions that apply to the Licensed Software Developer 
// Kit also apply to DPLUG:VST3.
//
//-----------------------------------------------------------------------------
module dplug.vst3.vst3main;

version(VST3):

nothrow @nogc:

import core.stdc.stdio: snprintf;

import dplug.core.runtime;
import dplug.core.nogc;

import dplug.client.client;
import dplug.client.daw;

import dplug.vst3.ipluginbase;
import dplug.vst3.ftypes;
import dplug.vst3.ivstaudioprocessor;
import dplug.vst3.client;

template VST3EntryPoint(alias ClientClass)
{
    // Those exports are optional, but could be useful in the future
    enum entry_InitDll = `export extern(C) bool InitDll() nothrow @nogc { return true; }`;
    enum entry_ExitDll = `export extern(C) bool ExitDll() nothrow @nogc { return true; }`;

    enum entry_GetPluginFactory =
        "export extern(C) void* GetPluginFactory() nothrow @nogc" ~
        "{" ~
        "    return cast(void*)(GetPluginFactoryInternal!" ~ ClientClass.stringof ~ ");" ~
        "}";

    // macOS has different "shared libraries" and "bundle"
    // For Cubase, VST3 validator and Nuendo, the VST3 binary must be a macOS "bundle".
    // Other hosts don't seem to care.
    // This fake a macOS bundle with special entry points.
    enum entry_bundleEntry = `export extern(C) bool bundleEntry(void*) nothrow @nogc { return true; }`;
    enum entry_bundleExit = `export extern(C) bool bundleExit() nothrow @nogc { return true; }`;

    // Issue #433: on Linux, VST3 need entry points ModuleEntry and ModuleExit
    version(linux)
    {
        enum entry_ModuleEntry = `export extern(C) bool ModuleEntry(void*) nothrow @nogc { return true; }`;
        enum entry_ModuleExit = `export extern(C) bool ModuleExit(void*) nothrow @nogc { return true; }`;
    }
    else
    {
        enum entry_ModuleEntry = ``;
        enum entry_ModuleExit = ``;
    }

    const char[] VST3EntryPoint = entry_InitDll ~ entry_ExitDll 
                                ~ entry_GetPluginFactory 
                                ~ entry_bundleEntry ~ entry_bundleExit
                                ~ entry_ModuleEntry ~ entry_ModuleExit;
}

IPluginFactory GetPluginFactoryInternal(ClientClass)()
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    if (!gPluginFactory)
    {
        // Create a client just for the purpose of creating the factory
        ClientClass client = mallocNew!ClientClass();
        scope(exit) client.destroyFree();

        auto vendorNameZ = CString(client.vendorName);

        string vendorEmail = client.getVendorSupportEmail();
        if (!vendorEmail) vendorEmail = "support@example.com";

        string pluginHomepage = client.pluginHomepage();
        if (!pluginHomepage) pluginHomepage = "https://google.com";

        auto pluginHomepageZ = CString(pluginHomepage);
        auto vendorEmailZ = CString(vendorEmail);

        PFactoryInfo factoryInfo = PFactoryInfo(vendorNameZ,
                                                pluginHomepageZ,
                                                vendorEmailZ,
                                                PFactoryInfo.kUnicode);

        auto pluginFactory = mallocNew!CPluginFactory(factoryInfo);
        gPluginFactory = pluginFactory;

        enum uint DPLUG_MAGIC  = 0xB20BA92;
        enum uint DPLUG_MAGIC2 = 0xCE0B145;
        char[4] vid = client.getVendorUniqueID();
        char[4] pid = client.getPluginUniqueID();
        TUID classId = INLINE_UID(DPLUG_MAGIC, DPLUG_MAGIC2, *cast(uint*)(vid.ptr), *cast(uint*)(pid.ptr));

        auto pluginNameZ = CString(client.pluginName());
        char[64] versionString;
        client.getPublicVersion().toVST3VersionString(versionString.ptr, 64);

        string vst3Category;
        final switch(client.pluginCategory()) with (PluginCategory)
        {
            case effectAnalysisAndMetering: vst3Category = PlugType.kFxAnalyzer; break;
            case effectDelay:               vst3Category = PlugType.kFxDelay; break;
            case effectDistortion:          vst3Category = PlugType.kFxDistortion; break;
            case effectDynamics:            vst3Category = PlugType.kFxDynamics; break;
            case effectEQ:                  vst3Category = PlugType.kFxEQ; break;
            case effectImaging:             vst3Category = PlugType.kFxSpatial; break;
            case effectModulation:          vst3Category = PlugType.kFxModulation; break;
            case effectPitch:               vst3Category = PlugType.kFxPitchShift; break;
            case effectReverb:              vst3Category = PlugType.kFxReverb; break;
            case effectOther:               vst3Category = PlugType.kFx; break;
            case instrumentDrums:           vst3Category = PlugType.kInstrumentDrum; break;
            case instrumentSampler:         vst3Category = PlugType.kInstrumentSampler; break;
            case instrumentSynthesizer:     vst3Category = PlugType.kInstrumentSynth; break;
            case instrumentOther:           vst3Category = PlugType.kInstrumentSynth; break;
            case invalid:                   assert(false);
        }

        PClassInfo2 componentClass = PClassInfo2(classId,
                                                 PClassInfo.kManyInstances, // cardinality
                                                 kVstAudioEffectClass.ptr,
                                                 pluginNameZ,
                                                 kSimpleModeSupported,
                                                 vst3Category.ptr,
                                                 vendorNameZ,
                                                 versionString.ptr,
                                                 kVstVersionString.ptr);
        pluginFactory.registerClass(&componentClass, &(createVST3Client!ClientClass));
    }
    else
        gPluginFactory.addRef();

    return gPluginFactory;
}

// must return a IAudioProcessor
extern(C) FUnknown createVST3Client(ClientClass)(void* useless) nothrow @nogc
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();
    ClientClass client = mallocNew!ClientClass();
    VST3Client plugin = mallocNew!VST3Client(client);
    return plugin;
}