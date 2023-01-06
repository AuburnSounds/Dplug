/// stb_image_write.h translations
/// Just the PNG encoder.
module dplug.graphics.stb_image_write;

import gamut;

import dplug.graphics.image;

nothrow @nogc:

// TODO: deprecate, should use gamut directly

/// Create a PNG image from an ImageRef!RGBA.
/// The data has to be freed with `free()` or `freeSlice`.
ubyte[] convertImageRefToPNG(ImageRef!RGBA image)
{
    Image gamutImage;
    gamutImage.createViewFromImageRef!RGBA(image);
    return gamutImage.saveToMemory(ImageFormat.PNG);
}

/// Create a PNG image from an ImageRef!L8.
/// The data has to be freed with `free()` or `freeSlice`.
// TODO: deprecate, should use gamut directly.
ubyte[] convertImageRefToPNG(ImageRef!L8 image)
{
    Image gamutImage;
    gamutImage.createViewFromImageRef!L8(image);
    return gamutImage.saveToMemory(ImageFormat.PNG);
}
