module dplug.plugin.graphics;

import dplug.plugin.client;

/// Plugin GUI
interface IGraphics
{
    abstract void openUI(void* parentInfo);
    abstract void closeUI();
    abstract int getGUIWidth();
    abstract int getGUIHeight();
}

/// Default Graphics object, does nothing
class NullGraphics : IGraphics
{
    override void openUI(void* parentInfo)
    {
    }

    override void closeUI()
    {
    }

    override int getGUIWidth()
    {
        return 0;
    }

    override int getGUIHeight()
    {
        return 0;
    }
}
