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
module dplug.lv2.lv2_init;

version(LV2):

import core.stdc.stdint;
import core.stdc.string;

import dplug.core.nogc;
import dplug.core.runtime;

import dplug.client.client;

import dplug.lv2.lv2;
import dplug.lv2.ui;
import dplug.lv2.state;
import dplug.lv2.lv2client;
import dplug.lv2.ttl;

//debug = debugLV2Client;



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
        "export extern(C) int GenerateManifestFromClient(char* manifestBuf, int manifestBufLen, const(char)* binaryFileName, int binaryFileNameLen)"  ~
        "{" ~
        "    return GenerateManifestFromClient_templated!" ~ ClientClass.stringof ~ "(manifestBuf[0..manifestBufLen], binaryFileName[0..binaryFileNameLen]);" ~
        "}\n";

    const char[] LV2EntryPoint = lv2_descriptor ~ lv2_ui_descriptor ~ generate_manifest_from_client;
}

const(LV2_Descriptor)* lv2_descriptor_templated(ClientClass)(uint index) nothrow @nogc
{
    debug(debugLV2Client) debugLog(">lv2_descriptor_templated");
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();
    
    build_all_lv2_descriptors!ClientClass();
    if(index >= cast(int)(lv2Descriptors.length))
        return null;

    debug(debugLV2Client) debugLog("<lv2_descriptor_templated");
    return &lv2Descriptors[index];
}

const (LV2UI_Descriptor)* lv2ui_descriptor_templated(ClientClass)(uint index) nothrow @nogc
{
    debug(debugLV2Client) debugLog(">lv2ui_descriptor_templated");
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    
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
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();
    
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
        lv2Descriptors[io].extension_data = &extensionData;
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
            extension_data: &extensionDataUI
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

/*
    LV2 Callback function implementations
*/
extern(C) nothrow @nogc
{
    void connect_port(LV2_Handle instance, uint32_t   port, void* data)
    {
        debug(debugLV2Client) debugLog(">connect_port");
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.connect_port(port, data);
        debug(debugLV2Client) debugLog("<connect_port");
    }

    void activate(LV2_Handle instance)
    {
        debug(debugLV2Client) debugLog(">activate");
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.activate();
        debug(debugLV2Client) debugLog("<activate");
    }

    void run(LV2_Handle instance, uint32_t n_samples)
    {
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
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
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
        LV2Client lv2client = cast(LV2Client)instance;
        lv2client.destroyFree();
        debug(debugLV2Client) debugLog("<cleanup");
    }

    const (void)* extensionData(const char* uri)
    {
        void* feature = null;
        debug(debugLV2Client) debugLogf(">extension_data: %s", uri);

        version(futureBinState)
        {
            static immutable LV2_State_Interface lv2StateInterface = LV2_State_Interface(&state_save, &state_restore);
            if (!strcmp(uri, LV2_STATE__interface)) {
                feature = cast(void*)&lv2StateInterface;
            }
        }

        debug(debugLV2Client) debugLog("<extension_dataUI");
        return feature;
    }

    const (void)* extensionDataUI(const char* uri)
    {
        void* feature = null;
        debug(debugLV2Client) debugLogf(">extension_dataUI: %s", uri);
        static const LV2UI_Resize lv2UIResize = LV2UI_Resize(cast(void*)null, &uiResize);
        if (!strcmp(uri, LV2_UI__resize)) {
            feature = cast(void*)&lv2UIResize;
        }

        debug(debugLV2Client) debugLog("<extension_dataUI");
        return feature;
    }
    
    /// This is currently not fully implemented
    /// According to the LV2 IRC channel, this extension is planned to be
    /// phased out.  The only known host that uses this extension is
    /// synthpod.  LV2 plug-ins should respond directly to resize
    /// events from the window.
    /// Note: is it used at all?
    int uiResize(LV2UI_Feature_Handle handle, int width, int height)
    {
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
        LV2Client lv2client = cast(LV2Client)handle;
        return 0;
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
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
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
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
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
        //debug(debugLV2Client) debugLog(">port_event");
        ScopedForeignCallback!(false, true) scopedCallback;
        scopedCallback.enter();
        LV2Client lv2client = cast(LV2Client)ui;
        lv2client.portEventUI(port_index, buffer_size, format, buffer);
        //debug(debugLV2Client) debugLog("<port_event");
    }

    version(futureBinState)
    {

        // Save plugin state (beyond the port values).
        LV2_State_Status state_save (LV2_Handle               instance,
                                     LV2_State_Store_Function store,
                                     LV2_State_Handle         handle,
                                     uint                     flags,
                                     const(LV2_Feature*)*     features)
        {
            debug(debugLV2Client) debugLog(">state_save");

            LV2Client lv2client = cast(LV2Client)instance;

            // Get the most current base64-encoded state + terminal zero.
            const(ubyte)[] lastChunk = lv2client.getBase64EncodedStateZ();

            LV2_State_Status res = store(handle,
                                         lv2client.getStateBinaryURID(),
                                         lastChunk.ptr,
                                         lastChunk.length, // this includes a terminal zero
                                         lv2client.getAtomStringURID(),
                                         LV2_STATE_IS_POD | LV2_STATE_IS_PORTABLE);
            debug(debugLV2Client) debugLog("<state_save");
            return res;
        }


        LV2_State_Status state_restore(LV2_Handle                  instance,
                                       LV2_State_Retrieve_Function retrieve,
                                       LV2_State_Handle            handle,
                                       uint                        flags, // those flags currently unused by LV2
                                       const(LV2_Feature*)*        features)
        {
            debug(debugLV2Client) debugLog(">state_restore");
            LV2Client lv2client = cast(LV2Client)instance;

            // BUG: this doesn't restore stuff

            size_t len;
            uint type;
            uint rflags;
            const(void)* pStateBinary = retrieve(handle, lv2client.getStateBinaryURID(), &len, &type, &rflags);

            if (pStateBinary == null)
                return LV2_STATE_ERR_NO_PROPERTY;

            if (type != lv2client.getAtomStringURID())
                return LV2_STATE_ERR_BAD_TYPE;

            if (len == 0)
                return LV2_STATE_ERR_BAD_TYPE;

            const(ubyte)[] chunk = (cast(const(ubyte)*)pStateBinary)[0..len-1];
            lv2client.restoreStateBinaryBase64(chunk);

            debug(debugLV2Client) debugLog("<state_restore");
            return LV2_STATE_SUCCESS;
        }
    }
}
