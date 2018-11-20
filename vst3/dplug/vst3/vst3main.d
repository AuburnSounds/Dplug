//-----------------------------------------------------------------------------
// LICENSE
// (c) 2018, Steinberg Media Technologies GmbH, All Rights Reserved
//-----------------------------------------------------------------------------
/*
This license applies only to files referencing this license,
for other files of the Software Development Kit the respective embedded license text
is applicable. The license can be found at: www.steinberg.net/sdklicenses_vst3

This Software Development Kit is licensed under the terms of the Steinberg VST3 License,
or alternatively under the terms of the General Public License (GPL) Version 3.
You may use the Software Development Kit according to either of these licenses as it is
most appropriate for your project on a case-by-case basis (commercial or not).

a) Proprietary Steinberg VST3 License
The Software Development Kit may not be distributed in parts or its entirety
without prior written agreement by Steinberg Media Technologies GmbH.
The SDK must not be used to re-engineer or manipulate any technology used
in any Steinberg or Third-party application or software module,
unless permitted by law.
Neither the name of the Steinberg Media Technologies GmbH nor the names of its
contributors may be used to endorse or promote products derived from this
software without specific prior written permission.
Before publishing a software under the proprietary license, you need to obtain a copy
of the License Agreement signed by Steinberg Media Technologies GmbH.
The Steinberg VST SDK License Agreement can be found at:
www.steinberg.net/en/company/developers.html

THE SDK IS PROVIDED BY STEINBERG MEDIA TECHNOLOGIES GMBH "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL STEINBERG MEDIA TECHNOLOGIES GMBH BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
OF THE POSSIBILITY OF SUCH DAMAGE.

b) General Public License (GPL) Version 3
Details of these licenses can be found at: www.gnu.org/licenses/gpl-3.0.html
//----------------------------------------------------------------------------------
*/
/*
Copyright: Guillaume Piolat 2018.
*/
module dplug.vst3.vst3main;

nothrow @nogc:


import dplug.core.runtime;
import dplug.core.nogc;

import dplug.client.client;
import dplug.client.daw;

import dplug.vst3.funknown;
import dplug.vst3.ipluginbase;
import dplug.vst3.ftypes;
import dplug.vst3.ivstaudioprocessor;
import dplug.vst3.client;

template VST3EntryPoint(alias ClientClass)
{
    // Those exports are optional, but could be useful in the future
    enum entry_InitDll = `export extern(C) bool InitDLL() nothrow @nogc { return true; }`;
    enum entry_ExitDll = `export extern(C) bool ExitDll() nothrow @nogc { return true; }`;

    enum entry_GetPluginFactory =
        "export extern(C) void* GetPluginFactory() nothrow @nogc" ~
        "{" ~
        "    return cast(void*)(GetPluginFactoryInternal!" ~ ClientClass.stringof ~ ");" ~
        "}";

    const char[] VST3EntryPoint = entry_InitDll ~ entry_ExitDll ~ entry_GetPluginFactory;
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

        PFactoryInfo factoryInfo = PFactoryInfo("Witty Audio",  // TODO
                                                "https://example.com",  // TODO
                                                "support@wittyaudio.fake", // TODO
                                                PFactoryInfo.kUnicode);

        auto pluginFactory = mallocNew!CPluginFactory(factoryInfo);
        gPluginFactory = pluginFactory;

        enum uint DPLUG_MAGIC  = 0xB20BA92;
        enum uint DPLUG_MAGIC2 = 0xCE0B145;
        char[4] vid = client.getVendorUniqueID();
        char[4] pid = client.getPluginUniqueID();
        TUID classId = INLINE_UID(DPLUG_MAGIC, DPLUG_MAGIC2, *cast(uint*)(vid.ptr), *cast(uint*)(pid.ptr));

        auto pluginNameZ = CString(client.pluginName());
        auto vendorNameZ = CString(client.vendorName());

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
extern(Windows) FUnknown createVST3Client(ClientClass)(void* hostInterface) nothrow @nogc
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();
    ClientClass client = mallocNew!ClientClass();
    VST3Client plugin = mallocNew!VST3Client(client, cast(FUnknown) hostInterface);
    return /*cast(IAudioProcessor)*/plugin;
}