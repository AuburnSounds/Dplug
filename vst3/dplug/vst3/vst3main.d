/*

MIT License

Copyright (c) 2025, Steinberg Media Technologies GmbH, All rights reserved.
Copyright (c) 2025, Guillaume Piolat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following condition.s:

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

        CString vendorNameZ = CString(client.vendorName);

        string vendorEmail = client.getVendorSupportEmail();
        if (!vendorEmail) vendorEmail = "support@example.com";

        string pluginHomepage = client.pluginHomepage();
        if (!pluginHomepage) pluginHomepage = "https://google.com";

        CString pluginHomepageZ = CString(pluginHomepage);
        CString vendorEmailZ = CString(vendorEmail);

        PFactoryInfo factoryInfo = PFactoryInfo(vendorNameZ.storage,
                                                pluginHomepageZ.storage,
                                                vendorEmailZ.storage,
                                                PFactoryInfo.kUnicode);

        auto pluginFactory = mallocNew!CPluginFactory(factoryInfo);
        gPluginFactory = pluginFactory;

        enum uint DPLUG_MAGIC  = 0xB20BA92;
        enum uint DPLUG_MAGIC2 = 0xCE0B145;
        char[4] vid = client.getVendorUniqueID();
        char[4] pid = client.getPluginUniqueID();
        TUID classId = INLINE_UID(DPLUG_MAGIC, DPLUG_MAGIC2, *cast(uint*)(vid.ptr), *cast(uint*)(pid.ptr));

        CString pluginNameZ = CString(client.pluginName());
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
                                                 pluginNameZ.storage,
                                                 kSimpleModeSupported,
                                                 vst3Category.ptr,
                                                 vendorNameZ.storage,
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