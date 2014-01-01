import dplug.vst;

import dplug.plugin;
import dplug.vst;


__gshared VSTClient plugin;

extern (C) nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) 
{
    if (hostCallback is null)
        return null;

    try
    {
        auto client = Client(CCONST('l', 'o', 'l', '!'));
        client.addParameter(Parameter("param0"));
        client.addParameter(Parameter("test"));
        client.addParameter(Parameter("test2"));
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

