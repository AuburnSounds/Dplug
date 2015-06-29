/**
 * Copyright: Copyright Auburn Sounds 2015 and later.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.plugin.graphics;

import dplug.plugin.client;
import dplug.plugin.daw;

/// Plugin GUI
interface IGraphics
{
    abstract void openUI(void* parentInfo, DAW daw);
    abstract void closeUI();
    abstract int getGUIWidth();
    abstract int getGUIHeight();
}

/// Default Graphics object, does nothing
class NullGraphics : IGraphics
{
    override void openUI(void* parentInfo, DAW daw)
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
