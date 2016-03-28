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
module dplug.au.client;

import core.stdc.config;
import derelict.carbon;
import gfm.core;
import dplug.core;
import dplug.client.client;


template AUEntryPoint(alias ClientClass)
{
    // The entry point names must be kept in sync with names in the .rsrc

    const char[] AUEntryPoint =
    "import derelict.carbon;"
    "extern(C) nothrow ComponentResult dplugAUEntryPoint(ComponentParameters* params, void* pPlug)"
    "{"
        "return audioUnitEntryPoint!" ~ ClientClass.stringof ~ "(params, pPlug);"
    "}"
    "extern(C) nothrow ComponentResult dplugAUCarbonViewEntryPoint(ComponentParameters* params, void* pView)"
    "{"
        "return audioUnitCarbonViewEntry!" ~ ClientClass.stringof ~ "(params, pView);"
    "}";
}

// LP64 => "long and pointers are 64-bit"
static if (size_t.sizeof == 8 && c_long.sizeof == 8)
    private enum __LP64__ = 1;
else
    private enum __LP64__ = 0;


private T getCompParam(T, int Idx, int Num)(ComponentParameters* params)
{
    static if (__LP64__)
        return *cast(T*)&(params.params[Num - Idx]);
    else
        return *cast(T*)&(params.params[Idx]);
}

void attachToRuntimeIfNeeded()
{
    import core.thread;
    import dplug.client.dllmain;
    runtimeInitWorkaround15060();
    thread_attachThis();
}

nothrow ComponentResult audioUnitEntryPoint(alias ClientClass)(ComponentParameters* params, void* pPlug)
{
    try
    {
        attachToRuntimeIfNeeded();
        int select = params.what;

        import core.stdc.stdio;
        debug printf("audioUnitEntryPoint %d", select);

        if (select == kComponentOpenSelect)
        {
            DerelictCoreServices.load();

            // Create client and AUClient
            auto client = new ClientClass();
            ComponentInstance instance = params.getCompParam!(ComponentInstance, 0, 1);
            AUClient plugin = mallocEmplace!AUClient(client, instance);
            SetComponentInstanceStorage( instance, cast(Handle)(cast(void*)plugin) );
            return noErr;
        }

        AUClient auClient = cast(AUClient)pPlug;
        assert(auClient !is null);

        return auClient.dispatcher(select, params);
    }
    catch (Throwable e)
    {
        moreInfoForDebug(e);
        unrecoverableError();
        return noErr;
    }
}

nothrow ComponentResult audioUnitCarbonViewEntry(alias ClientClass)(ComponentParameters* params, void* pView)
{
    // TODO
    return 0;
}

/// AU client wrapper
/// Big TODO
class AUClient
{
public:

    this(Client client, ComponentInstance instance)
    {
        _client = client;
        _instance = instance;
    }

    ~this()
    {
        debug ensureNotInGC("dplug.au.Client");
        _client.destroy();
    }

    ComponentResult dispatcher(int select, ComponentParameters* params)
    {
        // TODO lock here?

        switch(select)
        {
            case kComponentCloseSelect:
                this.destroy(); // free all resources except this and the runtime
                return noErr;

            default:
                return noErr;
        }
    }

private:
    ComponentInstance _instance;
    Client _client;
}