import dplug.vst;

import dplug.plugin;
import dplug.vst;


final class Distort : dplug.plugin.Client
{
    override int getPluginID()
    {
        return CCONST('l', 'o', 'l', 'd');
    }

    override void buildParameters()
    {
        addParameter(new Parameter("input", "db"));
        addParameter(new Parameter("drive", "%"));
        addParameter(new Parameter("output", "db"));
    }
}

__gshared VSTClient plugin;
__gshared Distort client;

extern (C) nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) 
{
    if (hostCallback is null)
        return null;

    try
    {
        auto client = new Distort();

        plugin = new VSTClient(client, hostCallback);
    }
    catch (Throwable e)
    {
        unrecoverableError(); // should not throw in a callback
        return null;
    }
    return &plugin._effect;
}

// doesn't work
//mixin VSTEntryPoint!(VSTPlugin, CCONST('l', 'o', 'l', 'Z'));

