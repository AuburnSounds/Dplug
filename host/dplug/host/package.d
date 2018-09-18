/**
 * Generic plug-in host interface.
 *
 * Copyright: Copyright Auburn Sounds 2016
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
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

    auto VSTPluginMain = getVSTEntryPoint(lib);
    if (VSTPluginMain != null) // is this is a VST plugin?
    {
        return new VSTPluginHost(move(lib));
    }
    else
        throw new Exception(format("Couldn't load plugin '%s': unknown format", dynlibPath));
}
