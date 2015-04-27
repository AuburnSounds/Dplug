module dplug.gui.toolkit.context;

import core.stdc.string;

import std.file;

import gfm.math;
import gfm.image.stb_image;


import dplug.gui.toolkit.font;
import dplug.gui.toolkit.element;


/// UIContext contains the "globals" of the UI
/// - current focused element
/// - current dragged element
/// - images and fonts...
class UIContext
{
public:
    this(Font font_)
    {
        font = font_;
    }

    void close()
    {
    }

    void addFont(string name, immutable(ubyte[]) data)
    {

    }

    void addImage(string name, immutable(ubyte[]) data)
    {
        _images[name] = loadImage(data);
    }

    Font font;
    UIElement focused = null; // last clicked element
    UIElement dragged = null; // current dragged element

    Image!RGBA image(string name)
    {
        return _images[name];
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

private:
    Image!RGBA[string] _images;

    Image!RGBA loadImage(immutable(ubyte[]) imageData)
    {
        void[] data = cast(void[])imageData;
        int width, height, components;
        ubyte* decoded = stbi_load_from_memory(data, width, height, components, 4);
        scope(exit) stbi_image_free(decoded);

        // stb_image guarantees that ouput will always have 4 components when asked

        // allocates result
        Image!RGBA loaded = Image!RGBA(width, height);

        // copy pixels (here they are contiguous in each case)
        memcpy(loaded.pixels.ptr, decoded, width * height * 4);
        return loaded; // this use GC to give up ownership...
    }
}




