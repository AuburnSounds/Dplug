/// PNG image loading.
/// D translation of stb_image-2.27
/// This port only support PNG loading, 8-bit and 16-bit.
module dplug.graphics.pngload;


/* stb_image - v2.27 - public domain image loader - http://nothings.org/stb
no warranty implied; use at your own risk


QUICK NOTES:
Primarily of interest to game developers and other people who can
avoid problematic images and only need the trivial interface

JPEG baseline & progressive (12 bpc/arithmetic not supported, same as stock IJG lib)
PNG 1/2/4/8/16-bit-per-channel

TGA (not sure what subset, if a subset)
BMP non-1bpp, non-RLE
PSD (composited view only, no extra channels, 8/16 bit-per-channel)

GIF (*comp always reports as 4-channel)
HDR (radiance rgbE format)
PIC (Softimage PIC)
PNM (PPM and PGM binary only)

Animated GIF still needs a proper API, but here's one way to do it:
http://gist.github.com/urraka/685d9a6340b26b830d49

- decode from memory
- decode from arbitrary I/O callbacks
- SIMD acceleration on x86/x64 (SSE2) and ARM (NEON)

Full documentation under "DOCUMENTATION" below.


LICENSE

See end of file for license information.

RECENT REVISION HISTORY:

2.27  (2021-07-11) document stbi_info better, 16-bit PNM support, bug fixes
2.26  (2020-07-13) many minor fixes
2.25  (2020-02-02) fix warnings
2.24  (2020-02-02) fix warnings; thread-local failure_reason and flip_vertically
2.23  (2019-08-11) fix clang static analysis warning
2.22  (2019-03-04) gif fixes, fix warnings
2.21  (2019-02-25) fix typo in comment
2.20  (2019-02-07) support utf8 filenames in Windows; fix warnings and platform ifdefs
2.19  (2018-02-11) fix warning
2.18  (2018-01-30) fix warnings
2.17  (2018-01-29) bugfix, 1-bit BMP, 16-bitness query, fix warnings
2.16  (2017-07-23) all functions have 16-bit variants; optimizations; bugfixes
2.15  (2017-03-18) fix png-1,2,4; all Imagenet JPGs; no runtime SSE detection on GCC
2.14  (2017-03-03) remove deprecated STBI_JPEG_OLD; fixes for Imagenet JPGs
2.13  (2016-12-04) experimental 16-bit API, only for PNG so far; fixes
2.12  (2016-04-02) fix typo in 2.11 PSD fix that caused crashes
2.11  (2016-04-02) 16-bit PNGS; enable SSE2 in non-gcc x64
RGB-format JPEG; remove white matting in PSD;
allocate large structures on the stack;
correct channel count for PNG & BMP
2.10  (2016-01-22) avoid warning introduced in 2.09
2.09  (2016-01-16) 16-bit TGA; comments in PNM files; STBI_REALLOC_SIZED

See end of file for full revision history.


============================    Contributors    =========================

Image formats                          Extensions, features
Sean Barrett (jpeg, png, bmp)          Jetro Lauha (stbi_info)
Nicolas Schulz (hdr, psd)              Martin "SpartanJ" Golini (stbi_info)
Jonathan Dummer (tga)                  James "moose2000" Brown (iPhone PNG)
Jean-Marc Lienher (gif)                Ben "Disch" Wenger (io callbacks)
Tom Seddon (pic)                       Omar Cornut (1/2/4-bit PNG)
Thatcher Ulrich (psd)                  Nicolas Guillemot (vertical flip)
Ken Miller (pgm, ppm)                  Richard Mitton (16-bit PSD)
github:urraka (animated gif)           Junggon Kim (PNM comments)
Christopher Forseth (animated gif)     Daniel Gibson (16-bit TGA)
socks-the-fox (16-bit PNG)
Jeremy Sawicki (handle all ImageNet JPGs)
Optimizations & bugfixes                  Mikhail Morozov (1-bit BMP)
Fabian "ryg" Giesen                    Anael Seghezzi (is-16-bit query)
Arseny Kapoulkine                      Simon Breuss (16-bit PNM)
John-Mark Allen
Carmelo J Fdez-Aguera

Bug & warning fixes
Marc LeBlanc            David Woo          Guillaume George     Martins Mozeiko
Christpher Lloyd        Jerry Jansson      Joseph Thomson       Blazej Dariusz Roszkowski
Phil Jordan                                Dave Moore           Roy Eltham
Hayaki Saito            Nathan Reed        Won Chun
Luke Graham             Johan Duparc       Nick Verigakis       the Horde3D community
Thomas Ruf              Ronny Chevalier                         github:rlyeh
Janez Zemva             John Bartholomew   Michal Cichon        github:romigrou
Jonathan Blow           Ken Hamada         Tero Hanninen        github:svdijk
Eugene Golushkov        Laurent Gomila     Cort Stratton        github:snagar
Aruelien Pocheville     Sergio Gonzalez    Thibault Reuille     github:Zelex
Cass Everitt            Ryamond Barbiero                        github:grim210
Paul Du Bois            Engin Manap        Aldo Culquicondor    github:sammyhw
Philipp Wiesemann       Dale Weiler        Oriol Ferrer Mesia   github:phprus
Josh Tobin                                 Matthew Gregan       github:poppolopoppo
Julian Raschke          Gregory Mullen     Christian Floisand   github:darealshinji
Baldur Karlsson         Kevin Schmidt      JR Smith             github:Michaelangel007
Brad Weinberger    Matvey Cherevko      github:mosra
Luca Sas                Alexander Veselov  Zack Middleton       [reserved]
Ryan C. Gordon          [reserved]                              [reserved]
DO NOT ADD YOUR NAME HERE

Jacko Dirks

To add your name to the credits, pick a random blank space in the middle and fill it.
80% of merge conflicts on stb PRs are due to people adding their name at the end
of the credits.
*/

import core.stdc.string: memcpy, memset;
import core.atomic;

import std.math: ldexp, pow, abs;
import dplug.core.vec;

nothrow @nogc:

import inteli.emmintrin;
enum stbi__sse2_available = true; // because always available with intel-intrinsics

// DOCUMENTATION
//
// Limitations:
//    - no 12-bit-per-channel JPEG
//    - no JPEGs with arithmetic coding
//    - GIF always returns *comp=4
//
// Basic usage (see HDR discussion below for HDR usage):
//    int x,y,n;
//    unsigned char *data = stbi_load(filename, &x, &y, &n, 0);
//    // ... process data if not null ...
//    // ... x = width, y = height, n = # 8-bit components per pixel ...
//    // ... replace '0' with '1'..'4' to force that many components per pixel
//    // ... but 'n' will always be the number that it would have been if you said 0
//    stbi_image_free(data)
//
// Standard parameters:
//    int *x                 -- outputs image width in pixels
//    int *y                 -- outputs image height in pixels
//    int *channels_in_file  -- outputs # of image components in image file
//    int desired_channels   -- if non-zero, # of image components requested in result
//
// The return value from an image loader is an 'unsigned char *' which points
// to the pixel data, or null on an allocation failure or if the image is
// corrupt or invalid. The pixel data consists of *y scanlines of *x pixels,
// with each pixel consisting of N interleaved 8-bit components; the first
// pixel pointed to is top-left-most in the image. There is no padding between
// image scanlines or between pixels, regardless of format. The number of
// components N is 'desired_channels' if desired_channels is non-zero, or
// *channels_in_file otherwise. If desired_channels is non-zero,
// *channels_in_file has the number of components that _would_ have been
// output otherwise. E.g. if you set desired_channels to 4, you will always
// get RGBA output, but you can check *channels_in_file to see if it's trivially
// opaque because e.g. there were only 3 channels in the source image.
//
// An output image with N components has the following components interleaved
// in this order in each pixel:
//
//     N=#comp     components
//       1           grey
//       2           grey, alpha
//       3           red, green, blue
//       4           red, green, blue, alpha
//
// If image loading fails for any reason, the return value will be null,
// and *x, *y, *channels_in_file will be unchanged. The function
// stbi_failure_reason() can be queried for an extremely brief, end-user
// unfriendly explanation of why the load failed. Define STBI_NO_FAILURE_STRINGS
// to avoid compiling these strings at all, and STBI_FAILURE_USERMSG to get slightly
// more user-friendly ones.
//
// Paletted PNG, BMP, GIF, and PIC images are automatically depalettized.
//
// To query the width, height and component count of an image without having to
// decode the full file, you can use the stbi_info family of functions:
//
//   int x,y,n,ok;
//   ok = stbi_info(filename, &x, &y, &n);
//   // returns ok=1 and sets x, y, n if image is a supported format,
//   // 0 otherwise.
//
// Note that stb_image pervasively uses ints in its public API for sizes,
// including sizes of memory buffers. This is now part of the API and thus
// hard to change without causing breakage. As a result, the various image
// loaders all have certain limits on image size; these differ somewhat
// by format but generally boil down to either just under 2GB or just under
// 1GB. When the decoded image would be larger than this, stb_image decoding
// will fail.
//
// Additionally, stb_image will reject image files that have any of their
// dimensions set to a larger value than the configurable STBI_MAX_DIMENSIONS,
// which defaults to 2**24 = 16777216 pixels. Due to the above memory limit,
// the only way to have an image with such dimensions load correctly
// is for it to have a rather extreme aspect ratio. Either way, the
// assumption here is that such larger images are likely to be malformed
// or malicious. If you do need to load an image with individual dimensions
// larger than that, and it still fits in the overall size limit, you can
// #define STBI_MAX_DIMENSIONS on your own to be something larger.
//
//
// Philosophy
//
// stb libraries are designed with the following priorities:
//
//    1. easy to use
//    2. easy to maintain
//    3. good performance
//
// Sometimes I let "good performance" creep up in priority over "easy to maintain",
// and for best performance I may provide less-easy-to-use APIs that give higher
// performance, in addition to the easy-to-use ones. Nevertheless, it's important
// to keep in mind that from the standpoint of you, a client of this library,
// all you care about is #1 and #3, and stb libraries DO NOT emphasize #3 above all.
//
// Some secondary priorities arise directly from the first two, some of which
// provide more explicit reasons why performance can't be emphasized.
//
//    - Portable ("ease of use")
//    - Small source code footprint ("easy to maintain")
//    - No dependencies ("ease of use")
//
// ===========================================================================
//
// I/O callbacks
//
// I/O callbacks allow you to read from arbitrary sources, like packaged
// files or some other source. Data read from callbacks are processed
// through a small internal buffer (currently 128 bytes) to try to reduce
// overhead.
//
// The three functions you must define are "read" (reads some bytes of data),
// "skip" (skips some bytes of data), "eof" (reports if the stream is at the end).
//
// ===========================================================================
//
// SIMD support
//
// The JPEG decoder will try to automatically use SIMD kernels on x86 when
// supported by the compiler. For ARM Neon support, you must explicitly
// request it.
//
// (The old do-it-yourself SIMD API is no longer supported in the current
// code.)
//
// On x86, SSE2 will automatically be used when available based on a run-time
// test; if not, the generic C versions are used as a fall-back. On ARM targets,
// the typical path is to have separate builds for NEON and non-NEON devices
// (at least this is true for iOS and Android). Therefore, the NEON support is
// toggled by a build flag: define STBI_NEON to get NEON loops.
//
// If for some reason you do not want to use any of SIMD code, or if
// you have issues compiling it, you can disable it entirely by
// defining STBI_NO_SIMD.
//
// ===========================================================================
//
// HDR image support   (disable by defining STBI_NO_HDR)
//
// stb_image supports loading HDR images in general, and currently the Radiance
// .HDR file format specifically. You can still load any file through the existing
// interface; if you attempt to load an HDR file, it will be automatically remapped
// to LDR, assuming gamma 2.2 and an arbitrary scale factor defaulting to 1;
// both of these constants can be reconfigured through this interface:
//
//     stbi_hdr_to_ldr_gamma(2.2f);
//     stbi_hdr_to_ldr_scale(1.0f);
//
// (note, do not use _inverse_ constants; stbi_image will invert them
// appropriately).
//
// Additionally, there is a new, parallel interface for loading files as
// (linear) floats to preserve the full dynamic range:
//
//    float *data = stbi_loadf(filename, &x, &y, &n, 0);
//
// If you load LDR images through this interface, those images will
// be promoted to floating point values, run through the inverse of
// constants corresponding to the above:
//
//     stbi_ldr_to_hdr_scale(1.0f);
//     stbi_ldr_to_hdr_gamma(2.2f);
//
// Finally, given a filename (or an open file or memory block--see header
// file for details) containing image data, you can query for the "most
// appropriate" interface to use (that is, whether the image is HDR or
// not), using:
//
//     stbi_is_hdr(char *filename);
//
// ===========================================================================
//
// iPhone PNG support:
//
// We optionally support converting iPhone-formatted PNGs (which store
// premultiplied BGRA) back to RGB, even though they're internally encoded
// differently. To enable this conversion, call
// stbi_convert_iphone_png_to_rgb(1).
//
// Call stbi_set_unpremultiply_on_load(1) as well to force a divide per
// pixel to remove any premultiplied alpha *only* if the image file explicitly
// says there's premultiplied data (currently only happens in iPhone images,
// and only if iPhone convert-to-rgb processing is on).
//
// ===========================================================================
//
// ADDITIONAL CONFIGURATION
//
//  - You can suppress implementation of any of the decoders to reduce
//    your code footprint by #defining one or more of the following
//    symbols before creating the implementation.
//
//        STBI_NO_JPEG
//        STBI_NO_PNG
//        STBI_NO_BMP
//        STBI_NO_PSD
//        STBI_NO_TGA
//        STBI_NO_GIF
//        STBI_NO_HDR
//        STBI_NO_PIC
//        STBI_NO_PNM   (.ppm and .pgm)
//
//
//   - If you use STBI_NO_PNG (or _ONLY_ without PNG), and you still
//     want the zlib decoder to be available, #define STBI_SUPPORT_ZLIB
//
//  - If you define STBI_MAX_DIMENSIONS, stb_image will reject images greater
//    than that size (in either width or height) without further processing.
//    This is to let programs in the wild set an upper bound to prevent
//    denial-of-service attacks on untrusted data, as one could generate a
//    valid image of gigantic dimensions and force stb_image to allocate a
//    huge block of memory and spend disproportionate time decoding it. By
//    default this is set to (1 << 24), which is 16777216, but that's still
//    very big.


version = decodePNG;
//version = decodeBMP;
//version = decodePSD;
//version = decodeTGA;
//version = decodeGIF;
//version = decodeHDR;
//version = decodePIC;
//version = decodePNM;

//version = enableLinear;  // STBI_NO_LINEAR
//version = enableFailureStrings;
//version = enableFailureStringsUser; // prettier error messages

enum STBI_VERSION = 1;

enum
{
    STBI_default = 0, // only used for desired_channels

    STBI_grey       = 1,
    STBI_grey_alpha = 2,
    STBI_rgb        = 3,
    STBI_rgb_alpha  = 4
}

alias stbi_uc = ubyte; 
alias stbi_us = ushort;

//////////////////////////////////////////////////////////////////////////////
//
// PRIMARY API - works on images of any type
//

//
// load image by filename, open file, or memory buffer
//

struct stbi_io_callbacks
{
    nothrow @nogc:
    int function(void *user,char *data,int size) read;   // fill 'data' with 'size' bytes.  return number of bytes actually read
    void function(void *user,int n) skip;                // skip the next 'n' bytes, or 'unget' the last -n bytes if negative
    int function(void *user) eof;                        // returns nonzero if we are at end of file/data
}

// <Implementation>

version = STBI_NO_THREAD_LOCALS;

alias stbi__uint16 = ushort;
alias stbi__int16 = short;
alias stbi__uint32 = uint;
alias stbi__int32 = int;

uint stbi_lrot(uint x, int y)
{
    return (x << y) | (x >> (-y & 31));
}

void* STBI_MALLOC(size_t size)
{
    return alignedMalloc(size, 1);
}

void* STBI_REALLOC(void* p, size_t new_size)
{
    return alignedRealloc(p, new_size, 1);
}

void* STBI_REALLOC_SIZED(void *ptr, size_t old_size, size_t new_size)
{
    return alignedRealloc(ptr, new_size, 1);
}

void STBI_FREE(void* p)
{
    alignedFree(p, 1);
}

//alias STBI_MALLOC = malloc;
//alias STBI_REALLOC = realloc;
//alias STBI_FREE = free;

enum STBI_MAX_DIMENSIONS = (1 << 24);

///////////////////////////////////////////////
//
//  stbi__context struct and start_xxx functions

// stbi__context structure is our basic context used by all images, so it
// contains all the IO context, plus some basic image information
struct stbi__context
{
    stbi__uint32 img_x, img_y;
    int img_n, img_out_n;

    stbi_io_callbacks io;
    void *io_user_data;

    int read_from_callbacks;
    int buflen;
    stbi_uc[128] buffer_start;
    int callback_already_read;

    stbi_uc *img_buffer, img_buffer_end;
    stbi_uc *img_buffer_original, img_buffer_original_end;
}


// initialize a memory-decode context
void stbi__start_mem(stbi__context *s, const(stbi_uc)* buffer, int len)
{
    s.io.read = null;
    s.read_from_callbacks = 0;
    s.callback_already_read = 0;
    s.img_buffer = s.img_buffer_original = cast(stbi_uc *) buffer;
    s.img_buffer_end = s.img_buffer_original_end = cast(stbi_uc *) buffer+len;
}

// initialize a callback-based context
void stbi__start_callbacks(stbi__context *s, stbi_io_callbacks *c, void *user)
{
    s.io = *c;
    s.io_user_data = user;
    s.buflen = s.buffer_start.sizeof;
    s.read_from_callbacks = 1;
    s.callback_already_read = 0;
    s.img_buffer = s.img_buffer_original = s.buffer_start.ptr;
    stbi__refill_buffer(s);
    s.img_buffer_original_end = s.img_buffer_end;
}

void stbi__rewind(stbi__context *s)
{
    // conceptually rewind SHOULD rewind to the beginning of the stream,
    // but we just rewind to the beginning of the initial buffer, because
    // we only use it after doing 'test', which only ever looks at at most 92 bytes
    s.img_buffer = s.img_buffer_original;
    s.img_buffer_end = s.img_buffer_original_end;
}

enum
{
    STBI_ORDER_RGB,
    STBI_ORDER_BGR
}

struct stbi__result_info
{
    int bits_per_channel;
    int num_channels;
    int channel_order;
}

version(enableFailureStrings)
{
    // Note: this is a global, so if multiple image loads happen at once, the reason given might be racey.
    __gshared const(char)* stbi__g_failure_reason;

    const(char*) stbi_failure_reason()
    {
        return stbi__g_failure_reason;
    }

    int stbi_err(const(char)* str)
    {
        stbi__g_failure_reason = str;
        return 0;
    }
}

alias stbi__malloc = STBI_MALLOC;

// stb_image uses ints pervasively, including for offset calculations.
// therefore the largest decoded image size we can support with the
// current code, even on 64-bit targets, is INT_MAX. this is not a
// significant limitation for the intended use case.
//
// we do, however, need to make sure our size calculations don't
// overflow. hence a few helper functions for size calculations that
// multiply integers together, making sure that they're non-negative
// and no overflow occurs.

// return 1 if the sum is valid, 0 on overflow.
// negative terms are considered invalid.
int stbi__addsizes_valid(int a, int b)
{
    if (b < 0) return 0;
    // now 0 <= b <= INT_MAX, hence also
    // 0 <= INT_MAX - b <= INTMAX.
    // And "a + b <= INT_MAX" (which might overflow) is the
    // same as a <= INT_MAX - b (no overflow)
    return a <= int.max - b;
}

// returns 1 if the product is valid, 0 on overflow.
// negative factors are considered invalid.
int stbi__mul2sizes_valid(int a, int b)
{
    if (a < 0 || b < 0) return 0;
    if (b == 0) return 1; // mul-by-0 is always safe
    // portable way to check for no overflows in a*b
    return a <= int.max/b;
}

int stbi__mad2sizes_valid(int a, int b, int add)
{
    return stbi__mul2sizes_valid(a, b) && stbi__addsizes_valid(a*b, add);
}

// returns 1 if "a*b*c + add" has no negative terms/factors and doesn't overflow
int stbi__mad3sizes_valid(int a, int b, int c, int add)
{
    return stbi__mul2sizes_valid(a, b) && stbi__mul2sizes_valid(a*b, c) &&
        stbi__addsizes_valid(a*b*c, add);
}

// returns 1 if "a*b*c*d + add" has no negative terms/factors and doesn't overflow
int stbi__mad4sizes_valid(int a, int b, int c, int d, int add)
{
    return stbi__mul2sizes_valid(a, b) && stbi__mul2sizes_valid(a*b, c) &&
        stbi__mul2sizes_valid(a*b*c, d) && stbi__addsizes_valid(a*b*c*d, add);
}

void *stbi__malloc_mad2(int a, int b, int add)
{
    if (!stbi__mad2sizes_valid(a, b, add)) return null;
    return stbi__malloc(a*b + add);
}

void *stbi__malloc_mad3(int a, int b, int c, int add)
{
    if (!stbi__mad3sizes_valid(a, b, c, add)) return null;
    return stbi__malloc(a*b*c + add);
}

void *stbi__malloc_mad4(int a, int b, int c, int d, int add)
{
    if (!stbi__mad4sizes_valid(a, b, c, d, add)) return null;
    return stbi__malloc(a*b*c*d + add);
}

// stbi__err - error

version(enableFailureStrings)
{
    int stbi__err(const(char)* msg, const(char)* msgUser)
    {
        return stbi_err(msg);
    }
}
else version(enableFailureStringsUser)
{
    int stbi__err(const(char)* msg, const(char)* msgUser)
    {
        return stbi_err(msgUser);
    }
}
else
{
    deprecated int stbi__err(const(char)* msg, const(char)* msgUser)
    {
        return 0;
    }
}

// stbi__errpf - error returning pointer to float
// stbi__errpuc - error returning pointer to unsigned char
deprecated float* stbi__errpf(const(char)* msg, const(char)* msgUser)
{
    return cast(float*) (cast(size_t) stbi__err(msg, msgUser));
}

deprecated ubyte* stbi__errpuc(const(char)* msg, const(char)* msgUser)
{
    return cast(ubyte*) (cast(size_t) stbi__err(msg, msgUser));
}

void stbi_image_free(void *retval_from_stbi_load) @trusted // TODO: make it @safe by changing stbi_load to return a slice
{
    STBI_FREE(retval_from_stbi_load);
}

void *stbi__load_main(stbi__context *s, int *x, int *y, int *comp, int req_comp, stbi__result_info *ri, int bpc)
{
    memset(ri, 0, (*ri).sizeof); // make sure it's initialized if we add new fields
    ri.bits_per_channel = 8; // default is 8 so most paths don't have to be changed
    ri.channel_order = STBI_ORDER_RGB; // all current input & output are this, but this is here so we can add BGR order
    ri.num_channels = 0;

    // test the formats with a very explicit header first (at least a FOURCC
    // or distinctive magic number first)
    version(decodePNG)
    {
        if (stbi__png_test(s))  return stbi__png_load(s,x,y,comp,req_comp, ri);
    }
    return null;
}

stbi_uc *stbi__convert_16_to_8(stbi__uint16 *orig, int w, int h, int channels)
{
    int img_len = w * h * channels;
    stbi_uc *reduced;

    reduced = cast(stbi_uc *) stbi__malloc(img_len);
    if (reduced == null) 
        return null;

    for (int i = 0; i < img_len; ++i)
        reduced[i] = cast(stbi_uc)((orig[i] >> 8) & 0xFF); // top half of each byte is sufficient approx of 16.8 bit scaling

    STBI_FREE(orig);
    return reduced;
}

stbi__uint16 *stbi__convert_8_to_16(stbi_uc *orig, int w, int h, int channels)
{
    int i;
    int img_len = w * h * channels;
    stbi__uint16 *enlarged;

    enlarged = cast(stbi__uint16 *) stbi__malloc(img_len*2);
    if (enlarged == null) 
        return null;

    for (i = 0; i < img_len; ++i)
        enlarged[i] = (orig[i] << 8) + orig[i]; // replicate to high and low byte, maps 0.0, 255.0xffff

    STBI_FREE(orig);
    return enlarged;
}


ubyte *stbi__load_and_postprocess_8bit(stbi__context *s, int *x, int *y, int *comp, int req_comp)
{
    stbi__result_info ri;
    void *result = stbi__load_main(s, x, y, comp, req_comp, &ri, 8);

    if (result == null)
        return null;

    // it is the responsibility of the loaders to make sure we get either 8 or 16 bit.
    assert(ri.bits_per_channel == 8 || ri.bits_per_channel == 16);

    if (ri.bits_per_channel != 8) {
        result = stbi__convert_16_to_8(cast(stbi__uint16 *) result, *x, *y, req_comp == 0 ? *comp : req_comp);
        ri.bits_per_channel = 8;
    }

    // @TODO: move stbi__convert_format to here

    return cast(ubyte*) result;
}

stbi__uint16 *stbi__load_and_postprocess_16bit(stbi__context *s, int *x, int *y, int *comp, int req_comp)
{
    stbi__result_info ri;
    void *result = stbi__load_main(s, x, y, comp, req_comp, &ri, 16);

    if (result == null)
        return null;

    // it is the responsibility of the loaders to make sure we get either 8 or 16 bit.
    assert(ri.bits_per_channel == 8 || ri.bits_per_channel == 16);

    if (ri.bits_per_channel != 16) {
        result = stbi__convert_8_to_16(cast(stbi_uc *) result, *x, *y, req_comp == 0 ? *comp : req_comp);
        ri.bits_per_channel = 16;
    }

    return cast(stbi__uint16 *) result;
}

void stbi__float_postprocess(float *result, int *x, int *y, int *comp, int req_comp)
{
}

stbi_us *stbi_load_16_from_memory(const(stbi_uc)*buffer, int len, int *x, int *y, int *channels_in_file, int desired_channels)
{
    stbi__context s;
    stbi__start_mem(&s,buffer,len);
    return stbi__load_and_postprocess_16bit(&s,x,y,channels_in_file,desired_channels);
}

stbi_us *stbi_load_16_from_callbacks(const(stbi_io_callbacks)*clbk, void *user, int *x, int *y, int *channels_in_file, int desired_channels)
{
    stbi__context s;
    stbi__start_callbacks(&s, cast(stbi_io_callbacks *)clbk, user); // const_cast here
    return stbi__load_and_postprocess_16bit(&s,x,y,channels_in_file,desired_channels);
}

stbi_uc *stbi_load_from_memory(const(stbi_uc)*buffer, int len, int *x, int *y, int *comp, int req_comp)
{
    stbi__context s;
    stbi__start_mem(&s,buffer,len);
    return stbi__load_and_postprocess_8bit(&s,x,y,comp,req_comp);
}

stbi_uc *stbi_load_from_callbacks(const(stbi_io_callbacks)*clbk, void *user, int *x, int *y, int *comp, int req_comp)
{
    stbi__context s;
    stbi__start_callbacks(&s, cast(stbi_io_callbacks *) clbk, user); // const_cast here
    return stbi__load_and_postprocess_8bit(&s,x,y,comp,req_comp);
}

version(enableLinear)
{
    __gshared stbi__l2h_gamma = 2.2f;
    __gshared stbi__l2h_scale = 1.0f;

    void stbi_ldr_to_hdr_gamma(float gamma) 
    { 
        atomicStore(stbi__l2h_gamma, gamma); 
    }

    void stbi_ldr_to_hdr_scale(float scale) 
    { 
        atomicStore(stbi__l2h_scale, scale);
    }
}


shared(float) stbi__h2l_gamma_i = 1.0f / 2.2f, 
    stbi__h2l_scale_i = 1.0f;

void stbi_hdr_to_ldr_gamma(float gamma)
{
    atomicStore(stbi__h2l_gamma_i, 1 / gamma); 
}

void stbi_hdr_to_ldr_scale(float scale)
{ 
    atomicStore(stbi__h2l_scale_i, 1 / scale); 
}


//////////////////////////////////////////////////////////////////////////////
//
// Common code used by all image loaders
//

enum
{
    STBI__SCAN_load = 0,
    STBI__SCAN_type,
    STBI__SCAN_header
}

void stbi__refill_buffer(stbi__context *s)
{
    int n = s.io.read(s.io_user_data, cast(char*)s.buffer_start, s.buflen);
    s.callback_already_read += cast(int) (s.img_buffer - s.img_buffer_original);
    if (n == 0) {
        // at end of file, treat same as if from memory, but need to handle case
        // where s.img_buffer isn't pointing to safe memory, e.g. 0-byte file
        s.read_from_callbacks = 0;
        s.img_buffer = s.buffer_start.ptr;
        s.img_buffer_end = s.buffer_start.ptr+1;
        *s.img_buffer = 0;
    } else {
        s.img_buffer = s.buffer_start.ptr;
        s.img_buffer_end = s.buffer_start.ptr + n;
    }
}

stbi_uc stbi__get8(stbi__context *s)
{
    if (s.img_buffer < s.img_buffer_end)
        return *s.img_buffer++;
    if (s.read_from_callbacks) {
        stbi__refill_buffer(s);
        return *s.img_buffer++;
    }
    return 0;
}

int stbi__at_eof(stbi__context *s) 
{
    if (s.io.read) 
    {
        if (!s.io.eof(s.io_user_data)) 
            return 0;
        // if feof() is true, check if buffer = end
        // special case: we've only got the special 0 character at the end
        if (s.read_from_callbacks == 0) 
            return 1;
    }
    return s.img_buffer >= s.img_buffer_end;
}

void stbi__skip(stbi__context *s, int n)
{
    if (n == 0) 
        return;  // already there!
    if (n < 0) 
    {
        s.img_buffer = s.img_buffer_end;
        return;
    }
    if (s.io.read) 
    {
        int blen = cast(int) (s.img_buffer_end - s.img_buffer);
        if (blen < n) 
        {
            s.img_buffer = s.img_buffer_end;
            s.io.skip(s.io_user_data, n - blen);
            return;
        }
    }
    s.img_buffer += n;
}

int stbi__getn(stbi__context *s, stbi_uc *buffer, int n)
{
    if (s.io.read) 
    {
        int blen = cast(int) (s.img_buffer_end - s.img_buffer);
        if (blen < n) 
        {
            int res, count;
            memcpy(buffer, s.img_buffer, blen);
            count = s.io.read(s.io_user_data, cast(char*) buffer + blen, n - blen);
            res = (count == (n-blen));
            s.img_buffer = s.img_buffer_end;
            return res;
        }
    }

    if (s.img_buffer+n <= s.img_buffer_end) 
    {
        memcpy(buffer, s.img_buffer, n);
        s.img_buffer += n;
        return 1;
    } 
    else
        return 0;
}

int stbi__get16be(stbi__context *s)
{
    int z = stbi__get8(s);
    return (z << 8) + stbi__get8(s);
}

stbi__uint32 stbi__get32be(stbi__context *s)
{
    stbi__uint32 z = stbi__get16be(s);
    return (z << 16) + stbi__get16be(s);
}

int stbi__get16le(stbi__context *s)
{
    int z = stbi__get8(s);
    return z + (stbi__get8(s) << 8);
}

stbi__uint32 stbi__get32le(stbi__context *s)
{
    stbi__uint32 z = stbi__get16le(s);
    z += cast(stbi__uint32)stbi__get16le(s) << 16;
    return z;
}

ubyte STBI__BYTECAST(T)(T x)
{
    return cast(ubyte)(x & 255); 
}

//////////////////////////////////////////////////////////////////////////////
//
//  generic converter from built-in img_n to req_comp
//    individual types do this automatically as much as possible (e.g. jpeg
//    does all cases internally since it needs to colorspace convert anyway,
//    and it never has alpha, so very few cases ). png can automatically
//    interleave an alpha=255 channel, but falls back to this for other cases
//
//  assume data buffer is malloced, so malloc a new one and free that one
//  only failure mode is malloc failing

stbi_uc stbi__compute_y(int r, int g, int b)
{
    return cast(ubyte)(((r * 77) + (g * 150) +  (29 * b)) >> 8);
}

ubyte *stbi__convert_format(ubyte *data, int img_n, int req_comp, uint x, uint y)
{
    int i,j;
    ubyte *good;

    if (req_comp == img_n) 
        return data;
    assert(req_comp >= 1 && req_comp <= 4);

    good = cast(ubyte*) stbi__malloc_mad3(req_comp, x, y, 0);
    if (good == null) 
    {
        STBI_FREE(data);
        return null;
    }

    for (j = 0; j < cast(int) y; ++j) 
    {
        ubyte *src  = data + j * x * img_n   ;
        ubyte *dest = good + j * x * req_comp;

        // convert source image with img_n components to one with req_comp components;
        // avoid switch per pixel, so use switch per scanline and massive macros
        switch (img_n * 8 + req_comp) 
        {
            case 1 * 8 + 2:
                { 
                    for(i = x - 1; i >= 0; --i, src += 1, dest += 2)
                    {
                        dest[0] = src[0]; 
                        dest[1] = 255;
                    }
                } 
                break;
            case 1 * 8 + 3:
                { 
                    for(i = x - 1; i >= 0; --i, src += 1, dest += 3)
                    {
                        dest[0] = dest[1] = dest[2] = src[0];
                    }
                } 
                break;
            case 1 * 8 + 4:
                for(i = x - 1; i >= 0; --i, src += 1, dest += 4)
                { 
                    dest[0] = dest[1] = dest[2] = src[0]; 
                    dest[3] = 255;                     
                } 
                break;
            case 2 * 8 + 1:
                { 
                    for(i = x - 1; i >= 0; --i, src += 2, dest += 1)
                    {
                        dest[0] = src[0];
                    }
                } 
                break;
            case 2 * 8 + 3:
                { 
                    for(i = x - 1; i >= 0; --i, src += 2, dest += 3)
                    {
                        dest[0] = dest[1] = dest[2] = src[0]; 
                    }
                } 
                break;
            case 2 * 8 + 4:
                { 
                    for(i = x - 1; i >= 0; --i, src += 2, dest += 4)
                    {
                        dest[0] = dest[1] = dest[2] = src[0]; 
                        dest[3] = src[1]; 
                    }
                } 
                break;
            case 3 * 8 + 4:
                { 
                    for(i = x - 1; i >= 0; --i, src += 3, dest += 4)
                    {
                        dest[0] = src[0];
                        dest[1] = src[1];
                        dest[2] = src[2];
                        dest[3] = 255;
                    }
                } 
                break;
            case 3 * 8 + 1:
                { 
                    for(i = x - 1; i >= 0; --i, src += 3, dest += 1)
                    {
                        dest[0] = stbi__compute_y(src[0],src[1],src[2]); 
                    }
                } 
                break;
            case 3 * 8 + 2:
                { 
                    for(i = x - 1; i >= 0; --i, src += 3, dest += 2)
                    {
                        dest[0] = stbi__compute_y(src[0],src[1],src[2]);
                        dest[1] = 255;
                    }
                } 
                break;

            case 4 * 8 + 1:
                { 
                    for(i = x - 1; i >= 0; --i, src += 4, dest += 1)
                    {
                        dest[0] = stbi__compute_y(src[0],src[1],src[2]);
                    }
                }
                break;

            case 4 * 8 + 2:
                { 
                    for(i = x - 1; i >= 0; --i, src += 4, dest += 2)
                    {
                        dest[0] = stbi__compute_y(src[0],src[1],src[2]); 
                        dest[1] = src[3];
                    }
                }
                break;
            case 4 * 8 + 3:
                { 
                    for(i = x - 1; i >= 0; --i, src += 4, dest += 3)
                    {
                        dest[0] = src[0]; 
                        dest[1] = src[1]; 
                        dest[2] = src[2];        
                    }
                }
                break;
            default: 
                assert(0); 
        }
    }

    STBI_FREE(data);
    return good;
}

stbi__uint16 stbi__compute_y_16(int r, int g, int b)
{
    return cast(stbi__uint16) (((r*77) + (g*150) +  (29*b)) >> 8);
}

stbi__uint16* stbi__convert_format16(stbi__uint16 *data, int img_n, int req_comp, uint x, uint y)
{
    int i,j;
    stbi__uint16 *good;

    if (req_comp == img_n) 
        return data;
    assert(req_comp >= 1 && req_comp <= 4);

    good = cast(stbi__uint16 *) stbi__malloc(req_comp * x * y * 2);
    if (good == null) 
    {
        STBI_FREE(data);
        return null;
    }

    for (j = 0; j < cast(int) y; ++j) 
    {
        stbi__uint16 *src  = data + j * x * img_n   ;
        stbi__uint16 *dest = good + j * x * req_comp;

        // convert source image with img_n components to one with req_comp components;
        // avoid switch per pixel, so use switch per scanline and massive macros
        switch (img_n * 8 + req_comp) 
        {
            case 1 * 8 + 2:
                { 
                    for(i = x - 1; i >= 0; --i, src += 1, dest += 2)
                    {
                        dest[0] = src[0]; 
                        dest[1] = 0xffff;
                    }
                } 
                break;
            case 1 * 8 + 3:
                { 
                    for(i = x - 1; i >= 0; --i, src += 1, dest += 3)
                    {
                        dest[0] = dest[1] = dest[2] = src[0];
                    }
                } 
                break;
            case 1 * 8 + 4:
                for(i = x - 1; i >= 0; --i, src += 1, dest += 4)
                { 
                    dest[0] = dest[1] = dest[2] = src[0]; 
                    dest[3] = 0xffff;                     
                } 
                break;
            case 2 * 8 + 1:
                { 
                    for(i = x - 1; i >= 0; --i, src += 2, dest += 1)
                    {
                        dest[0] = src[0];
                    }
                } 
                break;
            case 2 * 8 + 3:
                { 
                    for(i = x - 1; i >= 0; --i, src += 2, dest += 3)
                    {
                        dest[0] = dest[1] = dest[2] = src[0]; 
                    }
                } 
                break;
            case 2 * 8 + 4:
                { 
                    for(i = x - 1; i >= 0; --i, src += 2, dest += 4)
                    {
                        dest[0] = dest[1] = dest[2] = src[0]; 
                        dest[3] = src[1]; 
                    }
                } 
                break;
            case 3 * 8 + 4:
                { 
                    for(i = x - 1; i >= 0; --i, src += 3, dest += 4)
                    {
                        dest[0] = src[0];
                        dest[1] = src[1];
                        dest[2] = src[2];
                        dest[3] = 0xffff;
                    }
                } 
                break;
            case 3 * 8 + 1:
                { 
                    for(i = x - 1; i >= 0; --i, src += 3, dest += 1)
                    {
                        dest[0] = stbi__compute_y_16(src[0],src[1],src[2]); 
                    }
                } 
                break;
            case 3 * 8 + 2:
                { 
                    for(i = x - 1; i >= 0; --i, src += 3, dest += 2)
                    {
                        dest[0] = stbi__compute_y_16(src[0],src[1],src[2]);
                        dest[1] = 0xffff;
                    }
                } 
                break;

            case 4 * 8 + 1:
                { 
                    for(i = x - 1; i >= 0; --i, src += 4, dest += 1)
                    {
                        dest[0] = stbi__compute_y_16(src[0],src[1],src[2]);
                    }
                }
                break;

            case 4 * 8 + 2:
                { 
                    for(i = x - 1; i >= 0; --i, src += 4, dest += 2)
                    {
                        dest[0] = stbi__compute_y_16(src[0],src[1],src[2]); 
                        dest[1] = src[3];
                    }
                }
                break;
            case 4 * 8 + 3:
                { 
                    for(i = x - 1; i >= 0; --i, src += 4, dest += 3)
                    {
                        dest[0] = src[0]; 
                        dest[1] = src[1]; 
                        dest[2] = src[2];        
                    }
                }
                break;
            default: 
                assert(0); 
        }   
    }

    STBI_FREE(data);
    return good;
}

version(enableLinear)
{
    float* stbi__ldr_to_hdr(stbi_uc *data, int x, int y, int comp)
    {
        int i,k,n;
        float *output;
        if (!data) return null;
        output = cast(float *) stbi__malloc_mad4(x, y, comp, float.sizeof, 0);
        if (output == null) 
        { 
            STBI_FREE(data); 
            return null;
        }
        // compute number of non-alpha components
        if (comp & 1) 
            n = comp; 
        else 
            n = comp - 1;
        for (i = 0; i < x*y; ++i) 
        {
            for (k = 0; k < n; ++k) 
            {
                output[i*comp + k] = cast(float) (pow(data[i*comp+k] / 255.0f, stbi__l2h_gamma) * stbi__l2h_scale);
            }
        }
        if (n < comp) 
        {
            for (i=0; i < x*y; ++i) 
            {
                output[i*comp + n] = data[i*comp + n] / 255.0f;
            }
        }
        STBI_FREE(data);
        return output;
    }
}

int stbi__float2int(float x)
{
    return cast(int)x;
}

// public domain zlib decode    v0.2  Sean Barrett 2006-11-18
//    simple implementation
//      - all input must be provided in an upfront buffer
//      - all output is written to a single output buffer (can malloc/realloc)
//    performance
//      - fast huffman

// fast-way is faster to check than jpeg huffman, but slow way is slower
enum STBI__ZFAST_BITS = 9; // accelerate all cases in default tables
enum STBI__ZFAST_MASK = ((1 << STBI__ZFAST_BITS) - 1);
enum STBI__ZNSYMS = 288; // number of symbols in literal/length alphabet

// zlib-style huffman encoding
// (jpegs packs from left, zlib from right, so can't share code)
struct stbi__zhuffman
{
    stbi__uint16[1 << STBI__ZFAST_BITS] fast;
    stbi__uint16[16] firstcode;
    int[17] maxcode;
    stbi__uint16[16] firstsymbol;
    stbi_uc[STBI__ZNSYMS]  size;
    stbi__uint16[STBI__ZNSYMS] value;
}

int stbi__bitreverse16(int n)
{
    n = ((n & 0xAAAA) >>  1) | ((n & 0x5555) << 1);
    n = ((n & 0xCCCC) >>  2) | ((n & 0x3333) << 2);
    n = ((n & 0xF0F0) >>  4) | ((n & 0x0F0F) << 4);
    n = ((n & 0xFF00) >>  8) | ((n & 0x00FF) << 8);
    return n;
}

int stbi__bit_reverse(int v, int bits)
{
    assert(bits <= 16);
    // to bit reverse n bits, reverse 16 and shift
    // e.g. 11 bits, bit reverse and shift away 5
    return stbi__bitreverse16(v) >> (16-bits);
}

int stbi__zbuild_huffman(stbi__zhuffman *z, const stbi_uc *sizelist, int num)
{
    int i,k=0;
    int code;
    int[16] next_code;
    int[17] sizes;

    // DEFLATE spec for generating codes
    memset(sizes.ptr, 0, sizes.sizeof);
    memset(z.fast.ptr, 0, z.fast.sizeof);
    for (i=0; i < num; ++i)
        ++sizes[sizelist[i]];
    sizes[0] = 0;
    for (i=1; i < 16; ++i)
        if (sizes[i] > (1 << i))
            return 0; // stbi__err("bad sizes", "Corrupt PNG");
    code = 0;
    for (i=1; i < 16; ++i) {
        next_code[i] = code;
        z.firstcode[i] = cast(stbi__uint16) code;
        z.firstsymbol[i] = cast(stbi__uint16) k;
        code = (code + sizes[i]);
        if (sizes[i])
            if (code-1 >= (1 << i)) return 0; // stbi__err("bad codelengths","Corrupt PNG");
        z.maxcode[i] = code << (16-i); // preshift for inner loop
        code <<= 1;
        k += sizes[i];
    }
    z.maxcode[16] = 0x10000; // sentinel
    for (i=0; i < num; ++i) {
        int s = sizelist[i];
        if (s) {
            int c = next_code[s] - z.firstcode[s] + z.firstsymbol[s];
            stbi__uint16 fastv = cast(stbi__uint16) ((s << 9) | i);
            z.size [c] = cast(stbi_uc     ) s;
            z.value[c] = cast(stbi__uint16) i;
            if (s <= STBI__ZFAST_BITS) {
                int j = stbi__bit_reverse(next_code[s],s);
                while (j < (1 << STBI__ZFAST_BITS)) {
                    z.fast[j] = fastv;
                    j += (1 << s);
                }
            }
            ++next_code[s];
        }
    }
    return 1;
}

// zlib-from-memory implementation for PNG reading
//    because PNG allows splitting the zlib stream arbitrarily,
//    and it's annoying structurally to have PNG call ZLIB call PNG,
//    we require PNG read all the IDATs and combine them into a single
//    memory buffer

struct stbi__zbuf
{
    stbi_uc *zbuffer, zbuffer_end;
    int num_bits;
    stbi__uint32 code_buffer;

    ubyte *zout;
    ubyte *zout_start;
    ubyte *zout_end;
    int   z_expandable;

    stbi__zhuffman z_length, z_distance;
}

int stbi__zeof(stbi__zbuf *z)
{
    return (z.zbuffer >= z.zbuffer_end);
}

stbi_uc stbi__zget8(stbi__zbuf *z)
{
    return stbi__zeof(z) ? 0 : *z.zbuffer++;
}

void stbi__fill_bits(stbi__zbuf *z)
{
    do {
        if (z.code_buffer >= (1U << z.num_bits)) {
            z.zbuffer = z.zbuffer_end;  /* treat this as EOF so we fail. */
            return;
        }
        z.code_buffer |= cast(uint) stbi__zget8(z) << z.num_bits;
        z.num_bits += 8;
    } while (z.num_bits <= 24);
}

uint stbi__zreceive(stbi__zbuf *z, int n)
{
    uint k;
    if (z.num_bits < n) stbi__fill_bits(z);
    k = z.code_buffer & ((1 << n) - 1);
    z.code_buffer >>= n;
    z.num_bits -= n;
    return k;
}

int stbi__zhuffman_decode_slowpath(stbi__zbuf *a, stbi__zhuffman *z)
{
    int b,s,k;
    // not resolved by fast table, so compute it the slow way
    // use jpeg approach, which requires MSbits at top
    k = stbi__bit_reverse(a.code_buffer, 16);
    for (s=STBI__ZFAST_BITS+1; ; ++s)
        if (k < z.maxcode[s])
            break;
    if (s >= 16) return -1; // invalid code!
    // code size is s, so:
    b = (k >> (16-s)) - z.firstcode[s] + z.firstsymbol[s];
    if (b >= STBI__ZNSYMS) return -1; // some data was corrupt somewhere!
    if (z.size[b] != s) return -1;  // was originally an assert, but report failure instead.
    a.code_buffer >>= s;
    a.num_bits -= s;
    return z.value[b];
}

int stbi__zhuffman_decode(stbi__zbuf *a, stbi__zhuffman *z)
{
    int b,s;
    if (a.num_bits < 16) {
        if (stbi__zeof(a)) {
            return -1;   /* report error for unexpected end of data. */
        }
        stbi__fill_bits(a);
    }
    b = z.fast[a.code_buffer & STBI__ZFAST_MASK];
    if (b) {
        s = b >> 9;
        a.code_buffer >>= s;
        a.num_bits -= s;
        return b & 511;
    }
    return stbi__zhuffman_decode_slowpath(a, z);
}

int stbi__zexpand(stbi__zbuf *z, ubyte *zout, int n)  // need to make room for n bytes
{
    ubyte *q;
    uint cur, limit, old_limit;
    z.zout = zout;
    if (!z.z_expandable) return 0; // stbi__err("output buffer limit","Corrupt PNG");
    cur   = cast(uint) (z.zout - z.zout_start);
    limit = old_limit = cast(uint) (z.zout_end - z.zout_start);
    if (uint.max - cur < cast(uint) n) return 0; //stbi__err("outofmem", "Out of memory");
    while (cur + n > limit) {
        if(limit > uint.max / 2) return 0; //stbi__err("outofmem", "Out of memory");
        limit *= 2;
    }
    q = cast(ubyte *) STBI_REALLOC_SIZED(z.zout_start, old_limit, limit);
    if (q == null) return 0; //stbi__err("outofmem", "Out of memory");
    z.zout_start = q;
    z.zout       = q + cur;
    z.zout_end   = q + limit;
    return 1;
}

static immutable int[31] stbi__zlength_base = [
    3,4,5,6,7,8,9,10,11,13,
    15,17,19,23,27,31,35,43,51,59,
    67,83,99,115,131,163,195,227,258,0,0 ];

static immutable int[31] stbi__zlength_extra=
[ 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0 ];

static immutable int[32] stbi__zdist_base = [ 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
                                              257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577,0,0];

static immutable int[32] stbi__zdist_extra =
[ 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];

int stbi__parse_huffman_block(stbi__zbuf *a)
{
    ubyte *zout = a.zout;
    for(;;) {
        int z = stbi__zhuffman_decode(a, &a.z_length);
        if (z < 256) 
        {
            if (z < 0) 
                return 0; //stbi__err("bad huffman code","Corrupt PNG"); // error in huffman codes
            if (zout >= a.zout_end) {
                if (!stbi__zexpand(a, zout, 1)) return 0;
                zout = a.zout;
            }
            *zout++ = cast(char) z;
        } else {
            stbi_uc *p;
            int len,dist;
            if (z == 256) {
                a.zout = zout;
                return 1;
            }
            z -= 257;
            len = stbi__zlength_base[z];
            if (stbi__zlength_extra[z]) len += stbi__zreceive(a, stbi__zlength_extra[z]);
            z = stbi__zhuffman_decode(a, &a.z_distance);
            if (z < 0) return 0; //stbi__err("bad huffman code","Corrupt PNG");
            dist = stbi__zdist_base[z];
            if (stbi__zdist_extra[z]) dist += stbi__zreceive(a, stbi__zdist_extra[z]);
            if (zout - a.zout_start < dist) return 0; //stbi__err("bad dist","Corrupt PNG");
            if (zout + len > a.zout_end) {
                if (!stbi__zexpand(a, zout, len)) return 0;
                zout = a.zout;
            }
            p = cast(stbi_uc *) (zout - dist);
            if (dist == 1) { // run of one byte; common in images.
                stbi_uc v = *p;
                if (len) { do *zout++ = v; while (--len); }
            } else {
                if (len) { do *zout++ = *p++; while (--len); }
            }
        }
    }
}

int stbi__compute_huffman_codes(stbi__zbuf *a)
{
    static immutable stbi_uc[19] length_dezigzag = [ 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15 ];
    stbi__zhuffman z_codelength;
    stbi_uc[286+32+137] lencodes;//padding for maximum single op
    stbi_uc[19] codelength_sizes;
    int i,n;

    int hlit  = stbi__zreceive(a,5) + 257;
    int hdist = stbi__zreceive(a,5) + 1;
    int hclen = stbi__zreceive(a,4) + 4;
    int ntot  = hlit + hdist;

    memset(codelength_sizes.ptr, 0, codelength_sizes.sizeof);
    for (i=0; i < hclen; ++i) {
        int s = stbi__zreceive(a,3);
        codelength_sizes[length_dezigzag[i]] = cast(stbi_uc) s;
    }
    if (!stbi__zbuild_huffman(&z_codelength, codelength_sizes.ptr, 19)) return 0;

    n = 0;
    while (n < ntot) {
        int c = stbi__zhuffman_decode(a, &z_codelength);
        if (c < 0 || c >= 19) return 0; //stbi__err("bad codelengths", "Corrupt PNG");
        if (c < 16)
            lencodes[n++] = cast(stbi_uc) c;
        else {
            stbi_uc fill = 0;
            if (c == 16) {
                c = stbi__zreceive(a,2)+3;
                if (n == 0) return 0; //stbi__err("bad codelengths", "Corrupt PNG");
                fill = lencodes[n-1];
            } else if (c == 17) {
                c = stbi__zreceive(a,3)+3;
            } else if (c == 18) {
                c = stbi__zreceive(a,7)+11;
            } else {
                return 0; //stbi__err("bad codelengths", "Corrupt PNG");
            }
            if (ntot - n < c) return 0; //stbi__err("bad codelengths", "Corrupt PNG");
            memset(lencodes.ptr+n, fill, c);
            n += c;
        }
    }
    if (n != ntot) return 0; //stbi__err("bad codelengths","Corrupt PNG");
    if (!stbi__zbuild_huffman(&a.z_length, lencodes.ptr, hlit)) return 0;
    if (!stbi__zbuild_huffman(&a.z_distance, lencodes.ptr+hlit, hdist)) return 0;
    return 1;
}

int stbi__parse_uncompressed_block(stbi__zbuf *a)
{
    stbi_uc[4] header;
    int len,nlen,k;
    if (a.num_bits & 7)
        stbi__zreceive(a, a.num_bits & 7); // discard
    // drain the bit-packed data into header
    k = 0;
    while (a.num_bits > 0) {
        header[k++] = cast(stbi_uc) (a.code_buffer & 255); // suppress MSVC run-time check
        a.code_buffer >>= 8;
        a.num_bits -= 8;
    }
    if (a.num_bits < 0) return 0; //stbi__err("zlib corrupt","Corrupt PNG");
    // now fill header the normal way
    while (k < 4)
        header[k++] = stbi__zget8(a);
    len  = header[1] * 256 + header[0];
    nlen = header[3] * 256 + header[2];
    if (nlen != (len ^ 0xffff)) return 0; //stbi__err("zlib corrupt","Corrupt PNG");
    if (a.zbuffer + len > a.zbuffer_end) return 0; //stbi__err("read past buffer","Corrupt PNG");
    if (a.zout + len > a.zout_end)
        if (!stbi__zexpand(a, a.zout, len)) return 0;
    memcpy(a.zout, a.zbuffer, len);
    a.zbuffer += len;
    a.zout += len;
    return 1;
}

int stbi__parse_zlib_header(stbi__zbuf *a)
{
    int cmf   = stbi__zget8(a);
    int cm    = cmf & 15;
    /* int cinfo = cmf >> 4; */
    int flg   = stbi__zget8(a);
    if (stbi__zeof(a)) return 0; //stbi__err("bad zlib header","Corrupt PNG"); // zlib spec
    if ((cmf*256+flg) % 31 != 0) return  0; //stbi__err("bad zlib header","Corrupt PNG"); // zlib spec
    if (flg & 32) return  0; //stbi__err("no preset dict","Corrupt PNG"); // preset dictionary not allowed in png
    if (cm != 8) return  0; //stbi__err("bad compression","Corrupt PNG"); // DEFLATE required for png
    // window = 1 << (8 + cinfo)... but who cares, we fully buffer output
    return 1;
}

static immutable stbi_uc[STBI__ZNSYMS] stbi__zdefault_length =
[
    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
    9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
    9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
    9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, 7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8
];
static immutable stbi_uc[32] stbi__zdefault_distance =
[
    5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
    ];
/*
Init algorithm:
{
int i;   // use <= to match clearly with spec
for (i=0; i <= 143; ++i)     stbi__zdefault_length[i]   = 8;
for (   ; i <= 255; ++i)     stbi__zdefault_length[i]   = 9;
for (   ; i <= 279; ++i)     stbi__zdefault_length[i]   = 7;
for (   ; i <= 287; ++i)     stbi__zdefault_length[i]   = 8;

for (i=0; i <=  31; ++i)     stbi__zdefault_distance[i] = 5;
}
*/

int stbi__parse_zlib(stbi__zbuf *a, int parse_header)
{
    int final_, type;
    if (parse_header)
        if (!stbi__parse_zlib_header(a)) return 0;
    a.num_bits = 0;
    a.code_buffer = 0;
    do {
        final_ = stbi__zreceive(a,1);
        type = stbi__zreceive(a,2);
        if (type == 0) {
            if (!stbi__parse_uncompressed_block(a)) return 0;
        } else if (type == 3) {
            return 0;
        } else {
            if (type == 1) {
                // use fixed code lengths
                if (!stbi__zbuild_huffman(&a.z_length  , stbi__zdefault_length.ptr  , STBI__ZNSYMS)) return 0;
                if (!stbi__zbuild_huffman(&a.z_distance, stbi__zdefault_distance.ptr,  32)) return 0;
            } else {
                if (!stbi__compute_huffman_codes(a)) return 0;
            }
            if (!stbi__parse_huffman_block(a)) return 0;
        }
    } while (!final_);
    return 1;
}

int stbi__do_zlib(stbi__zbuf *a, ubyte *obuf, int olen, int exp, int parse_header)
{
    a.zout_start = obuf;
    a.zout       = obuf;
    a.zout_end   = obuf + olen;
    a.z_expandable = exp;

    return stbi__parse_zlib(a, parse_header);
}

ubyte *stbi_zlib_decode_malloc_guesssize(const char *buffer, int len, int initial_size, int *outlen)
{
    stbi__zbuf a;
    ubyte *p = cast(ubyte *) stbi__malloc(initial_size);
    if (p == null) return null;
    a.zbuffer = cast(stbi_uc *) buffer;
    a.zbuffer_end = cast(stbi_uc *) buffer + len;
    if (stbi__do_zlib(&a, p, initial_size, 1, 1)) {
        if (outlen) *outlen = cast(int) (a.zout - a.zout_start);
        return a.zout_start;
    } else {
        STBI_FREE(a.zout_start);
        return null;
    }
}

ubyte *stbi_zlib_decode_malloc(const(char)*buffer, int len, int *outlen)
{
    return stbi_zlib_decode_malloc_guesssize(buffer, len, 16384, outlen);
}

ubyte *stbi_zlib_decode_malloc_guesssize_headerflag(const char *buffer, int len, int initial_size, int *outlen, int parse_header)
{
    stbi__zbuf a;
    ubyte *p = cast(ubyte *) stbi__malloc(initial_size);
    if (p == null) return null;
    a.zbuffer = cast(stbi_uc *) buffer;
    a.zbuffer_end = cast(stbi_uc *) buffer + len;
    if (stbi__do_zlib(&a, p, initial_size, 1, parse_header)) {
        if (outlen) *outlen = cast(int) (a.zout - a.zout_start);
        return a.zout_start;
    } else {
        STBI_FREE(a.zout_start);
        return null;
    }
}


// public domain "baseline" PNG decoder   v0.10  Sean Barrett 2006-11-18
//    simple implementation
//      - only 8-bit samples
//      - no CRC checking
//      - allocates lots of intermediate memory
//        - avoids problem of streaming data between subsystems
//        - avoids explicit window management
//    performance
//      - uses stb_zlib, a PD zlib implementation with fast huffman decoding

version(decodePNG)
{
    struct stbi__pngchunk
    {
        stbi__uint32 length;
        stbi__uint32 type;
    }

    stbi__pngchunk stbi__get_chunk_header(stbi__context *s)
    {
        stbi__pngchunk c;
        c.length = stbi__get32be(s);
        c.type   = stbi__get32be(s);
        return c;
    }

    int stbi__check_png_header(stbi__context *s)
    {
        static immutable stbi_uc[8] png_sig = [ 137,80,78,71,13,10,26,10 ];
        int i;
        for (i=0; i < 8; ++i)
            if (stbi__get8(s) != png_sig[i]) 
                return 0; //stbi__err("bad png sig","Not a PNG");
        return 1;
    }

    struct stbi__png
    {
        stbi__context *s;
        stbi_uc* idata; 
        stbi_uc* expanded;
        stbi_uc* out_;
        int depth;
    }

    enum 
    {
        STBI__F_none=0,
        STBI__F_sub=1,
        STBI__F_up=2,
        STBI__F_avg=3,
        STBI__F_paeth=4,
        // synthetic filters used for first scanline to avoid needing a dummy row of 0s
        STBI__F_avg_first,
        STBI__F_paeth_first
    }

    static immutable stbi_uc[5] first_row_filter =
    [
        STBI__F_none,
        STBI__F_sub,
        STBI__F_none,
        STBI__F_avg_first,
        STBI__F_paeth_first
    ];

    int stbi__paeth(int a, int b, int c)
    {
        int p = a + b - c;
        int pa = abs(p-a);
        int pb = abs(p-b);
        int pc = abs(p-c);
        if (pa <= pb && pa <= pc) 
            return a;
        if (pb <= pc) 
            return b;
        return c;
    }

    static immutable stbi_uc[9] stbi__depth_scale_table = [ 0, 0xff, 0x55, 0, 0x11, 0,0,0, 0x01 ];

    // create the png data from post-deflated data
    int stbi__create_png_image_raw(stbi__png *a, stbi_uc *raw, stbi__uint32 raw_len, int out_n, stbi__uint32 x, stbi__uint32 y, int depth, int color)
    {
        int bytes = (depth == 16? 2 : 1);
        stbi__context *s = a.s;
        stbi__uint32 i,j,stride = x*out_n*bytes;
        stbi__uint32 img_len, img_width_bytes;
        int k;
        int img_n = s.img_n; // copy it into a local for later

        int output_bytes = out_n*bytes;
        int filter_bytes = img_n*bytes;
        int width = x;

        assert(out_n == s.img_n || out_n == s.img_n+1);
        a.out_ = cast(stbi_uc *) stbi__malloc_mad3(x, y, output_bytes, 0); // extra bytes to write off the end into
        if (!a.out_) return 0; //stbi__err("outofmem", "Out of memory");

        if (!stbi__mad3sizes_valid(img_n, x, depth, 7)) return 0; //stbi__err("too large", "Corrupt PNG");
        img_width_bytes = (((img_n * x * depth) + 7) >> 3);
        img_len = (img_width_bytes + 1) * y;

        // we used to check for exact match between raw_len and img_len on non-interlaced PNGs,
        // but issue #276 reported a PNG in the wild that had extra data at the end (all zeros),
        // so just check for raw_len < img_len always.
        if (raw_len < img_len) return 0; //stbi__err("not enough pixels","Corrupt PNG");

        for (j=0; j < y; ++j) 
        {
            stbi_uc *cur = a.out_ + stride*j;
            stbi_uc *prior;
            int filter = *raw++;

            if (filter > 4)
                return 0; //stbi__err("invalid filter","Corrupt PNG");

            if (depth < 8) {
                if (img_width_bytes > x) return 0; //stbi__err("invalid width","Corrupt PNG");
                cur += x*out_n - img_width_bytes; // store output to the rightmost img_len bytes, so we can decode in place
                filter_bytes = 1;
                width = img_width_bytes;
            }
            prior = cur - stride; // bugfix: need to compute this after 'cur +=' computation above

            // if first row, use special filter that doesn't sample previous row
            if (j == 0) filter = first_row_filter[filter];

            // handle first byte explicitly
            for (k=0; k < filter_bytes; ++k) 
            {
                switch (filter) {
                    case STBI__F_none       : cur[k] = raw[k]; break;
                    case STBI__F_sub        : cur[k] = raw[k]; break;
                    case STBI__F_up         : cur[k] = STBI__BYTECAST(raw[k] + prior[k]); break;
                    case STBI__F_avg        : cur[k] = STBI__BYTECAST(raw[k] + (prior[k]>>1)); break;
                    case STBI__F_paeth      : cur[k] = STBI__BYTECAST(raw[k] + stbi__paeth(0,prior[k],0)); break;
                    case STBI__F_avg_first  : cur[k] = raw[k]; break;
                    case STBI__F_paeth_first: cur[k] = raw[k]; break;
                    default: assert(false);
                }
            }

            if (depth == 8) {
                if (img_n != out_n)
                    cur[img_n] = 255; // first pixel
                raw += img_n;
                cur += out_n;
                prior += out_n;
            } else if (depth == 16) {
                if (img_n != out_n) {
                    cur[filter_bytes]   = 255; // first pixel top byte
                    cur[filter_bytes+1] = 255; // first pixel bottom byte
                }
                raw += filter_bytes;
                cur += output_bytes;
                prior += output_bytes;
            } else {
                raw += 1;
                cur += 1;
                prior += 1;
            }

            // this is a little gross, so that we don't switch per-pixel or per-component
            if (depth < 8 || img_n == out_n) {
                int nk = (width - 1)*filter_bytes;
                switch (filter) {
                    // "none" filter turns into a memcpy here; make that explicit.
                    case STBI__F_none:         
                        memcpy(cur, raw, nk); 
                        break;
                    case STBI__F_sub:         for (k=0; k < nk; ++k) { cur[k] = STBI__BYTECAST(raw[k] + cur[k-filter_bytes]); } break;
                    case STBI__F_up:          for (k=0; k < nk; ++k) { cur[k] = STBI__BYTECAST(raw[k] + prior[k]); } break;
                    case STBI__F_avg:         for (k=0; k < nk; ++k) { cur[k] = STBI__BYTECAST(raw[k] + ((prior[k] + cur[k-filter_bytes])>>1)); } break;
                    case STBI__F_paeth:       for (k=0; k < nk; ++k) { cur[k] = STBI__BYTECAST(raw[k] + stbi__paeth(cur[k-filter_bytes],prior[k],prior[k-filter_bytes])); } break;
                    case STBI__F_avg_first:   for (k=0; k < nk; ++k) { cur[k] = STBI__BYTECAST(raw[k] + (cur[k-filter_bytes] >> 1)); } break;
                    case STBI__F_paeth_first: for (k=0; k < nk; ++k) { cur[k] = STBI__BYTECAST(raw[k] + stbi__paeth(cur[k-filter_bytes],0,0)); } break;
                    default: assert(0);
                }
                raw += nk;
            } else {
                assert(img_n+1 == out_n);
                switch (filter) {
                    case STBI__F_none:         
                        for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes)
                            for (k=0; k < filter_bytes; ++k)
                            { cur[k] = raw[k]; } break;
                    case STBI__F_sub:          
                        for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes)
                            for (k=0; k < filter_bytes; ++k)
                            { cur[k] = STBI__BYTECAST(raw[k] + cur[k- output_bytes]); } break;
                    case STBI__F_up:           
                        for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes)
                            for (k=0; k < filter_bytes; ++k)
                            { cur[k] = STBI__BYTECAST(raw[k] + prior[k]); } break;
                    case STBI__F_avg:          
                        for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes)
                            for (k=0; k < filter_bytes; ++k)
                            { cur[k] = STBI__BYTECAST(raw[k] + ((prior[k] + cur[k- output_bytes])>>1)); } break;
                    case STBI__F_paeth:        
                        for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes)
                            for (k=0; k < filter_bytes; ++k)
                            { cur[k] = STBI__BYTECAST(raw[k] + stbi__paeth(cur[k- output_bytes],prior[k],prior[k- output_bytes])); } break;
                    case STBI__F_avg_first:    
                        for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes)
                            for (k=0; k < filter_bytes; ++k)
                            { cur[k] = STBI__BYTECAST(raw[k] + (cur[k- output_bytes] >> 1)); } break;
                    case STBI__F_paeth_first:  
                        for (i=x-1; i >= 1; --i, cur[filter_bytes]=255,raw+=filter_bytes,cur+=output_bytes,prior+=output_bytes)
                            for (k=0; k < filter_bytes; ++k)
                            { cur[k] = STBI__BYTECAST(raw[k] + stbi__paeth(cur[k- output_bytes],0,0)); } break;
                    default: assert(0);
                }

                // the loop above sets the high byte of the pixels' alpha, but for
                // 16 bit png files we also need the low byte set. we'll do that here.
                if (depth == 16) {
                    cur = a.out_ + stride*j; // start at the beginning of the row again
                    for (i=0; i < x; ++i,cur+=output_bytes) {
                        cur[filter_bytes+1] = 255;
                    }
                }
            }
        }

        // we make a separate pass to expand bits to pixels; for performance,
        // this could run two scanlines behind the above code, so it won't
        // intefere with filtering but will still be in the cache.
        if (depth < 8) {
            for (j=0; j < y; ++j) {
                stbi_uc *cur = a.out_ + stride*j;
                stbi_uc *in_  = a.out_ + stride*j + x*out_n - img_width_bytes;
                // unpack 1/2/4-bit into a 8-bit buffer. allows us to keep the common 8-bit path optimal at minimal cost for 1/2/4-bit
                // png guarante byte alignment, if width is not multiple of 8/4/2 we'll decode dummy trailing data that will be skipped in the later loop
                stbi_uc scale = (color == 0) ? stbi__depth_scale_table[depth] : 1; // scale grayscale values to 0..255 range

                // note that the final byte might overshoot and write more data than desired.
                // we can allocate enough data that this never writes out of memory, but it
                // could also overwrite the next scanline. can it overwrite non-empty data
                // on the next scanline? yes, consider 1-pixel-wide scanlines with 1-bit-per-pixel.
                // so we need to explicitly clamp the final ones

                if (depth == 4) {
                    for (k=x*img_n; k >= 2; k-=2, ++in_) {
                        *cur++ = cast(ubyte)(scale * ((*in_ >> 4))       );
                        *cur++ = cast(ubyte)(scale * ((*in_     ) & 0x0f));
                    }
                    if (k > 0) *cur++ = cast(ubyte)(scale * ((*in_ >> 4)       ));
                } else if (depth == 2) {
                    for (k=x*img_n; k >= 4; k-=4, ++in_) {
                        *cur++ = cast(ubyte)(scale * ((*in_ >> 6)       ));
                        *cur++ = cast(ubyte)(scale * ((*in_ >> 4) & 0x03));
                        *cur++ = cast(ubyte)(scale * ((*in_ >> 2) & 0x03));
                        *cur++ = cast(ubyte)(scale * ((*in_     ) & 0x03));
                    }
                    if (k > 0) *cur++ = cast(ubyte)(scale * ((*in_ >> 6)       ));
                    if (k > 1) *cur++ = cast(ubyte)(scale * ((*in_ >> 4) & 0x03));
                    if (k > 2) *cur++ = cast(ubyte)(scale * ((*in_ >> 2) & 0x03));
                } else if (depth == 1) {
                    for (k=x*img_n; k >= 8; k-=8, ++in_) {
                        *cur++ = scale * ((*in_ >> 7)       );
                        *cur++ = scale * ((*in_ >> 6) & 0x01);
                        *cur++ = scale * ((*in_ >> 5) & 0x01);
                        *cur++ = scale * ((*in_ >> 4) & 0x01);
                        *cur++ = scale * ((*in_ >> 3) & 0x01);
                        *cur++ = scale * ((*in_ >> 2) & 0x01);
                        *cur++ = scale * ((*in_ >> 1) & 0x01);
                        *cur++ = scale * ((*in_     ) & 0x01);
                    }
                    if (k > 0) *cur++ = scale * ((*in_ >> 7)       );
                    if (k > 1) *cur++ = scale * ((*in_ >> 6) & 0x01);
                    if (k > 2) *cur++ = scale * ((*in_ >> 5) & 0x01);
                    if (k > 3) *cur++ = scale * ((*in_ >> 4) & 0x01);
                    if (k > 4) *cur++ = scale * ((*in_ >> 3) & 0x01);
                    if (k > 5) *cur++ = scale * ((*in_ >> 2) & 0x01);
                    if (k > 6) *cur++ = scale * ((*in_ >> 1) & 0x01);
                }
                if (img_n != out_n) {
                    int q;
                    // insert alpha = 255
                    cur = a.out_ + stride*j;
                    if (img_n == 1) {
                        for (q=x-1; q >= 0; --q) {
                            cur[q*2+1] = 255;
                            cur[q*2+0] = cur[q];
                        }
                    } else {
                        assert(img_n == 3);
                        for (q=x-1; q >= 0; --q) {
                            cur[q*4+3] = 255;
                            cur[q*4+2] = cur[q*3+2];
                            cur[q*4+1] = cur[q*3+1];
                            cur[q*4+0] = cur[q*3+0];
                        }
                    }
                }
            }
        } else if (depth == 16) {
            // force the image data from big-endian to platform-native.
            // this is done in a separate pass due to the decoding relying
            // on the data being untouched, but could probably be done
            // per-line during decode if care is taken.
            stbi_uc *cur = a.out_;
            stbi__uint16 *cur16 = cast(stbi__uint16*)cur;

            for(i=0; i < x*y*out_n; ++i,cur16++,cur+=2) {
                *cur16 = (cur[0] << 8) | cur[1];
            }
        }

        return 1;
    }

    int stbi__create_png_image(stbi__png *a, stbi_uc *image_data, stbi__uint32 image_data_len, int out_n, int depth, int color, int interlaced)
    {
        int bytes = (depth == 16 ? 2 : 1);
        int out_bytes = out_n * bytes;
        stbi_uc *final_;
        int p;
        if (!interlaced)
            return stbi__create_png_image_raw(a, image_data, image_data_len, out_n, a.s.img_x, a.s.img_y, depth, color);

        // de-interlacing
        final_ = cast(stbi_uc *) stbi__malloc_mad3(a.s.img_x, a.s.img_y, out_bytes, 0);
        if (!final_) return 0; //stbi__err("outofmem", "Out of memory");
        for (p=0; p < 7; ++p) {
            static immutable int[7] xorig = [ 0,4,0,2,0,1,0 ];
            static immutable int[7] yorig = [ 0,0,4,0,2,0,1 ];
            static immutable int[7] xspc  = [ 8,8,4,4,2,2,1 ];
            static immutable int[7] yspc  = [ 8,8,8,4,4,2,2 ];
            int i,j,x,y;
            // pass1_x[4] = 0, pass1_x[5] = 1, pass1_x[12] = 1
            x = (a.s.img_x - xorig[p] + xspc[p]-1) / xspc[p];
            y = (a.s.img_y - yorig[p] + yspc[p]-1) / yspc[p];
            if (x && y) {
                stbi__uint32 img_len = ((((a.s.img_n * x * depth) + 7) >> 3) + 1) * y;
                if (!stbi__create_png_image_raw(a, image_data, image_data_len, out_n, x, y, depth, color)) {
                    STBI_FREE(final_);
                    return 0;
                }
                for (j=0; j < y; ++j) {
                    for (i=0; i < x; ++i) {
                        int out_y = j*yspc[p]+yorig[p];
                        int out_x = i*xspc[p]+xorig[p];
                        memcpy(final_ + out_y*a.s.img_x*out_bytes + out_x*out_bytes,
                               a.out_ + (j*x+i)*out_bytes, out_bytes);
                    }
                }
                STBI_FREE(a.out_);
                image_data += img_len;
                image_data_len -= img_len;
            }
        }
        a.out_ = final_;

        return 1;
    }

    int stbi__compute_transparency(stbi__png *z, stbi_uc* tc, int out_n)
    {
        stbi__context *s = z.s;
        stbi__uint32 i, pixel_count = s.img_x * s.img_y;
        stbi_uc *p = z.out_;

        // compute color-based transparency, assuming we've
        // already got 255 as the alpha value in the output
        assert(out_n == 2 || out_n == 4);

        if (out_n == 2) {
            for (i=0; i < pixel_count; ++i) {
                p[1] = (p[0] == tc[0] ? 0 : 255);
                p += 2;
            }
        } else {
            for (i=0; i < pixel_count; ++i) {
                if (p[0] == tc[0] && p[1] == tc[1] && p[2] == tc[2])
                    p[3] = 0;
                p += 4;
            }
        }
        return 1;
    }

    int stbi__compute_transparency16(stbi__png *z, stbi__uint16* tc, int out_n)
    {
        stbi__context *s = z.s;
        stbi__uint32 i, pixel_count = s.img_x * s.img_y;
        stbi__uint16 *p = cast(stbi__uint16*) z.out_;

        // compute color-based transparency, assuming we've
        // already got 65535 as the alpha value in the output
        assert(out_n == 2 || out_n == 4);

        if (out_n == 2) {
            for (i = 0; i < pixel_count; ++i) {
                p[1] = (p[0] == tc[0] ? 0 : 65535);
                p += 2;
            }
        } else {
            for (i = 0; i < pixel_count; ++i) {
                if (p[0] == tc[0] && p[1] == tc[1] && p[2] == tc[2])
                    p[3] = 0;
                p += 4;
            }
        }
        return 1;
    }

    int stbi__expand_png_palette(stbi__png *a, stbi_uc *palette, int len, int pal_img_n)
    {
        stbi__uint32 i, pixel_count = a.s.img_x * a.s.img_y;
        stbi_uc* p, temp_out, orig = a.out_;

        p = cast(stbi_uc *) stbi__malloc_mad2(pixel_count, pal_img_n, 0);
        if (p == null) return 0; //stbi__err("outofmem", "Out of memory");

        // between here and free(out) below, exitting would leak
        temp_out = p;

        if (pal_img_n == 3) {
            for (i=0; i < pixel_count; ++i) {
                int n = orig[i]*4;
                p[0] = palette[n  ];
                p[1] = palette[n+1];
                p[2] = palette[n+2];
                p += 3;
            }
        } else {
            for (i=0; i < pixel_count; ++i) {
                int n = orig[i]*4;
                p[0] = palette[n  ];
                p[1] = palette[n+1];
                p[2] = palette[n+2];
                p[3] = palette[n+3];
                p += 4;
            }
        }
        STBI_FREE(a.out_);
        a.out_ = temp_out;

        return 1;
    }

    enum stbi__unpremultiply_on_load = 1;

    uint STBI__PNG_TYPE(char a, char b, char c, char d)
    {
        return ( (cast(uint)a) << 24 )
            + ( (cast(uint)b) << 16 )
            + ( (cast(uint)c) << 8  )
            + ( (cast(uint)d) << 0  );
    }

    int stbi__parse_png_file(stbi__png *z, int scan, int req_comp)
    {
        stbi_uc[1024] palette;
        stbi_uc pal_img_n=0;
        stbi_uc has_trans = 0;
        stbi_uc[3] tc = [0, 0, 0];
        stbi__uint16[3] tc16;
        stbi__uint32 ioff=0, idata_limit=0, i, pal_len=0;
        int first=1,k,interlace=0, color=0, is_iphone=0;
        stbi__context *s = z.s;

        z.expanded = null;
        z.idata = null;
        z.out_ = null;

        if (!stbi__check_png_header(s)) return 0;

        if (scan == STBI__SCAN_type) return 1;

        for (;;) {
            stbi__pngchunk c = stbi__get_chunk_header(s);
            switch (c.type) {
                case STBI__PNG_TYPE('C','g','B','I'):
                    is_iphone = 1;
                    stbi__skip(s, c.length);
                    break;
                case STBI__PNG_TYPE('I','H','D','R'): {
                    int comp,filter;
                    if (!first) return 0; //stbi__err("multiple IHDR","Corrupt PNG");
                    first = 0;
                    if (c.length != 13) return 0; //stbi__err("bad IHDR len","Corrupt PNG");
                    s.img_x = stbi__get32be(s);
                    s.img_y = stbi__get32be(s);
                    if (s.img_y > STBI_MAX_DIMENSIONS) return 0; //stbi__err("too large","Very large image (corrupt?)");
                    if (s.img_x > STBI_MAX_DIMENSIONS) return 0; //stbi__err("too large","Very large image (corrupt?)");
                    z.depth = stbi__get8(s);  if (z.depth != 1 && z.depth != 2 && z.depth != 4 && z.depth != 8 && z.depth != 16)  return 0; //stbi__err("1/2/4/8/16-bit only","PNG not supported: 1/2/4/8/16-bit only");
                    color = stbi__get8(s);  if (color > 6)         return 0; //stbi__err("bad ctype","Corrupt PNG");
                    if (color == 3 && z.depth == 16)                  return 0; //stbi__err("bad ctype","Corrupt PNG");
                    if (color == 3) pal_img_n = 3; else if (color & 1) return 0; //stbi__err("bad ctype","Corrupt PNG");
                    comp  = stbi__get8(s);  if (comp) return 0; //stbi__err("bad comp method","Corrupt PNG");
                    filter= stbi__get8(s);  if (filter) return 0; //stbi__err("bad filter method","Corrupt PNG");
                    interlace = stbi__get8(s); if (interlace>1) return 0; //stbi__err("bad interlace method","Corrupt PNG");
                    if (!s.img_x || !s.img_y) return 0; //stbi__err("0-pixel image","Corrupt PNG");
                    if (!pal_img_n) {
                        s.img_n = (color & 2 ? 3 : 1) + (color & 4 ? 1 : 0);
                        if ((1 << 30) / s.img_x / s.img_n < s.img_y) return 0; //stbi__err("too large", "Image too large to decode");
                        if (scan == STBI__SCAN_header) return 1;
                    } else {
                        // if paletted, then pal_n is our final components, and
                        // img_n is # components to decompress/filter.
                        s.img_n = 1;
                        if ((1 << 30) / s.img_x / 4 < s.img_y) return 0; //stbi__err("too large","Corrupt PNG");
                        // if SCAN_header, have to scan to see if we have a tRNS
                    }
                    break;
                }

                case STBI__PNG_TYPE('P','L','T','E'):  {
                    if (first) return 0; //stbi__err("first not IHDR", "Corrupt PNG");
                    if (c.length > 256*3) return 0; //stbi__err("invalid PLTE","Corrupt PNG");
                    pal_len = c.length / 3;
                    if (pal_len * 3 != c.length) return 0; //stbi__err("invalid PLTE","Corrupt PNG");
                    for (i=0; i < pal_len; ++i) {
                        palette[i*4+0] = stbi__get8(s);
                        palette[i*4+1] = stbi__get8(s);
                        palette[i*4+2] = stbi__get8(s);
                        palette[i*4+3] = 255;
                    }
                    break;
                }

                case STBI__PNG_TYPE('t','R','N','S'): {
                    if (first) return 0; //stbi__err("first not IHDR", "Corrupt PNG");
                    if (z.idata) return 0; //stbi__err("tRNS after IDAT","Corrupt PNG");
                    if (pal_img_n) {
                        if (scan == STBI__SCAN_header) { s.img_n = 4; return 1; }
                        if (pal_len == 0) return 0; //stbi__err("tRNS before PLTE","Corrupt PNG");
                        if (c.length > pal_len) return 0; //stbi__err("bad tRNS len","Corrupt PNG");
                        pal_img_n = 4;
                        for (i=0; i < c.length; ++i)
                            palette[i*4+3] = stbi__get8(s);
                    } else {
                        if (!(s.img_n & 1)) return 0; //stbi__err("tRNS with alpha","Corrupt PNG");
                        if (c.length != cast(stbi__uint32) s.img_n*2) return 0; //stbi__err("bad tRNS len","Corrupt PNG");
                        has_trans = 1;
                        if (z.depth == 16) {
                            for (k = 0; k < s.img_n; ++k) tc16[k] = cast(stbi__uint16)stbi__get16be(s); // copy the values as-is
                        } else {
                            for (k = 0; k < s.img_n; ++k) 
                            {
                                tc[k] = cast(ubyte)( cast(stbi_uc)(stbi__get16be(s) & 255) * stbi__depth_scale_table[z.depth]); // non 8-bit images will be larger
                            }
                        }
                    }
                    break;
                }

                case STBI__PNG_TYPE('I','D','A','T'): {
                    if (first) return 0; //stbi__err("first not IHDR", "Corrupt PNG");
                    if (pal_img_n && !pal_len) return 0; //stbi__err("no PLTE","Corrupt PNG");
                    if (scan == STBI__SCAN_header) { s.img_n = pal_img_n; return 1; }
                    if (cast(int)(ioff + c.length) < cast(int)ioff) return 0;
                    if (ioff + c.length > idata_limit) {
                        stbi__uint32 idata_limit_old = idata_limit;
                        stbi_uc *p;
                        if (idata_limit == 0) idata_limit = c.length > 4096 ? c.length : 4096;
                        while (ioff + c.length > idata_limit)
                            idata_limit *= 2;
                        p = cast(stbi_uc *) STBI_REALLOC_SIZED(z.idata, idata_limit_old, idata_limit); if (p == null) return 0; //stbi__err("outofmem", "Out of memory");
                        z.idata = p;
                    }
                    if (!stbi__getn(s, z.idata+ioff,c.length)) return 0; //stbi__err("outofdata","Corrupt PNG");
                    ioff += c.length;
                    break;
                }

                case STBI__PNG_TYPE('I','E','N','D'): {
                    stbi__uint32 raw_len, bpl;
                    if (first) return 0; //stbi__err("first not IHDR", "Corrupt PNG");
                    if (scan != STBI__SCAN_load) return 1;
                    if (z.idata == null) return 0; //stbi__err("no IDAT","Corrupt PNG");
                    // initial guess for decoded data size to avoid unnecessary reallocs
                    bpl = (s.img_x * z.depth + 7) / 8; // bytes per line, per component
                    raw_len = bpl * s.img_y * s.img_n /* pixels */ + s.img_y /* filter mode per row */;
                    z.expanded = cast(stbi_uc *) stbi_zlib_decode_malloc_guesssize_headerflag(cast(char *) z.idata, ioff, raw_len, cast(int *) &raw_len, !is_iphone);
                    if (z.expanded == null) return 0; // zlib should set error
                    STBI_FREE(z.idata); z.idata = null;
                    if ((req_comp == s.img_n+1 && req_comp != 3 && !pal_img_n) || has_trans)
                        s.img_out_n = s.img_n+1;
                    else
                        s.img_out_n = s.img_n;
                    if (!stbi__create_png_image(z, z.expanded, raw_len, s.img_out_n, z.depth, color, interlace)) return 0;
                    if (has_trans) {
                        if (z.depth == 16) {
                            if (!stbi__compute_transparency16(z, tc16.ptr, s.img_out_n)) return 0;
                        } else {
                            if (!stbi__compute_transparency(z, tc.ptr, s.img_out_n)) return 0;
                        }
                    }

                    if (pal_img_n) {
                        // pal_img_n == 3 or 4
                        s.img_n = pal_img_n; // record the actual colors we had
                        s.img_out_n = pal_img_n;
                        if (req_comp >= 3) s.img_out_n = req_comp;
                        if (!stbi__expand_png_palette(z, palette.ptr, pal_len, s.img_out_n))
                            return 0;
                    } else if (has_trans) {
                        // non-paletted image with tRNS . source image has (constant) alpha
                        ++s.img_n;
                    }
                    STBI_FREE(z.expanded); z.expanded = null;
                    // end of PNG chunk, read and skip CRC
                    stbi__get32be(s);
                    return 1;
                }

                default:
                    // if critical, fail
                    if (first) return 0; //stbi__err("first not IHDR", "Corrupt PNG");
                    if ((c.type & (1 << 29)) == 0) 
                    {
                        return 0; //stbi__err("invalid_chunk", "PNG not supported: unknown PNG chunk type");
                    }
                    stbi__skip(s, c.length);
                    break;
            }
            // end of PNG chunk, read and skip CRC
            stbi__get32be(s);
        }
    }

    void *stbi__do_png(stbi__png *p, int *x, int *y, int *n, int req_comp, stbi__result_info *ri)
    {
        void *result=null;
        if (req_comp < 0 || req_comp > 4) return null; //stbi__errpuc("bad req_comp", "Internal error");
        if (stbi__parse_png_file(p, STBI__SCAN_load, req_comp)) {
            if (p.depth <= 8)
                ri.bits_per_channel = 8;
            else if (p.depth == 16)
                ri.bits_per_channel = 16;
            else
                return null; //stbi__errpuc("bad bits_per_channel", "PNG not supported: unsupported color depth");
            result = p.out_;
            p.out_ = null;
            if (req_comp && req_comp != p.s.img_out_n) {
                if (ri.bits_per_channel == 8)
                    result = stbi__convert_format(cast(ubyte*) result, p.s.img_out_n, req_comp, p.s.img_x, p.s.img_y);
                else
                    result = stbi__convert_format16(cast(stbi__uint16 *) result, p.s.img_out_n, req_comp, p.s.img_x, p.s.img_y);
                p.s.img_out_n = req_comp;
                if (result == null) return result;
            }
            *x = p.s.img_x;
            *y = p.s.img_y;
            if (n) *n = p.s.img_n;
        }
        STBI_FREE(p.out_);     p.out_     = null;
        STBI_FREE(p.expanded); p.expanded = null;
        STBI_FREE(p.idata);    p.idata    = null;

        return result;
    }

    void *stbi__png_load(stbi__context *s, int *x, int *y, int *comp, int req_comp, stbi__result_info *ri)
    {
        stbi__png p;
        p.s = s;
        return stbi__do_png(&p, x,y,comp,req_comp, ri);
    }

    int stbi__png_test(stbi__context *s)
    {
        int r;
        r = stbi__check_png_header(s);
        stbi__rewind(s);
        return r;
    }

    int stbi__png_info_raw(stbi__png *p, int *x, int *y, int *comp)
    {
        if (!stbi__parse_png_file(p, STBI__SCAN_header, 0)) {
            stbi__rewind( p.s );
            return 0;
        }
        if (x) *x = p.s.img_x;
        if (y) *y = p.s.img_y;
        if (comp) *comp = p.s.img_n;
        return 1;
    }

    int stbi__png_info(stbi__context *s, int *x, int *y, int *comp)
    {
        stbi__png p;
        p.s = s;
        return stbi__png_info_raw(&p, x, y, comp);
    }

    int stbi__png_is16(stbi__context *s)
    {
        stbi__png p;
        p.s = s;
        if (!stbi__png_info_raw(&p, null, null, null))
            return 0;
        if (p.depth != 16) {
            stbi__rewind(p.s);
            return 0;
        }
        return 1;
    }

}