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

import derelict.carbon.coreservices;
import gfm.core;

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

nothrow ComponentResult audioUnitEntryPoint(alias ClientClass)(ComponentParameters* params, void* pPlug)
{
    // TODO
    return 0;
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

    this(Client client)
    {
        _client = client;
    }

    ~this()
    {
        debug ensureNotInGC("dplug.au.Client");
        _client.destroy();
    }

private:
    Client _client;
}