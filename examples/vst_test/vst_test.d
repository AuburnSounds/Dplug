import dplug.vst;

import dplug.plugin;
import dplug.vst;


__gshared VSTClient plugin;
__gshared Client client;

extern (C) nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) 
{
    if (hostCallback is null)
        return null;

    try
    {
        auto client = new Client(CCONST('l', 'o', 'l', '!'));
        client.addParameter(new Parameter("input", "dB"));
        client.addParameter(new Parameter("drive", "%"));
        client.addParameter(new Parameter("output", "dB"));
        plugin = mallocEmplace!(VSTClient, Client, HostCallbackFunction)(client, hostCallback);
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

