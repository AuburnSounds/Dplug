import dplug.vst;


alias VSTPlugin VSTPluginClass;
int uniqueID = CCONST('l', 'o', 'l', 'Z');

__gshared VSTPluginClass plugin;

extern (Windows) nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) 
{
    if (hostCallback is null)
        return null;

    try
    {
        plugin = mallocEmplace!(VSTPlugin, HostCallbackFunction, int)(hostCallback, uniqueID);
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

