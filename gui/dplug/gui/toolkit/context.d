module dplug.gui.toolkit.context;

import core.stdc.string;

import std.file;

import gfm.math;
import gfm.image.stb_image;


import dplug.gui.toolkit.font;
import dplug.gui.toolkit.element;
import dplug.gui.toolkit.renderer;


// TODO: fix non-locality of fonts and graphics, and remove that "context" which is 
//       kind of a global

class UIContext
{
public:
    this(UIRenderer renderer_, Font font_)
    {
        renderer = renderer_;
        font = font_;
    }

    void close()
    {
    }

    void addImage(string name, immutable(ubyte[]) data)
    {
        _images[name] = loadImage(data);
    }

    UIRenderer renderer;
    Font font;
    UIElement dragged = null; // current dragged element

    Image!RGBA image(string name)
    {
        return _images[name];
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

            // TODO find equivalent
            // SDL_CaptureMouse(SDL_FALSE);
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




