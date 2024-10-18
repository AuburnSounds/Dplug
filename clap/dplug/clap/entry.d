/*
MIT License

Copyright (c) 2021 Alexandre BIQUE
Copyright (c) 2024 Guillaume PIOLAT

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

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
module dplug.clap.entry;

nothrow @nogc:

import core.stdc.string;
import dplug.core.runtime;
import dplug.core.nogc;


// version.h

import dplug.clap;
import dplug.clap.clapversion;

import core.stdc.stdio;
// Get the pointer to a factory. See factory/plugin-factory.h for an example.
//
// Returns null if the factory is not provided.
// The returned pointer must *not* be freed by the caller.
const(void)* clap_factory_templated(ClientClass)(const(char)* factory_id) 
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    if (!strcmp(factory_id, "clap.plugin-factory"))
    {
        __gshared clap_plugin_factory_t g_factory;
        g_factory.get_plugin_count = &factory_get_plugin_count;
        g_factory.get_plugin_descriptor = &factory_get_plugin_descriptor!ClientClass;
        g_factory.create_plugin = &factory_create_plugin;
           printf("Hey\n");
        return &g_factory;
    }
    return null;
}

extern(C)
{
    // Get the number of plugins available.
    uint factory_get_plugin_count(const(clap_plugin_factory_t)* factory)
    {
        return 1;
    }

    clap_plugin_descriptor_t* factory_get_plugin_descriptor(ClientClass)(const(clap_plugin_factory_t)* factory, uint index)
    {
        if (index != 0)
            return null;

        // Fill with information from PluginClass
        __gshared clap_plugin_descriptor_t desc;

        // Create a client just for the purpose of describing the plug-in
        ClientClass client = mallocNew!ClientClass();
        scope(exit) client.destroyFree();

        desc.id = "com.wittyaudio.msencode"; // TODO persistent stringZ instead
        desc.name = "MSEncodator"; // TODO persistent stringZ instead
        desc.vendor = "Witty Audio"; // TODO persistent stringZ instead
        desc.url = "https://wittyaudio.com/msencode"; // TODO persistent stringZ instead
        desc.manual_url = "https://wittyaudio.com/msencode/manual.pdf"; // TODO persistent stringZ instead
        desc.support_url = "https://example.com"; // TODO
        desc.version_ = "1.0.0"; // TODO
        desc.description = "My Description"; // TODO
        desc.features = ["mono".ptr].ptr;
        printf("Whatyado\n");
        return &desc;
    }

    void* factory_create_plugin(const(clap_plugin_factory_t)*factory,
        const(void)* host,
        const(char)* plugin_id)
    {
        // TODO
        return null;
    }
}

// factory.h

struct clap_plugin_factory_t 
{
nothrow @nogc extern(C):

   uint function(const(clap_plugin_factory_t)*) get_plugin_count;
   clap_plugin_descriptor_t* function(const(clap_plugin_factory_t)*,uint) get_plugin_descriptor;
   void* function(const(clap_plugin_factory_t)*, const(void)*, const(char)*) create_plugin;
}


// plugin.h

struct clap_plugin_descriptor_t 
{
    clap_version_t clap_version; // initialized to CLAP_VERSION

    // Mandatory fields must be set and must not be blank.
    // Otherwise the fields can be null or blank, though it is safer to make them blank.
    //
    // Some indications regarding id and version
    // - id is an arbitrary string which should be unique to your plugin,
    //   we encourage you to use a reverse URI eg: "com.u-he.diva"
    // - version is an arbitrary string which describes a plugin,
    //   it is useful for the host to understand and be able to compare two different
    //   version strings, so here is a regex like expression which is likely to be
    //   understood by most hosts: MAJOR(.MINOR(.REVISION)?)?( (Alpha|Beta) XREV)?
    const(char)* id;          // eg: "com.u-he.diva", mandatory
    const(char)* name;        // eg: "Diva", mandatory
    const(char)* vendor;      // eg: "u-he"
    const(char)* url;         // eg: "https://u-he.com/products/diva/"
    const(char)* manual_url;  // eg: "https://dl.u-he.com/manuals/plugins/diva/Diva-user-guide.pdf"
    const(char)* support_url; // eg: "https://u-he.com/support/"
    const(char)* version_;     // eg: "1.4.4"
    const(char)* description; // eg: "The spirit of analogue"

    // Arbitrary list of keywords.
    // They can be matched by the host indexer and used to classify the plugin.
    // The array of pointers must be null terminated.
    // For some standard features see plugin-features.h
    const(char)** features;
}

