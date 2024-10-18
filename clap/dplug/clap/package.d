/**
CLAP client package. This module is the public API.

Copyright: Guillaume Piolat 2024.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.clap;

// CLever Audio Plugin format.
// Reference: 

version(CLAP):

import dplug.core.nogc;
import dplug.core.runtime


/*
// Main entry point for CLAP plugins.
template CLAPEntryPoint(alias ClientClass)
{
    static immutable enum create_plugin_instance =
        "export extern(C) void* CreatePlugInstance(void* Host, size_t Tag) nothrow @nogc" ~
        "{" ~
        "    return CreatePlugInstance_templated!" ~ ClientClass.stringof ~ "(Host, Tag);" ~
        "}\n";

    const char[] CLAPEntryPoint = create_plugin_instance;
}
*/