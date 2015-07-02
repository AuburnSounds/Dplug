/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.toolkit.context;

import std.file;

import gfm.math;

import dplug.gui.mipmap;
import dplug.quarantine.font;
import dplug.gui.toolkit.element;
import dplug.gui.toolkit.dirtylist;
import dplug.gui.window;


/// UIContext contains the "globals" of the UI
/// - current focused element
/// - current dragged element
/// - images and fonts...
class UIContext
{
public:
    this()
    {
        // create a dummy black skybox
        skybox.size(10, 1024, 1024);

        dirtyList = new DirtyRectList();
    }

    ~this()
    {
        close();
    }

    void close()
    {
        if (dirtyList !is null)
        {
            dirtyList.close();
            dirtyList = null;
        }
    }

    UIElement focused = null; // last clicked element
    UIElement dragged = null; // current dragged element
    Mipmap skybox;

    // This is the global UI list of rectangles that need updating.
    // This used to be a list of rectangles per UIElement,
    // but this wasn't workable because of too many races and
    // inefficiencies.
    DirtyRectList dirtyList; 
    

    void setSkybox(Image!RGBA image)
    {
        skybox.size(10, image.w, image.h);
        skybox.levels[0] = image;
        skybox.generateMipmaps(Mipmap.Quality.box);
    }

    void setFocused(UIElement focused)
    {
        this.focused = focused;
    }

    void beginDragging(UIElement element)
    {
        stopDragging();
        dragged = element;
        dragged.onBeginDrag();
    }

    void stopDragging()
    {
        if (dragged !is null)
        {
            dragged.onStopDrag();
            dragged = null;
        }
    }

    void delegate(string message) debugOutput;
}




