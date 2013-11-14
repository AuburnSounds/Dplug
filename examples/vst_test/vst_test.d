import dplug.vst;

__gshared AEffectDispatcherProc callback;
__gshared VSTPlugin plugin;

extern(C)
{
    AEffect* VSTPluginMain(HostCallbackFunction audioMain) 
    {
        callback = audioMain;

        try 
        {    
            plugin = new VSTPlugin(audioMain);
        } 
        catch (Throwable e) 
        {
            return null;
        }
    
        return &plugin._effect;
    }
}
