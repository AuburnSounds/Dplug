/**
Wrapper for stb_image_resize.h port.
Makes it trivial to use.
Copyright: (c) Guillaume Piolat (2021)
*/
module dplug.graphics.resizer;

import std.math: PI;
import dplug.core.math;
import dplug.core.vec;
import dplug.graphics.color;
import dplug.graphics.image;
import dplug.graphics.stb_image_resize;


version = STB_image_resize;

/// Image resizer.
/// To minimize CPU, it is advised to reuse that object for similar resize.
/// To minimize memory allocation, it is advised to reuse that object even across different resize.
struct ImageResizer
{
public:
nothrow:
@nogc:

    @disable this(this);

    /**
    * Function resizes image. There are several other function for specialized treatment.
    *
    * Params:
    *   input Input image.
    *   output Output image.
    */
    void resizeImageGeneric(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        if (sameSizeResize(input, output))
            return;

        stbir_filter filter = STBIR_FILTER_DEFAULT;
        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }
    ///ditto
    void resizeImageGeneric(ImageRef!RGBA16 input, ImageRef!RGBA16 output)
    {
        if (sameSizeResize(input, output))
            return;

        stbir_filter filter = STBIR_FILTER_DEFAULT;
        int res = stbir_resize_uint16(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageSmoother(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        if (sameSizeResize(input, output))
            return;

        // suitable when depth is encoded in a RGB8 triplet, such as in UIImageKnob
        stbir_filter filter = STBIR_FILTER_CUBICBSPLINE;
        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageNearest(ImageRef!RGBA input, ImageRef!RGBA output) // same but with nearest filter
    {
        if (sameSizeResize(input, output))
            return;

        stbir_filter filter = STBIR_FILTER_BOX;
        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageGeneric(ImageRef!L16 input, ImageRef!L16 output)
    {
        if (sameSizeResize(input, output))
            return;

        stbir_filter filter = STBIR_FILTER_DEFAULT;
        int res = stbir_resize_uint16(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                      cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch, 1, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageDepth(ImageRef!L16 input, ImageRef!L16 output)
    {
        if (sameSizeResize(input, output))
            return;

        stbir_filter filter = STBIR_FILTER_MKS_2021;
        int res = stbir_resize_uint16(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                      cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch, 1, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageDepth(ImageRef!RGBA16 input, ImageRef!RGBA16 output)
    {
        // Note: this function is intended for those images that contain depth despite having 4 channels.
        if (sameSizeResize(input, output))
            return;

        stbir_filter filter = STBIR_FILTER_MKS_2021;
        int res = stbir_resize_uint16(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                      cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageCoverage(ImageRef!L8 input, ImageRef!L8 output)
    {
        if (sameSizeResize(input, output))
            return;

        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 1, STBIR_FILTER_DEFAULT, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImage_sRGBNoAlpha(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        if (sameSizeResize(input, output))
            return;
        stbir_filter filter = STBIR_FILTER_MKS_2013_86;
        int res = stbir_resize_uint8_srgb(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                          cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch,
                                          4, STBIR_ALPHA_CHANNEL_NONE, 0, &alloc_context, filter);
        assert(res);
    }

    ///ditto
    void resizeImage_sRGBWithAlpha(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        if (sameSizeResize(input, output))
            return;
        stbir_filter filter = STBIR_FILTER_MKS_2013_86;
        int res = stbir_resize_uint8_srgb(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                          cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch,
                                          4, 3, 0, &alloc_context, filter);
        assert(res);
    }

    ///ditto
    void resizeImageDiffuseWithAlphaPremul(ImageRef!RGBA16 input, ImageRef!RGBA16 output)
    {
        // Intended for 16-bit image in sRGB, with premultipled alpha.
        if (sameSizeResize(input, output))
            return;
        stbir_filter filter = STBIR_FILTER_MKS_2013_86;
        int flags = STBIR_FLAG_ALPHA_PREMULTIPLIED;

        int res = stbir_resize_uint16_generic(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                               cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch,
                                              4, 3, flags,
                                              STBIR_EDGE_CLAMP, filter, STBIR_COLORSPACE_LINEAR, // for some reason, STBIR_COLORSPACE_SRGB with uint16 creates artifacts
                                              &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageDiffuse(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        if (sameSizeResize(input, output))
            return;
        // Note: as the primary use case is downsampling, it was found it is helpful to have a relatively sharp filter
        // since the diffuse map may contain text, and downsampling text is too blurry as of today.
        stbir_filter filter = STBIR_FILTER_MKS_2013_86;
        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }

    // Note: no special treatment for material images
    // No particular quality gain when using lanczos 3.
    alias resizeImageMaterial = resizeImageGeneric;

    void resizeImageMaterialWithAlphaPremul(ImageRef!RGBA16 input, ImageRef!RGBA16 output)
    {
        // Intended for 16-bit image that contains Material with premultipled alpha.
        if (sameSizeResize(input, output))
            return;
        stbir_filter filter = STBIR_FILTER_DEFAULT;
        int flags = STBIR_FLAG_ALPHA_PREMULTIPLIED;

        int res = stbir_resize_uint16_generic(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                              cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch,
                                              4, 3, flags,
                                              STBIR_EDGE_CLAMP, filter, STBIR_COLORSPACE_LINEAR, // for some reason, STBIR_COLORSPACE_SRGB with uint16 creates artifacts
                                              &alloc_context);
        assert(res);
    }

    void resizeImageDepthWithAlphaPremul(ImageRef!RGBA16 input, ImageRef!RGBA16 output)
    {
        // Intended for 16-bit image that contains Depth in the RGB channels (or just one), with premultipled alpha.
        // Note: this function is intended for those images that contain depth despite having 4 channels.
        if (sameSizeResize(input, output))
            return;

        stbir_filter filter = STBIR_FILTER_MKS_2021;
        int flags = STBIR_FLAG_ALPHA_PREMULTIPLIED;
        int res = stbir_resize_uint16_generic(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                              cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch,
                                              4, 3, flags,
                                              STBIR_EDGE_CLAMP, filter, STBIR_COLORSPACE_LINEAR,
                                              &alloc_context);
        assert(res);
    }

private:

    STBAllocatorContext alloc_context;
}


private:


bool sameSizeResize(COLOR)(ImageRef!COLOR input, ImageRef!COLOR output) nothrow @nogc
{
    if (input.w == output.w && input.h == output.h)
    {
        // Just copy the pixels over
        input.blitTo(output);
        return true;
    }
    else
        return false;


}