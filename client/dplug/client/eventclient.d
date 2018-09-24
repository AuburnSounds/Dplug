/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 - 2017 Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/

/// Special base client implementation that uses callbacks in addition to the readXYZParamValue() methods
/// Usage: override .buildCallbackParameters
module dplug.client.eventclient;

import dplug.core.vec;
import dplug.client.client;
import dplug.client.params;

/// Wrapper struct
struct ParameterEvent
{
    alias SetParameterCallback = void delegate() nothrow @nogc;

    Parameter param;
    SetParameterCallback callback;
}

/// Inherit from this class and override .buildCallbackParameters
class EventClient : Client
{

    public this() nothrow @nogc
    {
        super();
    }

    final override void setParameterFromHost(int index, float value) nothrow @nogc
    {
        super.setParameterFromHost(index, value);
        _paramEvents[index].callback();
    }

    final override Parameter[] buildParameters() nothrow @nogc
    {
        _paramEvents = buildParameterEvents();

        auto params = makeVec!Parameter();
        foreach (pe; _paramEvents)
        {
            assert(pe.callback !is null, "No/invalid callback assigned to parameter");
            params.pushBack(pe.param);
        }
        return params.releaseData();
    }

    /// Override this method to implement parameter creation.
    /// This is an optional overload, default implementation declare no parameters.
    /// The returned slice must be allocated with `malloc`/`mallocSlice` and contains
    /// `ParameterEvent` instances.
    ParameterEvent[] buildParameterEvents() nothrow @nogc
    {
        return [];
    }

private:
    ParameterEvent[] _paramEvents;
}

