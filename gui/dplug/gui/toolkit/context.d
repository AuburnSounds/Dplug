module dplug.gui.toolkit.context;

import std.file;

import gfm.math;

import dplug.gui.mipmap;
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
        skybox.size(10, 1024, 1024);
    }

    ~this()
    {
        // neither image or fonts need clean-up, nothing to be done
    }

    UIElement focused = null; // last clicked element
    UIElement dragged = null; // current dragged element
    Mipmap skybox;

    void setSkybox(Image!RGBA image)
    {
        skybox.size(10, image.w, image.h);
        skybox.levels[0] = image;
        skybox.generateMipmaps();
    }

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




