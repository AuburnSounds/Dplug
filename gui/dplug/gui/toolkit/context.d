module dplug.gui.toolkit.context;

import std.file;

import gfm.math;

import dplug.gui.toolkit.font;
import dplug.gui.toolkit.element;


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
        skybox.size(1024, 1024);
    }

    ~this()
    {
        // neither images or fonts need clean-up, nothing to be done
    }

    UIElement focused = null; // last clicked element
    UIElement dragged = null; // current dragged element
    Image!RGBA skybox;

    void setFocused(UIElement focused)
    {
        this.focused = focused;
    }

    void beginDragging(UIElement element)
    {
        stopDragging();

        // Uncomment this once SDL_CaptureMouse is in Derelict
        // SDL_CaptureMouse(SDL_TRUE);

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
}




