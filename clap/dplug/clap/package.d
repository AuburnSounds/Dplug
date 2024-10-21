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
module dplug.clap;

// CLever Audio Plugin format.
// Reference: 

version(CLAP):

nothrow @nogc:

import dplug.core.nogc;
import dplug.core.runtime;

import dplug.clap.clapversion;
import dplug.clap.types;
public import dplug.clap.clapversion;


// parts of entry.h and version.h here
extern(C)
{
    alias CLAP_init_function_t = bool function(const(char)* plugin_path);
    alias CLAP_deinit_function_t = void function();
    alias CLAP_get_factory_function_t = const(void)* function(const(char)* factory_id);
}

struct clap_plugin_entry_t {
    clap_version_t clap_version;
    CLAP_init_function_t init;
    CLAP_deinit_function_t deinit;
    CLAP_get_factory_function_t get_factory;
}

// Main entry point for CLAP plugins.
template CLAPEntryPoint(alias ClientClass)
{
    static immutable enum factory_entry =
    "extern(C) const(void)* clap_factory_entry(const(char)* factory_id) nothrow @nogc" ~
    "{" ~
    "    import dplug.clap.types;" ~
    "    return clap_factory_templated!" ~ ClientClass.stringof ~ "(factory_id);" ~
    "}\n";

    static immutable enum init_entry =
    `extern(C) bool clap_entry_init(const(char)* plugin_path) nothrow @nogc { return true; }`;

    static immutable enum deinit_entry =
    `extern(C) void clap_entry_deinit() nothrow @nogc { }`;

    static immutable enum plugin_entry = 
    `export extern(C) __gshared clap_plugin_entry_t clap_entry = clap_plugin_entry_t(CLAP_VERSION, &clap_entry_init, &clap_entry_deinit, &clap_factory_entry);`;

    const char[] CLAPEntryPoint = init_entry ~ deinit_entry ~ factory_entry ~ plugin_entry;
}


