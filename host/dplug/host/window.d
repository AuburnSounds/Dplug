/**
 * Copyright: Copyright Auburn Sounds 2016
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.host.window;

import dplug.window;
import dplug.host.host;

/// Creates a new native window suitable to host the plugin window.
/// This window may keep a reference to pluginHost
IWindow createHostWindow(IPluginHost pluginHost)
{    
    int[2] windowSize = pluginHost.getUISize();

    auto hostWindow = createWindow(null, null, null, WindowBackend.autodetect, windowSize[0], windowSize[1]);
    pluginHost.openUI(hostWindow.systemHandle());

    return hostWindow;
}
