/// stb_image_write.h translations
/// Just the PNG encoder.
module dplug.graphics.stb_image_write;














/* stb_image_write - v1.16 - public domain - http://nothings.org/stb
   writes out PNG/BMP/TGA/JPEG/HDR images to C stdio - Sean Barrett 2010-2015
                                     no warranty implied; use at your own risk

   Before #including,

       #define STB_IMAGE_WRITE_IMPLEMENTATION

   in the file that you want to have the implementation.

   Will probably not work correctly with strict-aliasing optimizations.

ABOUT:

   This header file is a library for writing images to C stdio or a callback.

   The PNG output is not optimal; it is 20-50% larger than the file
   written by a decent optimizing implementation; though providing a custom
   zlib compress function (see STBIW_ZLIB_COMPRESS) can mitigate that.
   This library is designed for source code compactness and simplicity,
   not optimal image file size or run-time performance.


USAGE:

   There are one function:

     int stbi_write_bmp(char const *filename, int w, int h, int comp, const void *data);

   You can configure it with these global variables:
      int stbi_write_png_compression_level;    // defaults to 8; set to higher for more compression
      int stbi_write_force_png_filter;         // defaults to -1; set to 0..5 to force a filter mode

   Each function returns 0 on failure and non-0 on success.

   The functions create an image file defined by the parameters. The image
   is a rectangle of pixels stored from left-to-right, top-to-bottom.
   Each pixel contains 'comp' channels of data stored interleaved with 8-bits
   per channel, in the following order: 1=Y, 2=YA, 3=RGB, 4=RGBA. (Y is
   monochrome color.) The rectangle is 'w' pixels wide and 'h' pixels tall.
   The *data pointer points to the first byte of the top-left-most pixel.
   For PNG, "stride_in_bytes" is the distance in bytes from the first byte of
   a row of pixels to the first byte of the next row of pixels.

   PNG creates output files with the same number of components as the input.
   The BMP format expands Y to RGB in the file format and does not
   output alpha.

   PNG supports writing rectangles of data even when the bytes storing rows of
   data are not consecutive in memory (e.g. sub-rectangles of a larger image),
   by supplying the stride between the beginning of adjacent rows. The other
   formats do not. (Thus you cannot write a native-format BMP through the BMP
   writer, both because it is in BGR order and because it may have padding
   at the end of the line.)

   PNG allows you to set the deflate compression level by setting the global
   variable 'stbi_write_png_compression_level' (it defaults to 8).

CREDITS:


   Sean Barrett           -    PNG/BMP/TGA
   Baldur Karlsson        -    HDR
   Jean-Sebastien Guay    -    TGA monochrome
   Tim Kelsey             -    misc enhancements
   Alan Hickman           -    TGA RLE
   Emmanuel Julien        -    initial file IO callback implementation
   Jon Olick              -    original jo_jpeg.cpp code
   Daniel Gibson          -    integrate JPEG, allow external zlib
   Aarni Koskela          -    allow choosing PNG filter

   bugfixes:
      github:Chribba
      Guillaume Chereau
      github:jry2
      github:romigrou
      Sergio Gonzalez
      Jonas Karlsson
      Filip Wasil
      Thatcher Ulrich
      github:poppolopoppo
      Patrick Boettcher
      github:xeekworx
      Cap Petschulat
      Simon Rodriguez
      Ivan Tikhonov
      github:ignotion
      Adam Schackart
      Andrew Kensler

LICENSE

  See end of file for license information.

*/

import std.math: abs;
import core.stdc.stdlib: malloc, realloc, free;
import core.stdc.string: memcpy, memmove;
import dplug.graphics.image;

nothrow @nogc:

/// Create a PNG image from an ImageRef!RGBA.
/// The data has to be freed with `free()` or `freeSlice`.
ubyte[] convertImageRefToPNG(ImageRef!RGBA image)
{
    int width = image.w;
    int height = image.h;
    int channels = 4;
    int stride = cast(int)image.pitch;
    int len;
    ubyte *img = stbi_write_png_to_mem(cast(ubyte*) image.pixels, stride, width, height, channels, &len);
    return img[0..len];
}

/// Create a PNG image from an ImageRef!L8.
/// The data has to be freed with `free()` or `freeSlice`.
ubyte[] convertImageRefToPNG(ImageRef!L8 image)
{
    int width = image.w;
    int height = image.h;
    int channels = 1;
    int stride = cast(int)image.pitch;
    int len;
    ubyte *img = stbi_write_png_to_mem(cast(ubyte*) image.pixels, stride, width, height, channels, &len);
    return img[0..len];
}

private:

alias STBIW_MALLOC = malloc;
alias STBIW_REALLOC = realloc;
alias STBIW_FREE = free;
alias STBIW_MEMMOVE = memmove;

void* STBIW_REALLOC_SIZED(void *ptr, size_t oldsz, size_t newsz)
{
    return realloc(ptr, newsz);
}

ubyte STBIW_UCHAR(int x)
{
    return cast(ubyte)(x);
}

enum int stbi_write_png_compression_level = 8;
enum int stbi_write_force_png_filter = -1;

// Useful?
enum int stbi__flip_vertically_on_write = 0;


alias stbiw_uint32 = uint;

//////////////////////////////////////////////////////////////////////////////
//
// PNG writer
//

// stretchy buffer; stbiw__sbpush() == vector<>::push_back() -- stbiw__sbcount() == vector<>::size()
int* stbiw__sbraw(void* a)
{
    return (cast(int *)a) - 2;
}

ref int stbiw__sbm(void* a) 
{
    return stbiw__sbraw(a)[0]; // this place stores count of items
}

ref int stbiw__sbn(void* a)
{
    return stbiw__sbraw(a)[1]; // this place stores capacity of items
}

bool stbiw__sbneedgrow(void* a, int n)
{
    return (a == null) || ( stbiw__sbn(a) + n >= stbiw__sbm(a) );
}

void stbiw__sbmaybegrow(T)(ref T* a, int n)
{
    if (stbiw__sbneedgrow(a,n))
        stbiw__sbgrow(a,n);
}

void stbiw__sbgrow(T)(ref T* a, int n)
{
    stbiw__sbgrowf(cast(void **) &a, n, T.sizeof);
}

void stbiw__sbpush(T)(ref T* a, T v)
{
    stbiw__sbmaybegrow!T(a, 1);
    a[stbiw__sbn(a)++] = v;
}

int stbiw__sbcount(void* a)
{
    if (a)
        return stbiw__sbn(a);
    else
        return 0;
}

void stbiw__sbfree(void* a)
{
    if (a) STBIW_FREE(stbiw__sbraw(a));
}


void *stbiw__sbgrowf(void **arr, int increment, int itemsize)
{
    int m = *arr ? ( 2*stbiw__sbm(*arr)+increment ) : increment+1;
    void *p = STBIW_REALLOC_SIZED(*arr ? stbiw__sbraw(*arr) : null, *arr ? (stbiw__sbm(*arr)*itemsize + int.sizeof*2) : 0, itemsize * m + int.sizeof*2);
    assert(p);
    if (!*arr) (cast(int *) p)[1] = 0;
    *arr = cast(void *) (cast(int *) p + 2);
    stbiw__sbm(*arr) = m;
    return *arr;
}

unittest
{
    int* a = null;
    assert(stbiw__sbcount(a) == 0);
    stbiw__sbpush(a, 2);
    assert(a[0] == 2);
    stbiw__sbfree(a);
}

ubyte *stbiw__zlib_flushf(ubyte *data, uint *bitbuffer, int *bitcount)
{
   while (*bitcount >= 8) {
      stbiw__sbpush(data, STBIW_UCHAR(*bitbuffer));
      *bitbuffer >>= 8;
      *bitcount -= 8;
   }
   return data;
}

int stbiw__zlib_bitrev(int code, int codebits)
{
   int res=0;
   while (codebits--) {
      res = (res << 1) | (code & 1);
      code >>= 1;
   }
   return res;
}

uint stbiw__zlib_countm(ubyte* a, ubyte * b, int limit)
{
   int i;
   for (i=0; i < limit && i < 258; ++i)
      if (a[i] != b[i]) break;
   return i;
}

uint stbiw__zhash(ubyte *data)
{
    stbiw_uint32 hash = data[0] + (data[1] << 8) + (data[2] << 16);
    hash ^= hash << 3;
    hash += hash >> 5;
    hash ^= hash << 4;
    hash += hash >> 17;
    hash ^= hash << 25;
    hash += hash >> 6;
    return hash;
}


enum stbiw__ZHASH = 16384;


ubyte * stbi_zlib_compress(ubyte *data, int data_len, int *out_len, int quality)
{
    static immutable ushort[30] lengthc = 
    [ 3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258, 259 ];
    static immutable ubyte[29] lengtheb = 
    [ 0,0,0,0,0,0,0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4,  4,  5,  5,  5,  5,  0 ];
    static immutable ushort[31] distc   = 
    [ 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577, 32768 ];
    static immutable ubyte[30] disteb  = 
    [ 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13 ];
    uint bitbuf=0;
    int i,j, bitcount=0;
    ubyte *out_ = null;
    ubyte ***hash_table = cast(ubyte***) STBIW_MALLOC(stbiw__ZHASH * (ubyte**).sizeof);
    if (hash_table == null)
        return null;
    if (quality < 5) quality = 5;

    stbiw__sbpush(out_, 0x78);   // DEFLATE 32K window
    stbiw__sbpush(out_, 0x5e);   // FLEVEL = 1

    void stbiw__zlib_flush() nothrow @nogc
    {
        out_ = stbiw__zlib_flushf(out_, &bitbuf, &bitcount);
    }

    void stbiw__zlib_add(int code, int codebits) nothrow @nogc
    {
       bitbuf |= code << bitcount;
       bitcount += codebits;
       stbiw__zlib_flush();
    }

    void stbiw__zlib_huffa(int b, int c)
    {
        stbiw__zlib_add(stbiw__zlib_bitrev(b,c),c);
    }
    // default huffman tables
    void stbiw__zlib_huff1(int n)
    {
         stbiw__zlib_huffa(0x30 + (n), 8);

    } 
    void stbiw__zlib_huff2(int n)
    {
         stbiw__zlib_huffa(0x190 + (n)-144, 9);

    } 
    void stbiw__zlib_huff3(int n)
    {
         stbiw__zlib_huffa(0 + (n)-256,7);

    } 
    void stbiw__zlib_huff4(int n)
    {
         stbiw__zlib_huffa(0xc0 + (n)-280,8);
    }

    void stbiw__zlib_huff(int n)
    {
         ((n) <= 143 ? stbiw__zlib_huff1(n) : (n) <= 255 ? stbiw__zlib_huff2(n) : (n) <= 279 ? stbiw__zlib_huff3(n) : stbiw__zlib_huff4(n));
    } 

    void stbiw__zlib_huffb(int n)
    {
        ((n) <= 143 ? stbiw__zlib_huff1(n) : stbiw__zlib_huff2(n));
    }

    stbiw__zlib_add(1,1);  // BFINAL = 1
    stbiw__zlib_add(1,2);  // BTYPE = 1 -- fixed huffman

    for (i=0; i < stbiw__ZHASH; ++i)
        hash_table[i] = null;

    i=0;
    while (i < data_len-3) 
    {
      // hash next 3 bytes of data to be compressed
      int h = stbiw__zhash(data+i)&(stbiw__ZHASH-1), best=3;
      ubyte *bestloc = null;
      ubyte **hlist = hash_table[h];
      int n = stbiw__sbcount(hlist);
      for (j=0; j < n; ++j) {
         if (hlist[j]-data > i-32768) { // if entry lies within window
            int d = stbiw__zlib_countm(hlist[j], data+i, data_len-i);
            if (d >= best) { best=d; bestloc=hlist[j]; }
         }
      }
      // when hash table entry is too long, delete half the entries
      if (hash_table[h] && stbiw__sbn(hash_table[h]) == 2*quality) {
         STBIW_MEMMOVE(hash_table[h], hash_table[h]+quality, (hash_table[h][0]).sizeof * quality);
         stbiw__sbn(hash_table[h]) = quality;
      }
      stbiw__sbpush(hash_table[h],data+i);

      if (bestloc) {
         // "lazy matching" - check match at *next* byte, and if it's better, do cur byte as literal
         h = stbiw__zhash(data+i+1)&(stbiw__ZHASH-1);
         hlist = hash_table[h];
         n = stbiw__sbcount(hlist);
         for (j=0; j < n; ++j) {
            if (hlist[j]-data > i-32767) {
               int e = stbiw__zlib_countm(hlist[j], data+i+1, data_len-i-1);
               if (e > best) { // if next match is better, bail on current match
                  bestloc = null;
                  break;
               }
            }
         }
      }

      if (bestloc) {
         int d = cast(int) (data+i - bestloc); // distance back
         assert(d <= 32767 && best <= 258);
         for (j=0; best > lengthc[j+1]-1; ++j) { }
         stbiw__zlib_huff(j+257);
         if (lengtheb[j]) stbiw__zlib_add(best - lengthc[j], lengtheb[j]);
         for (j=0; d > distc[j+1]-1; ++j) { }
         stbiw__zlib_add(stbiw__zlib_bitrev(j,5),5);
         if (disteb[j]) stbiw__zlib_add(d - distc[j], disteb[j]);
         i += best;
      } else {
         stbiw__zlib_huffb(data[i]);
         ++i;
      }
   }
   // write out final bytes
   for (;i < data_len; ++i)
      stbiw__zlib_huffb(data[i]);
   stbiw__zlib_huff(256); // end of block
   // pad with 0 bits to byte boundary
   while (bitcount)
      stbiw__zlib_add(0,1);

   for (i=0; i < stbiw__ZHASH; ++i)
   {
       stbiw__sbfree(hash_table[i]);
   }
   STBIW_FREE(hash_table);

   // store uncompressed instead if compression was worse
   if (stbiw__sbn(out_) > data_len + 2 + ((data_len+32766)/32767)*5) {
      stbiw__sbn(out_) = 2;  // truncate to DEFLATE 32K window and FLEVEL = 1
      for (j = 0; j < data_len;) {
         int blocklen = data_len - j;
         if (blocklen > 32767) blocklen = 32767;
         stbiw__sbpush(out_, data_len - j == blocklen); // BFINAL = ?, BTYPE = 0 -- no compression
         stbiw__sbpush(out_, STBIW_UCHAR(blocklen)); // LEN
         stbiw__sbpush(out_, STBIW_UCHAR(blocklen >> 8));
         stbiw__sbpush(out_, STBIW_UCHAR(~blocklen)); // NLEN
         stbiw__sbpush(out_, STBIW_UCHAR(~blocklen >> 8));
         memcpy(out_+stbiw__sbn(out_), data+j, blocklen);
         stbiw__sbn(out_) += blocklen;
         j += blocklen;
      }
   }

   {
      // compute adler32 on input
      uint s1=1, s2=0;
      int blocklen = cast(int) (data_len % 5552);
      j=0;
      while (j < data_len) {
         for (i=0; i < blocklen; ++i) { s1 += data[j+i]; s2 += s1; }
         s1 %= 65521; s2 %= 65521;
         j += blocklen;
         blocklen = 5552;
      }
      stbiw__sbpush(out_, STBIW_UCHAR(s2 >> 8));
      stbiw__sbpush(out_, STBIW_UCHAR(s2));
      stbiw__sbpush(out_, STBIW_UCHAR(s1 >> 8));
      stbiw__sbpush(out_, STBIW_UCHAR(s1));
   }
   *out_len = stbiw__sbn(out_);
   // make returned pointer freeable
   STBIW_MEMMOVE(stbiw__sbraw(out_), out_, *out_len);
   return cast(ubyte *) stbiw__sbraw(out_);
}

static uint stbiw__crc32(ubyte *buffer, int len)
{
    static immutable uint[256] crc_table =
    [
        0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
        0x0eDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
        0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
        0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
        0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
        0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
        0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
        0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
        0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
        0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
        0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
        0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
        0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
        0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
        0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
        0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
        0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
        0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
        0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
        0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
        0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
        0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
        0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
        0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
        0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
        0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
        0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
        0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
        0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
        0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
        0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
        0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
    ];

    uint crc = ~0u;
    int i;
    for (i=0; i < len; ++i)
        crc = (crc >> 8) ^ crc_table[buffer[i] ^ (crc & 0xff)];
    return ~crc;
}

void stbiw__wpng4(ref ubyte* o, ubyte a, ubyte b, ubyte c, ubyte d)
{
    o[0] = a;
    o[1] = b;
    o[2] = c;
    o[3] = d;
    o += 4;
}

void stbiw__wp32(ref ubyte* data, uint v)
{
    stbiw__wpng4(data, v >> 24, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff);
}

void stbiw__wptag(ref ubyte* data, char[4] s)
{
    stbiw__wpng4(data, s[0], s[1], s[2], s[3]);
}

static void stbiw__wpcrc(ubyte **data, int len)
{
   uint crc = stbiw__crc32(*data - len - 4, len+4);
   stbiw__wp32(*data, crc);
}

ubyte stbiw__paeth(int a, int b, int c)
{
   int p = a + b - c, pa = abs(p-a), pb = abs(p-b), pc = abs(p-c);
   if (pa <= pb && pa <= pc) return STBIW_UCHAR(a);
   if (pb <= pc) return STBIW_UCHAR(b);
   return STBIW_UCHAR(c);
}

// @OPTIMIZE: provide an option that always forces left-predict or paeth predict
static void stbiw__encode_png_line(ubyte *pixels, int stride_bytes, int width, int height, int y, int n, int filter_type, byte* line_buffer)
{
   static immutable int[5] mapping  = [ 0,1,2,3,4 ];
   static immutable int[5] firstmap = [ 0,1,0,5,6 ];
   immutable(int)* mymap = (y != 0) ? mapping.ptr : firstmap.ptr;
   int i;
   int type = mymap[filter_type];
   ubyte *z = pixels + stride_bytes * (stbi__flip_vertically_on_write ? height-1-y : y);
   int signed_stride = stbi__flip_vertically_on_write ? -stride_bytes : stride_bytes;

   if (type==0) {
      memcpy(line_buffer, z, width*n);
      return;
   }

   // first loop isn't optimized since it's just one pixel
   for (i = 0; i < n; ++i) {
      switch (type) {
         case 1: line_buffer[i] = z[i]; break;
         case 2: line_buffer[i] = cast(byte)(z[i] - z[i-signed_stride]); break;
         case 3: line_buffer[i] = cast(byte)(z[i] - (z[i-signed_stride]>>1)); break;
         case 4: line_buffer[i] = cast(byte) (z[i] - stbiw__paeth(0,z[i-signed_stride],0)); break;
         case 5: line_buffer[i] = z[i]; break;
         case 6: line_buffer[i] = z[i]; break;
         default: assert(0);
      }
   }
   switch (type) {
      case 1: for (i=n; i < width*n; ++i) line_buffer[i] = cast(byte)(z[i] - z[i-n]); break;
      case 2: for (i=n; i < width*n; ++i) line_buffer[i] = cast(byte)(z[i] - z[i-signed_stride]); break;
      case 3: for (i=n; i < width*n; ++i) line_buffer[i] = cast(byte)(z[i] - ((z[i-n] + z[i-signed_stride])>>1)); break;
      case 4: for (i=n; i < width*n; ++i) line_buffer[i] = cast(byte)(z[i] - stbiw__paeth(z[i-n], z[i-signed_stride], z[i-signed_stride-n])); break;
      case 5: for (i=n; i < width*n; ++i) line_buffer[i] = cast(byte)(z[i] - (z[i-n]>>1)); break;
      case 6: for (i=n; i < width*n; ++i) line_buffer[i] = cast(byte)(z[i] - stbiw__paeth(z[i-n], 0,0)); break;
      default: assert(0);
   }
}

ubyte *stbi_write_png_to_mem(const(ubyte*) pixels, int stride_bytes, int x, int y, int n, int *out_len)
{
    int force_filter = stbi_write_force_png_filter;
    static immutable int[5] ctype = [ -1, 0, 4, 2, 6 ];
    static immutable ubyte[8] sig = [ 137,80,78,71,13,10,26,10 ];
    ubyte *out_, o, filt, zlib;
    byte* line_buffer;
    int j, zlen;

    if (stride_bytes == 0)
        stride_bytes = x * n;

    if (force_filter >= 5) 
    {
        force_filter = -1;
    }

    filt = cast(ubyte *) STBIW_MALLOC((x*n+1) * y); 
    if (!filt) 
        return null;
    line_buffer = cast(byte *) STBIW_MALLOC(x * n); 
    if (!line_buffer) 
    { 
        STBIW_FREE(filt); 
        return null; 
    }

   for (j=0; j < y; ++j) 
   {
      int filter_type;
      if (force_filter > -1) {
         filter_type = force_filter;
         stbiw__encode_png_line(cast(ubyte*)(pixels), stride_bytes, x, y, j, n, force_filter, line_buffer);
      } else { // Estimate the best filter by running through all of them:
         int best_filter = 0, best_filter_val = 0x7fffffff, est, i;
         for (filter_type = 0; filter_type < 5; filter_type++) {
            stbiw__encode_png_line(cast(ubyte*)(pixels), stride_bytes, x, y, j, n, filter_type, line_buffer);

            // Estimate the entropy of the line using this filter; the less, the better.
            est = 0;
            for (i = 0; i < x*n; ++i) {
               est += abs(line_buffer[i]);
            }
            if (est < best_filter_val) {
               best_filter_val = est;
               best_filter = filter_type;
            }
         }
         if (filter_type != best_filter) {  // If the last iteration already got us the best filter, don't redo it
            stbiw__encode_png_line(cast(ubyte*)(pixels), stride_bytes, x, y, j, n, best_filter, line_buffer);
            filter_type = best_filter;
         }
      }
      // when we get here, filter_type contains the filter type, and line_buffer contains the data
      filt[j*(x*n+1)] = cast(ubyte) filter_type;
      STBIW_MEMMOVE(filt+j*(x*n+1)+1, line_buffer, x*n);
   }
   STBIW_FREE(line_buffer);
   zlib = stbi_zlib_compress(filt, y*( x*n+1), &zlen, stbi_write_png_compression_level);
   STBIW_FREE(filt);
   if (!zlib) 
       return null;

   // each tag requires 12 bytes of overhead
   out_ = cast(ubyte *) STBIW_MALLOC(8 + 12+13 + 12+zlen + 12);
   if (!out_) return null;
   *out_len = 8 + 12+13 + 12+zlen + 12;

   o = out_;
   STBIW_MEMMOVE(o, sig.ptr, 8); 
   o+= 8;
   stbiw__wp32(o, 13); // header length
   stbiw__wptag(o, "IHDR");
   stbiw__wp32(o, x);
   stbiw__wp32(o, y);
   *o++ = 8;
   *o++ = STBIW_UCHAR(ctype[n]);
   *o++ = 0;
   *o++ = 0;
   *o++ = 0;
   stbiw__wpcrc(&o,13);

   stbiw__wp32(o, zlen);
   stbiw__wptag(o, "IDAT");
   STBIW_MEMMOVE(o, zlib, zlen);
   o += zlen;
   STBIW_FREE(zlib);
   stbiw__wpcrc(&o, zlen);

   stbiw__wp32(o,0);
   stbiw__wptag(o, "IEND");
   stbiw__wpcrc(&o,0);

   assert(o == out_ + *out_len);

   return out_;
}


/* Revision history
      1.16  (2021-07-11)
             make Deflate code emit uncompressed blocks when it would otherwise expand
             support writing BMPs with alpha channel
      1.15  (2020-07-13) unknown
      1.14  (2020-02-02) updated JPEG writer to downsample chroma channels
      1.13
      1.12
      1.11  (2019-08-11)

      1.10  (2019-02-07)
             support utf8 filenames in Windows; fix warnings and platform ifdefs
      1.09  (2018-02-11)
             fix typo in zlib quality API, improve STB_I_W_STATIC in C++
      1.08  (2018-01-29)
             add stbi__flip_vertically_on_write, external zlib, zlib quality, choose PNG filter
      1.07  (2017-07-24)
             doc fix
      1.06 (2017-07-23)
             writing JPEG (using Jon Olick's code)
      1.05   ???
      1.04 (2017-03-03)
             monochrome BMP expansion
      1.03   ???
      1.02 (2016-04-02)
             avoid allocating large structures on the stack
      1.01 (2016-01-16)
             STBIW_REALLOC_SIZED: support allocators with no realloc support
             avoid race-condition in crc initialization
             minor compile issues
      1.00 (2015-09-14)
             installable file IO function
      0.99 (2015-09-13)
             warning fixes; TGA rle support
      0.98 (2015-04-08)
             added STBIW_MALLOC, STBIW_ASSERT etc
      0.97 (2015-01-18)
             fixed HDR asserts, rewrote HDR rle logic
      0.96 (2015-01-17)
             add HDR output
             fix monochrome BMP
      0.95 (2014-08-17)
             add monochrome TGA output
      0.94 (2014-05-31)
             rename private functions to avoid conflicts with stb_image.h
      0.93 (2014-05-27)
             warning fixes
      0.92 (2010-08-01)
             casts to unsigned char to fix warnings
      0.91 (2010-07-17)
             first public release
      0.90   first internal release
*/

/*
------------------------------------------------------------------------------
This software is available under 2 licenses -- choose whichever you prefer.
------------------------------------------------------------------------------
ALTERNATIVE A - MIT License
Copyright (c) 2017 Sean Barrett
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
------------------------------------------------------------------------------
ALTERNATIVE B - Public Domain (www.unlicense.org)
This is free and unencumbered software released into the public domain.
Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means.
In jurisdictions that recognize copyright laws, the author or authors of this
software dedicate any and all copyright interest in the software to the public
domain. We make this dedication for the benefit of the public at large and to
the detriment of our heirs and successors. We intend this dedication to be an
overt act of relinquishment in perpetuity of all present and future rights to
this software under copyright law.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
------------------------------------------------------------------------------
*/
