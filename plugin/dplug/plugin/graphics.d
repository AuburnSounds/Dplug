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
    abstract int[2] getGUISize();
    abstract void close(); // free resources
}

