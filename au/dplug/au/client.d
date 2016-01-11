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

import gfm.core;

import dplug.client.client;

template AUEntryPoint(alias ClientClass)
{
    const char[] AUEntryPoint = ""; // TODO
/*
    ComponentResult PLUG_ENTRY(ComponentParameters* params, void* pPlug)
    {
      return IPlugAU::IPlugAUEntry(params, pPlug);
    }
    ComponentResult PLUG_VIEW_ENTRY(ComponentParameters* params, void* pView)
    {
      return IPlugAU::IPlugAUCarbonViewEntry(params, pView);
    }
    */
}

/// AU client wrapper
/// Big TODO
class AUClient
{
public:

    this(Client client)
    {
        _client = client;
        _initialized = true;
    }

    ~this()
    {
        if (_initialized)
        {
            debug ensureNotInGC("dplug.au.Client");
            _client.destroy();
            _initialized = false;
        }
    }

private:
    Client _client;
    bool _initialized; // destructor flag
}