/**
Generic host interface.

Copyright: Auburn Sounds 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.host;

public import dplug.host.host;
public import dplug.host.vst;
public import dplug.host.window;

import std.algorithm.mutation;

/// Loads an audio plugin.
IPluginHost createPluginHost(string dynlibPath)
{
    import std.string;
    import dplug.core.sharedlib;

    // FUTURE support OSX plugin bundles
    SharedLib lib;
    lib.load(dynlibPath);

    // Detect if  this is a VST plugin
    void* VSTPluginMain = getVSTEntryPoint(lib);
    if (VSTPluginMain != null) 
    {
        version(VST)
        {
            return new VSTPluginHost(move(lib));
        }
        else
            throw new Exception(format("Couldn't load plugin '%s': VST 2.4 format not supported", dynlibPath));
    }
    else
        throw new Exception(format("Couldn't load plugin '%s': unknown format", dynlibPath));
}
