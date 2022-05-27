module dplug.graphics.qoi;

/*

QOI - The "Quite OK Image" format for fast, lossless image compression

Dominic Szablewski - https://phoboslab.org


-- LICENSE: The MIT License(MIT)

Copyright(c) 2021 Dominic Szablewski
Copyright(c) 2022 Guillaume Piolat (D translation)

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files(the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and / or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions :
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


-- About

QOI encodes and decodes images in a lossless format. Compared to stb_image and
stb_image_write QOI offers 20x-50x faster encoding, 3x-4x faster decoding and
20% better compression.


-- Documentation

This library provides the following functions;
- qoi_decode  -- decode the raw bytes of a QOI image from memory
- qoi_encode  -- encode an rgba buffer into a QOI image in memory


-- Data Format

A QOI file has a 14 byte header, followed by any number of data "chunks" and an
8-byte end marker.

struct qoi_header_t {
    char     magic[4];   // magic bytes "qoif"
    uint32_t width;      // image width in pixels (BE)
    uint32_t height;     // image height in pixels (BE)
    uint8_t  channels;   // 3 = RGB, 4 = RGBA
    uint8_t  colorspace; // 0 = sRGB with linear alpha, 1 = all channels linear
};

Images are encoded row by row, left to right, top to bottom. The decoder and
encoder start with {r: 0, g: 0, b: 0, a: 255} as the previous pixel value. An
image is complete when all pixels specified by width * height have been covered.

Pixels are encoded as
 - a run of the previous pixel
 - an index into an array of previously seen pixels
 - a difference to the previous pixel value in r,g,b
 - full r,g,b or r,g,b,a values

The color channels are assumed to not be premultiplied with the alpha channel
("un-premultiplied alpha").

A running array[64] (zero-initialized) of previously seen pixel values is
maintained by the encoder and decoder. Each pixel that is seen by the encoder
and decoder is put into this array at the position formed by a hash function of
the color value. In the encoder, if the pixel value at the index matches the
current pixel, this index position is written to the stream as QOI_OP_INDEX.
The hash function for the index is:

    index_position = (r * 3 + g * 5 + b * 7 + a * 11) % 64

Each chunk starts with a 2- or 8-bit tag, followed by a number of data bits. The
bit length of chunks is divisible by 8 - i.e. all chunks are byte aligned. All
values encoded in these data bits have the most significant bit on the left.

The 8-bit tags have precedence over the 2-bit tags. A decoder must check for the
presence of an 8-bit tag first.

The byte stream's end is marked with 7 0x00 bytes followed a single 0x01 byte.


The possible chunks are:


.- QOI_OP_INDEX ----------.
|         Byte[0]         |
|  7  6  5  4  3  2  1  0 |
|-------+-----------------|
|  0  0 |     index       |
`-------------------------`
2-bit tag b00
6-bit index into the color index array: 0..63

A valid encoder must not issue 2 or more consecutive QOI_OP_INDEX chunks to the
same index. QOI_OP_RUN should be used instead.


.- QOI_OP_DIFF -----------.
|         Byte[0]         |
|  7  6  5  4  3  2  1  0 |
|-------+-----+-----+-----|
|  0  1 |  dr |  dg |  db |
`-------------------------`
2-bit tag b01
2-bit   red channel difference from the previous pixel between -2..1
2-bit green channel difference from the previous pixel between -2..1
2-bit  blue channel difference from the previous pixel between -2..1

The difference to the current channel values are using a wraparound operation,
so "1 - 2" will result in 255, while "255 + 1" will result in 0.

Values are stored as unsigned integers with a bias of 2. E.g. -2 is stored as
0 (b00). 1 is stored as 3 (b11).

The alpha value remains unchanged from the previous pixel.


.- QOI_OP_LUMA -------------------------------------.
|         Byte[0]         |         Byte[1]         |
|  7  6  5  4  3  2  1  0 |  7  6  5  4  3  2  1  0 |
|-------+-----------------+-------------+-----------|
|  1  0 |  green diff     |   dr - dg   |  db - dg  |
`---------------------------------------------------`
2-bit tag b10
6-bit green channel difference from the previous pixel -32..31
4-bit   red channel difference minus green channel difference -8..7
4-bit  blue channel difference minus green channel difference -8..7

The green channel is used to indicate the general direction of change and is
encoded in 6 bits. The red and blue channels (dr and db) base their diffs off
of the green channel difference and are encoded in 4 bits. I.e.:
    dr_dg = (cur_px.r - prev_px.r) - (cur_px.g - prev_px.g)
    db_dg = (cur_px.b - prev_px.b) - (cur_px.g - prev_px.g)

The difference to the current channel values are using a wraparound operation,
so "10 - 13" will result in 253, while "250 + 7" will result in 1.

Values are stored as unsigned integers with a bias of 32 for the green channel
and a bias of 8 for the red and blue channel.

The alpha value remains unchanged from the previous pixel.


.- QOI_OP_RUN ------------.
|         Byte[0]         |
|  7  6  5  4  3  2  1  0 |
|-------+-----------------|
|  1  1 |       run       |
`-------------------------`
2-bit tag b11
6-bit run-length repeating the previous pixel: 1..62

The run-length is stored with a bias of -1. Note that the run-lengths 63 and 64
(b111110 and b111111) are illegal as they are occupied by the QOI_OP_RGB and
QOI_OP_RGBA tags.


.- QOI_OP_RGB ------------------------------------------.
|         Byte[0]         | Byte[1] | Byte[2] | Byte[3] |
|  7  6  5  4  3  2  1  0 | 7 .. 0  | 7 .. 0  | 7 .. 0  |
|-------------------------+---------+---------+---------|
|  1  1  1  1  1  1  1  0 |   red   |  green  |  blue   |
`-------------------------------------------------------`
8-bit tag b11111110
8-bit   red channel value
8-bit green channel value
8-bit  blue channel value

The alpha value remains unchanged from the previous pixel.


.- QOI_OP_RGBA ---------------------------------------------------.
|         Byte[0]         | Byte[1] | Byte[2] | Byte[3] | Byte[4] |
|  7  6  5  4  3  2  1  0 | 7 .. 0  | 7 .. 0  | 7 .. 0  | 7 .. 0  |
|-------------------------+---------+---------+---------+---------|
|  1  1  1  1  1  1  1  1 |   red   |  green  |  blue   |  alpha  |
`-----------------------------------------------------------------`
8-bit tag b11111111
8-bit   red channel value
8-bit green channel value
8-bit  blue channel value
8-bit alpha channel value

*/


/* A pointer to a qoi_desc struct has to be supplied to all of qoi's functions.
It describes either the input format (for qoi_write and qoi_encode), or is
filled with the description read from the file header (for qoi_read and
qoi_decode).

The colorspace in this qoi_desc is an enum where
    0 = sRGB, i.e. gamma scaled RGB channels and a linear alpha channel
    1 = all channels are linear
You may use the constants QOI_SRGB or QOI_LINEAR. The colorspace is purely
informative. It will be saved to the file header, but does not affect
how chunks are en-/decoded. */

import core.stdc.string: memset;
import core.stdc.stdlib: malloc, free;
import dplug.graphics.color;

nothrow @nogc:

enum QOI_SRGB = 0;
enum QOI_LINEAR = 1;

struct qoi_desc
{
    uint width;
    uint height;
    ubyte channels;
    ubyte colorspace;
}



alias QOI_MALLOC = malloc;
alias QOI_FREE = free;

enum int QOI_OP_INDEX = 0x00; /* 00xxxxxx */
enum int QOI_OP_DIFF  = 0x40; /* 01xxxxxx */
enum int QOI_OP_LUMA  = 0x80; /* 10xxxxxx */
enum int QOI_OP_RUN   = 0xc0; /* 11xxxxxx */
enum int QOI_OP_RGB   = 0xfe; /* 11111110 */
enum int QOI_OP_RGBA  = 0xff; /* 11111111 */

enum int QOI_MASK_2   = 0xc0; /* 11000000 */

int  QOI_COLOR_HASH(qoi_rgba_t C)
{
    return (C.rgba.r*3 + C.rgba.g*5 + C.rgba.b*7 + C.rgba.a*11);
}

enum uint QOI_MAGIC = 0x716F6966; // "qoif"
enum QOI_HEADER_SIZE = 14;

/* 2GB is the max file size that this implementation can safely handle. We guard
against anything larger than that, assuming the worst case with 5 bytes per
pixel, rounded down to a nice clean value. 400 million pixels ought to be
enough for anybody. */
enum uint QOI_PIXELS_MAX = 400000000;

struct qoi_rgba_t 
{   
    union
    {
        RGBA rgba;
        uint v;
    }
}

static immutable ubyte[8] qoi_padding = [0,0,0,0,0,0,0,1];

void qoi_write_32(ubyte* bytes, int *p, uint v) 
{
    bytes[(*p)++] = (0xff000000 & v) >> 24;
    bytes[(*p)++] = (0x00ff0000 & v) >> 16;
    bytes[(*p)++] = (0x0000ff00 & v) >> 8;
    bytes[(*p)++] = (0x000000ff & v);
}

uint qoi_read_32(const(ubyte)* bytes, int *p) 
{
    uint a = bytes[(*p)++];
    uint b = bytes[(*p)++];
    uint c = bytes[(*p)++];
    uint d = bytes[(*p)++];
    return a << 24 | b << 16 | c << 8 | d;
}

/* Encode raw RGB or RGBA pixels into a QOI image in memory.

The function either returns null on failure (invalid parameters or malloc
failed) or a pointer to the encoded data on success. On success the out_len
is set to the size in bytes of the encoded data.

The returned qoi data should be free()d after use. */
void *qoi_encode(const(void)* data, const(qoi_desc)* desc, int *out_len) 
{
    int i, max_size, p, run;
    int px_len, px_end, px_pos, channels;
    ubyte *bytes;
    const(ubyte)*pixels;
    qoi_rgba_t[64] index;
    qoi_rgba_t px, px_prev;

    if (
        data == null || out_len == null || desc == null ||
        desc.width == 0 || desc.height == 0 ||
        desc.channels < 3 || desc.channels > 4 ||
        desc.colorspace > 1 ||
        desc.height >= QOI_PIXELS_MAX / desc.width
    ) {
        return null;
    }

    max_size =
        desc.width * desc.height * (desc.channels + 1) +
        QOI_HEADER_SIZE + cast(int)qoi_padding.sizeof;

    p = 0;
    bytes = cast(ubyte *) QOI_MALLOC(max_size);
    if (!bytes) 
    {
        return null;
    }

    qoi_write_32(bytes, &p, QOI_MAGIC);
    qoi_write_32(bytes, &p, desc.width);
    qoi_write_32(bytes, &p, desc.height);
    bytes[p++] = desc.channels;
    bytes[p++] = desc.colorspace;

    pixels = cast(const(ubyte)*)data;

    memset(index.ptr, 0, 64 * qoi_rgba_t.sizeof);

    run = 0;
    px_prev.rgba.r = 0;
    px_prev.rgba.g = 0;
    px_prev.rgba.b = 0;
    px_prev.rgba.a = 255;
    px = px_prev;

    px_len = desc.width * desc.height * desc.channels;
    px_end = px_len - desc.channels;
    channels = desc.channels;

    for (px_pos = 0; px_pos < px_len; px_pos += channels) 
    {
        if (channels == 4) 
        {
            px = *cast(qoi_rgba_t *)(pixels + px_pos);
        }
        else {
            px.rgba.r = pixels[px_pos + 0];
            px.rgba.g = pixels[px_pos + 1];
            px.rgba.b = pixels[px_pos + 2];
        }

        if (px.v == px_prev.v) {
            run++;
            if (run == 62 || px_pos == px_end) {
                bytes[p++] = cast(ubyte)(QOI_OP_RUN | (run - 1));
                run = 0;
            }
        }
        else {
            int index_pos;

            if (run > 0) {
                bytes[p++] = cast(ubyte)(QOI_OP_RUN | (run - 1));
                run = 0;
            }

            index_pos = QOI_COLOR_HASH(px) % 64;

            if (index[index_pos].v == px.v) {
                bytes[p++] = cast(ubyte)(QOI_OP_INDEX | index_pos);
            }
            else {
                index[index_pos] = px;

                if (px.rgba.a == px_prev.rgba.a) {
                    byte vr = cast(byte)(px.rgba.r - px_prev.rgba.r);
                    byte vg = cast(byte)(px.rgba.g - px_prev.rgba.g);
                    byte vb = cast(byte)(px.rgba.b - px_prev.rgba.b);
                    byte vg_r = cast(byte)(vr - vg);
                    byte vg_b = cast(byte)(vb - vg);

                    if (
                        vr > -3 && vr < 2 &&
                        vg > -3 && vg < 2 &&
                        vb > -3 && vb < 2
                    ) {
                        bytes[p++] = cast(ubyte)(QOI_OP_DIFF | (vr + 2) << 4 | (vg + 2) << 2 | (vb + 2));
                    }
                    else if (
                        vg_r >  -9 && vg_r <  8 &&
                        vg   > -33 && vg   < 32 &&
                        vg_b >  -9 && vg_b <  8
                    ) {
                        bytes[p++] = cast(ubyte)(QOI_OP_LUMA     | (vg   + 32));
                        bytes[p++] = cast(ubyte)( (vg_r + 8) << 4 | (vg_b +  8) );
                    }
                    else {
                        bytes[p++] = QOI_OP_RGB;
                        bytes[p++] = px.rgba.r;
                        bytes[p++] = px.rgba.g;
                        bytes[p++] = px.rgba.b;
                    }
                }
                else {
                    bytes[p++] = QOI_OP_RGBA;
                    bytes[p++] = px.rgba.r;
                    bytes[p++] = px.rgba.g;
                    bytes[p++] = px.rgba.b;
                    bytes[p++] = px.rgba.a;
                }
            }
        }
        px_prev = px;
    }

    for (i = 0; i < cast(int)(qoi_padding.length); i++) 
    {
        bytes[p++] = qoi_padding[i];
    }

    *out_len = p;
    return bytes;
}


/** Decode a QOI image from memory.

The function either returns null on failure (invalid parameters or malloc
failed) or a pointer to the decoded pixels. On success, the qoi_desc struct
is filled with the description from the file header.

The returned pixel data should be free()d after use. */
void *qoi_decode(const void *data, int size, qoi_desc *desc, int channels) 
{
    const(ubyte)* bytes;
    uint header_magic;
    ubyte* pixels;
    qoi_rgba_t[64] index;
    qoi_rgba_t px;
    int px_len, chunks_len, px_pos;
    int p = 0, run = 0;

    if (
        data == null || desc == null ||
        (channels != 0 && channels != 3 && channels != 4) ||
        size < QOI_HEADER_SIZE + cast(int)(qoi_padding.sizeof)
    ) {
        return null;
    }

    bytes = cast(const(ubyte)*)data;

    header_magic = qoi_read_32(bytes, &p);
    desc.width = qoi_read_32(bytes, &p);
    desc.height = qoi_read_32(bytes, &p);
    desc.channels = bytes[p++];
    desc.colorspace = bytes[p++];

    if (
        desc.width == 0 || desc.height == 0 ||
        desc.channels < 3 || desc.channels > 4 ||
        desc.colorspace > 1 ||
        header_magic != QOI_MAGIC ||
        desc.height >= QOI_PIXELS_MAX / desc.width
    ) {
        return null;
    }

    if (channels == 0) {
        channels = desc.channels;
    }

    px_len = desc.width * desc.height * channels;
    pixels = cast(ubyte*) QOI_MALLOC(px_len);
    if (!pixels) {
        return null;
    }

    memset(index.ptr, 0, 64 * qoi_rgba_t.sizeof);
    px.rgba.r = 0;
    px.rgba.g = 0;
    px.rgba.b = 0;
    px.rgba.a = 255;

    chunks_len = size - cast(int)(qoi_padding.length);
    for (px_pos = 0; px_pos < px_len; px_pos += channels) {
        if (run > 0) {
            run--;
        }
        else if (p < chunks_len) {
            int b1 = bytes[p++];

            if (b1 == QOI_OP_RGB) {
                px.rgba.r = bytes[p++];
                px.rgba.g = bytes[p++];
                px.rgba.b = bytes[p++];
            }
            else if (b1 == QOI_OP_RGBA) {
                px.rgba.r = bytes[p++];
                px.rgba.g = bytes[p++];
                px.rgba.b = bytes[p++];
                px.rgba.a = bytes[p++];
            }
            else if ((b1 & QOI_MASK_2) == QOI_OP_INDEX) {
                px = index[b1];
            }
            else if ((b1 & QOI_MASK_2) == QOI_OP_DIFF) {
                px.rgba.r += ((b1 >> 4) & 0x03) - 2;
                px.rgba.g += ((b1 >> 2) & 0x03) - 2;
                px.rgba.b += ( b1       & 0x03) - 2;
            }
            else if ((b1 & QOI_MASK_2) == QOI_OP_LUMA) {
                int b2 = bytes[p++];
                int vg = (b1 & 0x3f) - 32;
                px.rgba.r += vg - 8 + ((b2 >> 4) & 0x0f);
                px.rgba.g += vg;
                px.rgba.b += vg - 8 +  (b2       & 0x0f);
            }
            else if ((b1 & QOI_MASK_2) == QOI_OP_RUN) {
                run = (b1 & 0x3f);
            }

            index[QOI_COLOR_HASH(px) % 64] = px;
        }

        if (channels == 4) {
            *cast(qoi_rgba_t*)(pixels + px_pos) = px;
        }
        else {
            pixels[px_pos + 0] = px.rgba.r;
            pixels[px_pos + 1] = px.rgba.g;
            pixels[px_pos + 2] = px.rgba.b;
        }
    }

    return pixels;
}

bool qoi_is_qoi_image(const(ubyte)[] imageData)
{
    if (imageData is null)
        return false;

    if (imageData.length < QOI_HEADER_SIZE)
        return false;

    int p = 0;
    uint header_magic = qoi_read_32(imageData.ptr, &p);
    return header_magic == QOI_MAGIC;
}