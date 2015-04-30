module dplug.gui.toolkit;

// ae.utils.graphics is fundamental to use dplug's gui
public import ae.utils.graphics;

public import dplug.gui.toolkit.element;
public import dplug.gui.toolkit.context;
public import dplug.gui.toolkit.font;
public import dplug.gui.toolkit.knob;
public import dplug.gui.toolkit.slider;



/// Loads an image from a static array
Image!RGBA loadImage(const(ubyte[]) imageData)
{
    import gfm.image.stb_image;
    import core.stdc.string;

    void[] data = cast(void[])imageData;
    int width, height, components;
    ubyte* decoded = stbi_load_from_memory(data, width, height, components, 4);
    scope(exit) stbi_image_free(decoded);

    // stb_image guarantees that ouput will always have 4 components when asked
    // Fortunately they are already RGBA

    // allocates result
    Image!RGBA loaded = Image!RGBA(width, height);

    // copy pixels (here they are contiguous in each case)
    memcpy(loaded.pixels.ptr, decoded, width * height * 4);
    return loaded; // this uses the GC to give up ownership
}
