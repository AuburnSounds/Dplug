/**
FL Plugin client package. This module is the public API.

Copyright: Guillaume Piolat 2023.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flp;

// Fruity Loops Plug-in format.

version(FLP):

import dplug.core.nogc;
import dplug.core.runtime;
import dplug.flp.types;
import dplug.flp.client;

 
// Main entry point for FLP plugins.
template FLPEntryPoint(alias ClientClass)
{
    static immutable enum create_plugin_instance =
        "export extern(C) void* CreatePlugInstance(void* Host, size_t Tag) nothrow @nogc" ~
        "{" ~
        "    return CreatePlugInstance_templated!" ~ ClientClass.stringof ~ "(Host, Tag);" ~
        "}\n";

    const char[] FLPEntryPoint = create_plugin_instance;
}

// Templated helper.
void* CreatePlugInstance_templated(ClientClass)(void* Host, size_t Tag)
{
    TPluginTag tag = Tag;
    TFruityPlugHost pHost = cast(TFruityPlugHost) Host;

    if (pHost is null)
        return null;

    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    ClientClass client = mallocNew!ClientClass();

    bool err;
    FLPCLient plugin = mallocNew!FLPCLient(pHost, tag, client, &err);

    if (err)
    {
        destroyFree(client);
        return null;
    }

    return cast(void*) plugin;
}