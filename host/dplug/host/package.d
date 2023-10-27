/**
Generic host interface.

Copyright: Auburn Sounds 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.host;

import dplug.core.sharedlib;
import dplug.core.nogc;
public import dplug.host.host;
public import dplug.host.vst2;
public import dplug.host.window;

nothrow @nogc:

/// Loads an audio plugin.
/// Such a host MUST be destroyed with `destroyPluginHost`.
/// Return: a plugin host, or `null` on error.
IPluginHost createPluginHost(string dynlibPath)
{
    // FUTURE support OSX plugin bundles
    SharedLib lib;
    lib.load(dynlibPath);

    // Detect if  this is a VST plugin
    void* VSTPluginMain = getVST2EntryPoint(lib);
    if (VSTPluginMain != null) 
    {
        version(VST2)
        {
            bool err;
            VST2PluginHost instance = mallocNew!VST2PluginHost(lib.disown, &err);
            if (err)
            {
                destroyFree(instance);
                return null; // TODO: shall call destructor?
            }
            return instance;
        }
        else
            return null; // VST 2.4 not supported
    }
    else
        return null; // unknown format
}

/// Destroy a plugin host created with `createPluginHost`.
/// Works even if `host` is null.
void destroyPluginHost(IPluginHost host) nothrow @nogc
{
    destroyFree(host);
}