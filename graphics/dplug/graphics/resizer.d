/**
* 
* AVIR Copyright (c) 2015-2020 Aleksey Vaneev
*
* Translation of lancir.h
*
* @section intro_sec Introduction
*
* Description is available at https://github.com/avaneev/avir
*
*
* AVIR License Agreement
*
* The MIT License (MIT)
*
* Copyright (c) 2015-2020 Aleksey Vaneev
*
* Permission is hereby granted, free of charge, to any person obtaining a
* copy of this software and associated documentation files (the "Software"),
* to deal in the Software without restriction, including without limitation
* the rights to use, copy, modify, merge, publish, distribute, sublicense,
* and/or sell copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
* DEALINGS IN THE SOFTWARE.
*/
/**
Resizer ported to D from C++, based on https://github.com/avaneev/avir "lancir" method.
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
        stbir_filter filter = STBIR_FILTER_DEFAULT;
        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageSmoother(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        // suitable when depth is encoded in a RGB8 triplet, such as in UIImageKnob
        stbir_filter filter = STBIR_FILTER_CUBICBSPLINE;
        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageGeneric(ImageRef!L16 input, ImageRef!L16 output)
    {
        // Note: smoothing depth while resampling avoids some depth artifacts.
        stbir_filter filter = STBIR_FILTER_DEFAULT;
        int res = stbir_resize_uint16(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                      cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch, 1, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageDepth(ImageRef!L16 input, ImageRef!L16 output)
    {
        // If too smooth, downsampling depth could make too blurry transitions.
        // So we use the normal fltrer again.
        stbir_filter filter = STBIR_FILTER_DEFAULT;
        int res = stbir_resize_uint16(cast(const(ushort*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                      cast(      ushort* )output.pixels, output.w, output.h, cast(int)output.pitch, 1, filter, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageCoverage(ImageRef!L8 input, ImageRef!L8 output)
    {
        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 1, STBIR_FILTER_DEFAULT, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImage_sRGBNoAlpha(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        int res = stbir_resize_uint8_srgb(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                          cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch,
                                          4, STBIR_ALPHA_CHANNEL_NONE, 0, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImage_sRGBWithAlpha(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        int res = stbir_resize_uint8_srgb(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                          cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch,
                                          4, 3, 0, &alloc_context);
        assert(res);
    }

    ///ditto
    void resizeImageDiffuse(ImageRef!RGBA input, ImageRef!RGBA output)
    {
        // Note: as the primary use case is downsampling, it was found it is helpful to have a relatively sharp filter
        // since the diffuse map may contain text, and downsampling text is too blurry as of today.
        stbir_filter filter = STBIR_FILTER_CATMULLROM;
        int res = stbir_resize_uint8(cast(const(ubyte*))input.pixels, input.w, input.h, cast(int)input.pitch,
                                     cast(      ubyte* )output.pixels, output.w, output.h, cast(int)output.pitch, 4, filter, &alloc_context);
        assert(res);
    }


   // Note: no special treatment for material images
    alias resizeImageMaterial = resizeImageGeneric;

private:

    STBAllocatorContext alloc_context;
}
