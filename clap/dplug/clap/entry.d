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


// version.h

import dplug.clap;

enum uint CLAP_VERSION_MAJOR = 1;
enum uint CLAP_VERSION_MINOR = 2;
enum uint CLAP_VERSION_REVISION = 2;
/*
clap_version_t CLAP_VERSION_INIT(uint major, uint minor, uint rev) 
{
    return clap_version(major, minor, rev);
}*/

bool CLAP_VERSION_LT(uint maj, uint min, uint rev)
{
    if (CLAP_VERSION_MAJOR < maj) return true;
    if ((maj == CLAP_VERSION_MAJOR) && (CLAP_VERSION_MINOR < min)) return true;
    if ((maj == CLAP_VERSION_MAJOR) && (min == CLAP_VERSION_MINOR) 
        && (CLAP_VERSION_REVISION < rev))
        return true;
    return false;
}

bool CLAP_VERSION_EQ(uint maj, uint min, uint rev)
{
    return maj == CLAP_VERSION_MAJOR
        && min == CLAP_VERSION_MINOR
        && rev == CLAP_VERSION_REVISION;
}

bool CLAP_VERSION_GE(uint maj, uint min, uint rev)
{
    return ! CLAP_VERSION_LT(maj, min, rev);
}

bool clap_version_is_compatible(T)(T v) 
{
   // versions 0.x.y were used during development stage and aren't compatible
   return v.major >= 1;
}
import core.stdc.stdio;
// Get the pointer to a factory. See factory/plugin-factory.h for an example.
//
// Returns null if the factory is not provided.
// The returned pointer must *not* be freed by the caller.
const(void)* clap_factory_templated(ClientCLass)(const(char)* factory_id) 
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    printf("Hey\n");

    if (!strcmp(factory_id, "clap.plugin-factory"))
    {
        __gshared clap_plugin_factory_t g_factory;
        g_factory.get_plugin_count = &factory_get_plugin_count;
        g_factory.get_plugin_descriptor = &factory_get_plugin_descriptor;
        g_factory.create_plugin = &factory_create_plugin;
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

    clap_plugin_descriptor_t* factory_get_plugin_descriptor(const(clap_plugin_factory_t)* factory, uint index)
    {
        __gshared clap_plugin_descriptor_t desc;
        return null;//&desc;
    }

    void* factory_create_plugin(const(clap_plugin_factory_t)*factory,
        const(void)* host,
        const(char)* plugin_id)
    {
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


struct clap_plugin_descriptor_t
{
    // TODO
}