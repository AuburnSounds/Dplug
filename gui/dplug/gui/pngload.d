/// D translation of stb_image-1.33 (http://nothings.org/stb_image.c)
///
/// This port only supports:
/// $(UL
///   $(LI PNG 8-bit-per-channel only.)
/// )
///
//============================    Contributors    =========================
//
// Image formats                                Optimizations & bugfixes
// Sean Barrett (jpeg, png, bmp)                Fabian "ryg" Giesen
// Nicolas Schulz (hdr, psd)
// Jonathan Dummer (tga)                     Bug fixes & warning fixes
// Jean-Marc Lienher (gif)                      Marc LeBlanc
// Tom Seddon (pic)                             Christpher Lloyd
// Thatcher Ulrich (psd)                        Dave Moore
// Won Chun
// the Horde3D community
// Extensions, features                            Janez Zemva
// Jetro Lauha (stbi_info)                      Jonathan Blow
// James "moose2000" Brown (iPhone PNG)         Laurent Gomila
// Ben "Disch" Wenger (io callbacks)            Aruelien Pocheville
// Martin "SpartanJ" Golini                     Ryamond Barbiero
// David Woo

module dplug.gui.pngload;

// This has been revived for the sake of loading PNG without too much memory usage.
// It turns out stb_image is more efficient than the loaders using std.zlib.
// https://github.com/lgvz/imageformats/issues/26

import core.stdc.stdlib;
import core.stdc.string;

enum STBI_VERSION = 1;

/// The exception type thrown when loading an image failed.
class STBImageException : Exception
{
    public
    {
        @safe pure nothrow this(string message, string file =__FILE__, size_t line = __LINE__, Throwable next = null)
        {
            super(message, file, line, next);
        }
    }
}

enum : int
{
   STBI_default    = 0, // only used for req_comp
   STBI_grey       = 1,
   STBI_grey_alpha = 2,
   STBI_rgb        = 3,
   STBI_rgb_alpha  = 4
};

// define faster low-level operations (typically SIMD support)

// stbi structure is our basic context used by all images, so it
// contains all the IO context, plus some basic image information
struct stbi
{
   uint img_x, img_y;
   int img_n, img_out_n;

   int buflen;
   ubyte[128] buffer_start;

   const(ubyte) *img_buffer;
   const(ubyte) *img_buffer_end;
   const(ubyte) *img_buffer_original;
}


// initialize a memory-decode context
void start_mem(stbi *s, const(ubyte)*buffer, int len)
{
   s.img_buffer = buffer;
   s.img_buffer_original = buffer;
   s.img_buffer_end = buffer+len;
}

/// Loads an image from memory.
/// Throws: STBImageException on error.
ubyte* stbi_load_png_from_memory(const(void)[] buffer, out int width, out int height, out int components, int requestedComponents)
{
   stbi s;
   start_mem(&s, cast(const(ubyte)*)buffer.ptr, cast(int)(buffer.length));
   return stbi_png_load(&s, &width, &height, &components, requestedComponents);
}

/// Frees an image loaded by stb_image.
void stbi_image_free(void *retval_from_stbi_load)
{
    free(retval_from_stbi_load);
}

//
// Common code used by all image loaders
//

enum : int
{
   SCAN_load=0,
   SCAN_type,
   SCAN_header
};


int get8(stbi *s)
{
   if (s.img_buffer < s.img_buffer_end)
      return *s.img_buffer++;

   return 0;
}

int at_eof(stbi *s)
{
   return s.img_buffer >= s.img_buffer_end;
}

ubyte get8u(stbi *s)
{
   return cast(ubyte) get8(s);
}

void skip(stbi *s, int n)
{
   s.img_buffer += n;
}

int getn(stbi *s, ubyte *buffer, int n)
{
   if (s.img_buffer+n <= s.img_buffer_end) {
      memcpy(buffer, s.img_buffer, n);
      s.img_buffer += n;
      return 1;
   } else
      return 0;
}

int get16(stbi *s)
{
   int z = get8(s);
   return (z << 8) + get8(s);
}

uint get32(stbi *s)
{
   uint z = get16(s);
   return (z << 16) + get16(s);
}

int get16le(stbi *s)
{
   int z = get8(s);
   return z + (get8(s) << 8);
}

uint get32le(stbi *s)
{
   uint z = get16le(s);
   return z + (get16le(s) << 16);
}

//
//  generic converter from built-in img_n to req_comp
//    individual types do this automatically as much as possible (e.g. jpeg
//    does all cases internally since it needs to colorspace convert anyway,
//    and it never has alpha, so very few cases ). png can automatically
//    interleave an alpha=255 channel, but falls back to this for other cases
//
//  assume data buffer is malloced, so malloc a new one and free that one
//  only failure mode is malloc failing

ubyte compute_y(int r, int g, int b)
{
   return cast(ubyte) (((r*77) + (g*150) +  (29*b)) >> 8);
}

ubyte *convert_format(ubyte *data, int img_n, int req_comp, uint x, uint y)
{
    int i,j;
    ubyte *good;

    if (req_comp == img_n) return data;
    assert(req_comp >= 1 && req_comp <= 4);

    good = cast(ubyte*) malloc(req_comp * x * y);
    if (good == null) {
        free(data);
        throw new STBImageException("Out of memory");
    }

    for (j=0; j < cast(int) y; ++j) {
        ubyte *src  = data + j * x * img_n   ;
        ubyte *dest = good + j * x * req_comp;

        // convert source image with img_n components to one with req_comp components;
        // avoid switch per pixel, so use switch per scanline and massive macros
        switch (img_n * 8 + req_comp)
        {
            case 1 * 8 + 2:
                for(i=x-1; i >= 0; --i, src += 1, dest += 2)
                    dest[0] = src[0], dest[1] = 255;
                break;
            case 1 * 8 + 3:
                for(i=x-1; i >= 0; --i, src += 1, dest += 3)
                    dest[0]=dest[1]=dest[2]=src[0];
                break;
            case 1 * 8 + 4:
                for(i=x-1; i >= 0; --i, src += 1, dest += 4)
                    dest[0]=dest[1]=dest[2]=src[0], dest[3]=255;
                break;
            case 2 * 8 + 1:
                for(i=x-1; i >= 0; --i, src += 2, dest += 1)
                    dest[0]=src[0];
                break;
            case 2 * 8 + 3:
                for(i=x-1; i >= 0; --i, src += 2, dest += 3)
                    dest[0]=dest[1]=dest[2]=src[0];
                break;
            case 2 * 8 + 4:
                for(i=x-1; i >= 0; --i, src += 2, dest += 4)
                    dest[0]=dest[1]=dest[2]=src[0], dest[3]=src[1];
                break;
            case 3 * 8 + 4:
                for(i=x-1; i >= 0; --i, src += 3, dest += 4)
                    dest[0]=src[0],dest[1]=src[1],dest[2]=src[2],dest[3]=255;
                break;
            case 3 * 8 + 1:
                for(i=x-1; i >= 0; --i, src += 3, dest += 1)
                    dest[0]=compute_y(src[0],src[1],src[2]);
                break;
            case 3 * 8 + 2:
                for(i=x-1; i >= 0; --i, src += 3, dest += 2)
                    dest[0]=compute_y(src[0],src[1],src[2]), dest[1] = 255;
                break;
            case 4 * 8 + 1:
                for(i=x-1; i >= 0; --i, src += 4, dest += 1)
                    dest[0]=compute_y(src[0],src[1],src[2]);
                break;
            case 4 * 8 + 2:
                for(i=x-1; i >= 0; --i, src += 4, dest += 2)
                    dest[0]=compute_y(src[0],src[1],src[2]), dest[1] = src[3];
                break;
            case 4 * 8 + 3:
                for(i=x-1; i >= 0; --i, src += 4, dest += 3)
                    dest[0]=src[0],dest[1]=src[1],dest[2]=src[2];
                break;
            default: assert(0);
        }
    }

    free(data);
    return good;
}

// public domain zlib decode    v0.2  Sean Barrett 2006-11-18
//    simple implementation
//      - all input must be provided in an upfront buffer
//      - all output is written to a single output buffer (can malloc/realloc)
//    performance
//      - fast huffman

// fast-way is faster to check than jpeg huffman, but slow way is slower
enum ZFAST_BITS = 9; // accelerate all cases in default tables
enum ZFAST_MASK = ((1 << ZFAST_BITS) - 1);

// zlib-style huffman encoding
// (jpegs packs from left, zlib from right, so can't share code)
struct zhuffman
{
   ushort[1 << ZFAST_BITS] fast;
   ushort[16] firstcode;
   int[17] maxcode;
   ushort[16] firstsymbol;
   ubyte[288] size;
   ushort[288] value;
} ;

int bitreverse16(int n)
{
  n = ((n & 0xAAAA) >>  1) | ((n & 0x5555) << 1);
  n = ((n & 0xCCCC) >>  2) | ((n & 0x3333) << 2);
  n = ((n & 0xF0F0) >>  4) | ((n & 0x0F0F) << 4);
  n = ((n & 0xFF00) >>  8) | ((n & 0x00FF) << 8);
  return n;
}

int bit_reverse(int v, int bits)
{
   assert(bits <= 16);
   // to bit reverse n bits, reverse 16 and shift
   // e.g. 11 bits, bit reverse and shift away 5
   return bitreverse16(v) >> (16-bits);
}

int zbuild_huffman(zhuffman *z, ubyte *sizelist, int num)
{
   int i,k=0;
   int code;
   int[16] next_code;
   int[17] sizes;

   // DEFLATE spec for generating codes
   memset(sizes.ptr, 0, sizes.sizeof);
   memset(z.fast.ptr, 255, z.fast.sizeof);
   for (i=0; i < num; ++i)
      ++sizes[sizelist[i]];
   sizes[0] = 0;
   for (i=1; i < 16; ++i)
      assert(sizes[i] <= (1 << i));
   code = 0;
   for (i=1; i < 16; ++i) {
      next_code[i] = code;
      z.firstcode[i] = cast(ushort) code;
      z.firstsymbol[i] = cast(ushort) k;
      code = (code + sizes[i]);
      if (sizes[i])
         if (code-1 >= (1 << i))
            throw new STBImageException("Bad codelength, corrupt JPEG");
      z.maxcode[i] = code << (16-i); // preshift for inner loop
      code <<= 1;
      k += sizes[i];
   }
   z.maxcode[16] = 0x10000; // sentinel
   for (i=0; i < num; ++i) {
      int s = sizelist[i];
      if (s) {
         int c = next_code[s] - z.firstcode[s] + z.firstsymbol[s];
         z.size[c] = cast(ubyte)s;
         z.value[c] = cast(ushort)i;
         if (s <= ZFAST_BITS) {
            int k_ = bit_reverse(next_code[s],s);
            while (k_ < (1 << ZFAST_BITS)) {
               z.fast[k_] = cast(ushort) c;
               k_ += (1 << s);
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

struct zbuf
{
   const(ubyte) *zbuffer;
   const(ubyte) *zbuffer_end;
   int num_bits;
   uint code_buffer;

   ubyte *zout;
   ubyte *zout_start;
   ubyte *zout_end;
   int   z_expandable;

   zhuffman z_length, z_distance;
} ;

int zget8(zbuf *z)
{
   if (z.zbuffer >= z.zbuffer_end) return 0;
   return *z.zbuffer++;
}

void fill_bits(zbuf *z)
{
   do {
      assert(z.code_buffer < (1U << z.num_bits));
      z.code_buffer |= zget8(z) << z.num_bits;
      z.num_bits += 8;
   } while (z.num_bits <= 24);
}

uint zreceive(zbuf *z, int n)
{
   uint k;
   if (z.num_bits < n) fill_bits(z);
   k = z.code_buffer & ((1 << n) - 1);
   z.code_buffer >>= n;
   z.num_bits -= n;
   return k;
}

int zhuffman_decode(zbuf *a, zhuffman *z)
{
   int b,s,k;
   if (a.num_bits < 16) fill_bits(a);
   b = z.fast[a.code_buffer & ZFAST_MASK];
   if (b < 0xffff) {
      s = z.size[b];
      a.code_buffer >>= s;
      a.num_bits -= s;
      return z.value[b];
   }

   // not resolved by fast table, so compute it the slow way
   // use jpeg approach, which requires MSbits at top
   k = bit_reverse(a.code_buffer, 16);
   for (s=ZFAST_BITS+1; ; ++s)
      if (k < z.maxcode[s])
         break;
   if (s == 16) return -1; // invalid code!
   // code size is s, so:
   b = (k >> (16-s)) - z.firstcode[s] + z.firstsymbol[s];
   assert(z.size[b] == s);
   a.code_buffer >>= s;
   a.num_bits -= s;
   return z.value[b];
}

int expand(zbuf *z, int n)  // need to make room for n bytes
{
   ubyte *q;
   int cur, limit;
   if (!z.z_expandable)
      throw new STBImageException("Output buffer limit, corrupt PNG");
   cur   = cast(int) (z.zout     - z.zout_start);
   limit = cast(int) (z.zout_end - z.zout_start);
   while (cur + n > limit)
      limit *= 2;
   q = cast(ubyte*) realloc(z.zout_start, limit);
   if (q == null)
      throw new STBImageException("Out of memory");
   z.zout_start = q;
   z.zout       = q + cur;
   z.zout_end   = q + limit;
   return 1;
}

static immutable int[31] length_base = [
   3,4,5,6,7,8,9,10,11,13,
   15,17,19,23,27,31,35,43,51,59,
   67,83,99,115,131,163,195,227,258,0,0 ];

static immutable int[31] length_extra =
[ 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0 ];

static immutable int[32] dist_base = [ 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577,0,0];

static immutable int[32] dist_extra =
[ 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];

int parse_huffman_block(zbuf *a)
{
   for(;;) {
      int z = zhuffman_decode(a, &a.z_length);
      if (z < 256) {
         if (z < 0)
             throw new STBImageException("Bad Huffman code, corrupt PNG");
         if (a.zout >= a.zout_end) if (!expand(a, 1)) return 0;
         *a.zout++ = cast(ubyte) z;
      } else {
         ubyte *p;
         int len,dist;
         if (z == 256) return 1;
         z -= 257;
         len = length_base[z];
         if (length_extra[z]) len += zreceive(a, length_extra[z]);
         z = zhuffman_decode(a, &a.z_distance);
         if (z < 0) throw new STBImageException("Bad Huffman code, corrupt PNG");
         dist = dist_base[z];
         if (dist_extra[z]) dist += zreceive(a, dist_extra[z]);
         if (a.zout - a.zout_start < dist) throw new STBImageException("Bad dist, corrupt PNG");
         if (a.zout + len > a.zout_end) if (!expand(a, len)) return 0;
         p = a.zout - dist;
         while (len--)
            *a.zout++ = *p++;
      }
   }
}

int compute_huffman_codes(zbuf *a)
{
   static immutable ubyte[19] length_dezigzag = [ 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15 ];
   zhuffman z_codelength;
   ubyte[286+32+137] lencodes;//padding for maximum single op
   ubyte[19] codelength_sizes;
   int i,n;

   int hlit  = zreceive(a,5) + 257;
   int hdist = zreceive(a,5) + 1;
   int hclen = zreceive(a,4) + 4;

   memset(codelength_sizes.ptr, 0, codelength_sizes.sizeof);
   for (i=0; i < hclen; ++i) {
      int s = zreceive(a,3);
      codelength_sizes[length_dezigzag[i]] = cast(ubyte) s;
   }
   if (!zbuild_huffman(&z_codelength, codelength_sizes.ptr, 19)) return 0;

   n = 0;
   while (n < hlit + hdist) {
      int c = zhuffman_decode(a, &z_codelength);
      assert(c >= 0 && c < 19);
      if (c < 16)
         lencodes[n++] = cast(ubyte) c;
      else if (c == 16) {
         c = zreceive(a,2)+3;
         memset(lencodes.ptr+n, lencodes[n-1], c);
         n += c;
      } else if (c == 17) {
         c = zreceive(a,3)+3;
         memset(lencodes.ptr+n, 0, c);
         n += c;
      } else {
         assert(c == 18);
         c = zreceive(a,7)+11;
         memset(lencodes.ptr+n, 0, c);
         n += c;
      }
   }
   if (n != hlit+hdist) throw new STBImageException("Bad codelengths, corrupt PNG");
   if (!zbuild_huffman(&a.z_length, lencodes.ptr, hlit)) return 0;
   if (!zbuild_huffman(&a.z_distance, lencodes.ptr+hlit, hdist)) return 0;
   return 1;
}

int parse_uncompressed_block(zbuf *a)
{
   ubyte[4] header;
   int len,nlen,k;
   if (a.num_bits & 7)
      zreceive(a, a.num_bits & 7); // discard
   // drain the bit-packed data into header
   k = 0;
   while (a.num_bits > 0) {
      header[k++] = cast(ubyte) (a.code_buffer & 255); // wtf this warns?
      a.code_buffer >>= 8;
      a.num_bits -= 8;
   }
   assert(a.num_bits == 0);
   // now fill header the normal way
   while (k < 4)
      header[k++] = cast(ubyte) zget8(a);
   len  = header[1] * 256 + header[0];
   nlen = header[3] * 256 + header[2];
   if (nlen != (len ^ 0xffff)) throw new STBImageException("Zlib corrupt, corrupt PNG");
   if (a.zbuffer + len > a.zbuffer_end) throw new STBImageException("Read past buffer, corrupt PNG");
   if (a.zout + len > a.zout_end)
      if (!expand(a, len)) return 0;
   memcpy(a.zout, a.zbuffer, len);
   a.zbuffer += len;
   a.zout += len;
   return 1;
}

int parse_zlib_header(zbuf *a)
{
   int cmf   = zget8(a);
   int cm    = cmf & 15;
   /* int cinfo = cmf >> 4; */
   int flg   = zget8(a);
   if ((cmf*256+flg) % 31 != 0) throw new STBImageException("Bad zlib header, corrupt PNG"); // zlib spec
   if (flg & 32) throw new STBImageException("No preset dict, corrupt PNG"); // preset dictionary not allowed in png
   if (cm != 8) throw new STBImageException("Bad compression, corrupt PNG");  // DEFLATE required for png
   // window = 1 << (8 + cinfo)... but who cares, we fully buffer output
   return 1;
}

// @TODO: should statically initialize these for optimal thread safety
__gshared ubyte[288] default_length;
__gshared ubyte[32] default_distance;

void init_defaults()
{
   int i;   // use <= to match clearly with spec
   for (i=0; i <= 143; ++i)     default_length[i]   = 8;
   for (   ; i <= 255; ++i)     default_length[i]   = 9;
   for (   ; i <= 279; ++i)     default_length[i]   = 7;
   for (   ; i <= 287; ++i)     default_length[i]   = 8;

   for (i=0; i <=  31; ++i)     default_distance[i] = 5;
}

__gshared int stbi_png_partial; // a quick hack to only allow decoding some of a PNG... I should implement real streaming support instead
int parse_zlib(zbuf *a, int parse_header)
{
   int final_, type;
   if (parse_header)
      if (!parse_zlib_header(a)) return 0;
   a.num_bits = 0;
   a.code_buffer = 0;
   do {
      final_ = zreceive(a,1);
      type = zreceive(a,2);
      if (type == 0) {
         if (!parse_uncompressed_block(a)) return 0;
      } else if (type == 3) {
         return 0;
      } else {
         if (type == 1) {
            // use fixed code lengths
            if (!default_distance[31]) init_defaults();
            if (!zbuild_huffman(&a.z_length  , default_length.ptr  , 288)) return 0;
            if (!zbuild_huffman(&a.z_distance, default_distance.ptr,  32)) return 0;
         } else {
            if (!compute_huffman_codes(a)) return 0;
         }
         if (!parse_huffman_block(a)) return 0;
      }
      if (stbi_png_partial && a.zout - a.zout_start > 65536)
         break;
   } while (!final_);
   return 1;
}

int do_zlib(zbuf *a, ubyte *obuf, int olen, int exp, int parse_header)
{
   a.zout_start = obuf;
   a.zout       = obuf;
   a.zout_end   = obuf + olen;
   a.z_expandable = exp;

   return parse_zlib(a, parse_header);
}

ubyte *stbi_zlib_decode_malloc_guesssize(const(ubyte) *buffer, int len, int initial_size, int *outlen)
{
   zbuf a;
   ubyte *p = cast(ubyte*) malloc(initial_size);
   if (p == null) return null;
   a.zbuffer = buffer;
   a.zbuffer_end = buffer + len;
   if (do_zlib(&a, p, initial_size, 1, 1)) {
      if (outlen) *outlen = cast(int) (a.zout - a.zout_start);
      return a.zout_start;
   } else {
      free(a.zout_start);
      return null;
   }
}

ubyte *stbi_zlib_decode_malloc(const(ubyte) *buffer, int len, int *outlen)
{
   return stbi_zlib_decode_malloc_guesssize(buffer, len, 16384, outlen);
}

ubyte *stbi_zlib_decode_malloc_guesssize_headerflag(const(ubyte) *buffer, int len, int initial_size, int *outlen, int parse_header)
{
   zbuf a;
   ubyte *p = cast(ubyte*) malloc(initial_size);
   if (p == null) return null;
   a.zbuffer = buffer;
   a.zbuffer_end = buffer + len;
   if (do_zlib(&a, p, initial_size, 1, parse_header)) {
      if (outlen) *outlen = cast(int) (a.zout - a.zout_start);
      return a.zout_start;
   } else {
      free(a.zout_start);
      return null;
   }
}

int stbi_zlib_decode_buffer(ubyte* obuffer, int olen, const(ubyte)* ibuffer, int ilen)
{
   zbuf a;
   a.zbuffer = ibuffer;
   a.zbuffer_end = ibuffer + ilen;
   if (do_zlib(&a, obuffer, olen, 0, 1))
      return cast(int) (a.zout - a.zout_start);
   else
      return -1;
}

ubyte *stbi_zlib_decode_noheader_malloc(const(ubyte) *buffer, int len, int *outlen)
{
   zbuf a;
   ubyte *p = cast(ubyte*) malloc(16384);
   if (p == null) return null;
   a.zbuffer = buffer;
   a.zbuffer_end = buffer+len;
   if (do_zlib(&a, p, 16384, 1, 0)) {
      if (outlen) *outlen = cast(int) (a.zout - a.zout_start);
      return a.zout_start;
   } else {
      free(a.zout_start);
      return null;
   }
}

int stbi_zlib_decode_noheader_buffer(ubyte *obuffer, int olen, const(ubyte) *ibuffer, int ilen)
{
   zbuf a;
   a.zbuffer = ibuffer;
   a.zbuffer_end = ibuffer + ilen;
   if (do_zlib(&a, obuffer, olen, 0, 0))
      return cast(int) (a.zout - a.zout_start);
   else
      return -1;
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


struct chunk
{
   uint length;
   uint type;
}

uint PNG_TYPE(ubyte a, ubyte b, ubyte c, ubyte d)
{
   return (a << 24) + (b << 16) + (c << 8) + d;
}

chunk get_chunk_header(stbi *s)
{
   chunk c;
   c.length = get32(s);
   c.type   = get32(s);
   return c;
}

static int check_png_header(stbi *s)
{
   static immutable ubyte[8] png_sig = [ 137, 80, 78, 71, 13, 10, 26, 10 ];
   for (int i = 0; i < 8; ++i)
   {
       ubyte headerByte = get8u(s);
       ubyte expected = png_sig[i];
       if (headerByte != expected)
           throw new STBImageException("Bad PNG sig, not a PNG");
   }
   return 1;
}

struct png
{
   stbi *s;
   ubyte *idata;
   ubyte *expanded;
   ubyte *out_;
}


enum : int
{
   F_none=0, F_sub=1, F_up=2, F_avg=3, F_paeth=4,
   F_avg_first, F_paeth_first
}

static immutable ubyte[5] first_row_filter =
[
   F_none, F_sub, F_none, F_avg_first, F_paeth_first
];

static int paeth(int a, int b, int c)
{
   int p = a + b - c;
   int pa = abs(p-a);
   int pb = abs(p-b);
   int pc = abs(p-c);
   if (pa <= pb && pa <= pc) return a;
   if (pb <= pc) return b;
   return c;
}

// create the png data from post-deflated data
static int create_png_image_raw(png *a, ubyte *raw, uint raw_len, int out_n, uint x, uint y)
{
   stbi *s = a.s;
   uint i,j,stride = x*out_n;
   int k;
   int img_n = s.img_n; // copy it into a local for later
   assert(out_n == s.img_n || out_n == s.img_n+1);
   if (stbi_png_partial) y = 1;
   a.out_ = cast(ubyte*) malloc(x * y * out_n);
   if (!a.out_) throw new STBImageException("Out of memory");
   if (!stbi_png_partial) {
      if (s.img_x == x && s.img_y == y) {
         if (raw_len != (img_n * x + 1) * y) throw new STBImageException("Not enough pixels, corrupt PNG");
      } else { // interlaced:
         if (raw_len < (img_n * x + 1) * y) throw new STBImageException("Not enough pixels, corrupt PNG");
      }
   }
   for (j=0; j < y; ++j) {
      ubyte *cur = a.out_ + stride*j;
      ubyte *prior = cur - stride;
      int filter = *raw++;
      if (filter > 4) throw new STBImageException("Invalid filter, corrupt PNG");
      // if first row, use special filter that doesn't sample previous row
      if (j == 0) filter = first_row_filter[filter];
      // handle first pixel explicitly
      for (k=0; k < img_n; ++k) {
         switch (filter) {
            case F_none       : cur[k] = raw[k]; break;
            case F_sub        : cur[k] = raw[k]; break;
            case F_up         : cur[k] = cast(ubyte)(raw[k] + prior[k]); break;
            case F_avg        : cur[k] = cast(ubyte)(raw[k] + (prior[k]>>1)); break;
            case F_paeth      : cur[k] = cast(ubyte) (raw[k] + paeth(0,prior[k],0)); break;
            case F_avg_first  : cur[k] = raw[k]; break;
            case F_paeth_first: cur[k] = raw[k]; break;
            default: break;
         }
      }
      if (img_n != out_n) cur[img_n] = 255;
      raw += img_n;
      cur += out_n;
      prior += out_n;
      // this is a little gross, so that we don't switch per-pixel or per-component
      if (img_n == out_n) {

         for (i=x-1; i >= 1; --i, raw+=img_n,cur+=img_n,prior+=img_n)
            for (k=0; k < img_n; ++k)
            {
               switch (filter) {
                  case F_none:  cur[k] = raw[k]; break;
                  case F_sub:   cur[k] = cast(ubyte)(raw[k] + cur[k-img_n]); break;
                  case F_up:    cur[k] = cast(ubyte)(raw[k] + prior[k]); break;
                  case F_avg:   cur[k] = cast(ubyte)(raw[k] + ((prior[k] + cur[k-img_n])>>1)); break;
                  case F_paeth:  cur[k] = cast(ubyte) (raw[k] + paeth(cur[k-img_n],prior[k],prior[k-img_n])); break;
                  case F_avg_first:    cur[k] = cast(ubyte)(raw[k] + (cur[k-img_n] >> 1)); break;
                  case F_paeth_first:  cur[k] = cast(ubyte) (raw[k] + paeth(cur[k-img_n],0,0)); break;
                  default: break;
               }
            }
      } else {
         assert(img_n+1 == out_n);

         for (i=x-1; i >= 1; --i, cur[img_n]=255,raw+=img_n,cur+=out_n,prior+=out_n)
            for (k=0; k < img_n; ++k)
            {
               switch (filter) {
                  case F_none:  cur[k] = raw[k]; break;
                  case F_sub:   cur[k] = cast(ubyte)(raw[k] + cur[k-out_n]); break;
                  case F_up:    cur[k] = cast(ubyte)(raw[k] + prior[k]); break;
                  case F_avg:   cur[k] = cast(ubyte)(raw[k] + ((prior[k] + cur[k-out_n])>>1)); break;
                  case F_paeth:  cur[k] = cast(ubyte) (raw[k] + paeth(cur[k-out_n],prior[k],prior[k-out_n])); break;
                  case F_avg_first:    cur[k] = cast(ubyte)(raw[k] + (cur[k-out_n] >> 1)); break;
                  case F_paeth_first:  cur[k] = cast(ubyte) (raw[k] + paeth(cur[k-out_n],0,0)); break;
                  default: break;
               }
            }
      }
   }
   return 1;
}

int create_png_image(png *a, ubyte *raw, uint raw_len, int out_n, int interlaced)
{
   ubyte *final_;
   int p;
   int save;
   if (!interlaced)
      return create_png_image_raw(a, raw, raw_len, out_n, a.s.img_x, a.s.img_y);
   save = stbi_png_partial;
   stbi_png_partial = 0;

   // de-interlacing
   final_ = cast(ubyte*) malloc(a.s.img_x * a.s.img_y * out_n);
   for (p=0; p < 7; ++p) {
      static immutable int[7] xorig = [ 0,4,0,2,0,1,0 ];
      static immutable int[7] yorig = [ 0,0,4,0,2,0,1 ];
      static immutable int[7] xspc = [ 8,8,4,4,2,2,1 ];
      static immutable int[7] yspc = [ 8,8,8,4,4,2,2 ];
      int i,j,x,y;
      // pass1_x[4] = 0, pass1_x[5] = 1, pass1_x[12] = 1
      x = (a.s.img_x - xorig[p] + xspc[p]-1) / xspc[p];
      y = (a.s.img_y - yorig[p] + yspc[p]-1) / yspc[p];
      if (x && y) {
         if (!create_png_image_raw(a, raw, raw_len, out_n, x, y)) {
            free(final_);
            return 0;
         }
         for (j=0; j < y; ++j)
            for (i=0; i < x; ++i)
               memcpy(final_ + (j*yspc[p]+yorig[p])*a.s.img_x*out_n + (i*xspc[p]+xorig[p])*out_n,
                      a.out_ + (j*x+i)*out_n, out_n);
         free(a.out_);
         raw += (x*out_n+1)*y;
         raw_len -= (x*out_n+1)*y;
      }
   }
   a.out_ = final_;

   stbi_png_partial = save;
   return 1;
}

static int compute_transparency(png *z, ubyte[3] tc, int out_n)
{
   stbi *s = z.s;
   uint i, pixel_count = s.img_x * s.img_y;
   ubyte *p = z.out_;

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

int expand_palette(png *a, ubyte *palette, int len, int pal_img_n)
{
   uint i, pixel_count = a.s.img_x * a.s.img_y;
   ubyte *p;
   ubyte *temp_out;
   ubyte *orig = a.out_;

   p = cast(ubyte*) malloc(pixel_count * pal_img_n);
   if (p == null)
      throw new STBImageException("Out of memory");

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
   free(a.out_);
   a.out_ = temp_out;

   return 1;
}

int parse_png_file(png *z, int scan, int req_comp)
{
   ubyte[1024] palette;
   ubyte pal_img_n=0;
   ubyte has_trans=0;
   ubyte[3] tc;
   uint ioff=0, idata_limit=0, i, pal_len=0;
   int first=1,k,interlace=0;
   stbi *s = z.s;

   z.expanded = null;
   z.idata = null;
   z.out_ = null;

   if (!check_png_header(s)) return 0;

   if (scan == SCAN_type) return 1;

   for (;;) {
      chunk c = get_chunk_header(s);
      switch (c.type) {
         case PNG_TYPE('I','H','D','R'): {
            int depth,color,comp,filter;
            if (!first) throw new STBImageException("Multiple IHDR, corrupt PNG");
            first = 0;
            if (c.length != 13) throw new STBImageException("Bad IHDR len, corrupt PNG");
            s.img_x = get32(s); if (s.img_x > (1 << 24)) throw new STBImageException("Very large image (corrupt?)");
            s.img_y = get32(s); if (s.img_y > (1 << 24)) throw new STBImageException("Very large image (corrupt?)");
            depth = get8(s);  if (depth != 8)        throw new STBImageException("8bit only, PNG not supported: 8-bit only");
            color = get8(s);  if (color > 6)         throw new STBImageException("Bad ctype, corrupt PNG");
            if (color == 3) pal_img_n = 3; else if (color & 1) throw new STBImageException("Bad ctype, corrupt PNG");
            comp  = get8(s);  if (comp) throw new STBImageException("Bad comp method, corrupt PNG");
            filter= get8(s);  if (filter) throw new STBImageException("Bad filter method, corrupt PNG");
            interlace = get8(s); if (interlace>1) throw new STBImageException("Bad interlace method, corrupt PNG");
            if (!s.img_x || !s.img_y) throw new STBImageException("0-pixel image, corrupt PNG");
            if (!pal_img_n) {
               s.img_n = (color & 2 ? 3 : 1) + (color & 4 ? 1 : 0);
               if ((1 << 30) / s.img_x / s.img_n < s.img_y) throw new STBImageException("Image too large to decode");
               if (scan == SCAN_header) return 1;
            } else {
               // if paletted, then pal_n is our final components, and
               // img_n is # components to decompress/filter.
               s.img_n = 1;
               if ((1 << 30) / s.img_x / 4 < s.img_y) throw new STBImageException("Too large, corrupt PNG");
               // if SCAN_header, have to scan to see if we have a tRNS
            }
            break;
         }

         case PNG_TYPE('P','L','T','E'):  {
            if (first) throw new STBImageException("first not IHDR, corrupt PNG");
            if (c.length > 256*3) throw new STBImageException("invalid PLTE, corrupt PNG");
            pal_len = c.length / 3;
            if (pal_len * 3 != c.length) throw new STBImageException("invalid PLTE, corrupt PNG");
            for (i=0; i < pal_len; ++i) {
               palette[i*4+0] = get8u(s);
               palette[i*4+1] = get8u(s);
               palette[i*4+2] = get8u(s);
               palette[i*4+3] = 255;
            }
            break;
         }

         case PNG_TYPE('t','R','N','S'): {
            if (first) throw new STBImageException("first not IHDR, cCorrupt PNG");
            if (z.idata) throw new STBImageException("tRNS after IDAT, corrupt PNG");
            if (pal_img_n) {
               if (scan == SCAN_header) { s.img_n = 4; return 1; }
               if (pal_len == 0) throw new STBImageException("tRNS before PLTE, corrupt PNG");
               if (c.length > pal_len) throw new STBImageException("bad tRNS len, corrupt PNG");
               pal_img_n = 4;
               for (i=0; i < c.length; ++i)
                  palette[i*4+3] = get8u(s);
            } else {
               if (!(s.img_n & 1)) throw new STBImageException("tRNS with alpha, corrupt PNG");
               if (c.length != cast(uint) s.img_n*2) throw new STBImageException("bad tRNS len, corrupt PNG");
               has_trans = 1;
               for (k=0; k < s.img_n; ++k)
                  tc[k] = cast(ubyte) get16(s); // non 8-bit images will be larger
            }
            break;
         }

         case PNG_TYPE('I','D','A','T'): {
            if (first) throw new STBImageException("first not IHDR, corrupt PNG");
            if (pal_img_n && !pal_len) throw new STBImageException("no PLTE, corrupt PNG");
            if (scan == SCAN_header) { s.img_n = pal_img_n; return 1; }
            if (ioff + c.length > idata_limit) {
               ubyte *p;
               if (idata_limit == 0) idata_limit = c.length > 4096 ? c.length : 4096;
               while (ioff + c.length > idata_limit)
                  idata_limit *= 2;
               p = cast(ubyte*) realloc(z.idata, idata_limit); if (p == null) throw new STBImageException("outofmem, cOut of memory");
               z.idata = p;
            }
            if (!getn(s, z.idata+ioff,c.length)) throw new STBImageException("outofdata, corrupt PNG");
            ioff += c.length;
            break;
         }

         case PNG_TYPE('I','E','N','D'): {
            uint raw_len;
            if (first) throw new STBImageException("first not IHDR, corrupt PNG");
            if (scan != SCAN_load) return 1;
            if (z.idata == null) throw new STBImageException("no IDAT, corrupt PNG");
            z.expanded = stbi_zlib_decode_malloc_guesssize_headerflag(z.idata, ioff, 16384, cast(int *) &raw_len, 1);
            if (z.expanded == null) return 0; // zlib should set error
            free(z.idata); z.idata = null;
            if ((req_comp == s.img_n+1 && req_comp != 3 && !pal_img_n) || has_trans)
               s.img_out_n = s.img_n+1;
            else
               s.img_out_n = s.img_n;
            if (!create_png_image(z, z.expanded, raw_len, s.img_out_n, interlace)) return 0;
            if (has_trans)
               if (!compute_transparency(z, tc, s.img_out_n)) return 0;
            if (pal_img_n) {
               // pal_img_n == 3 or 4
               s.img_n = pal_img_n; // record the actual colors we had
               s.img_out_n = pal_img_n;
               if (req_comp >= 3) s.img_out_n = req_comp;
               if (!expand_palette(z, palette.ptr, pal_len, s.img_out_n))
                  return 0;
            }
            free(z.expanded); z.expanded = null;
            return 1;
         }

         default:
            // if critical, fail
            if (first) throw new STBImageException("first not IHDR, corrupt PNG");
            if ((c.type & (1 << 29)) == 0) {

               throw new STBImageException("PNG not supported: unknown chunk type");
            }
            skip(s, c.length);
            break;
      }
      // end of chunk, read and skip CRC
      get32(s);
   }
}

ubyte *do_png(png *p, int *x, int *y, int *n, int req_comp)
{
   ubyte *result=null;
   if (req_comp < 0 || req_comp > 4)
      throw new STBImageException("Internal error: bad req_comp");
   if (parse_png_file(p, SCAN_load, req_comp)) {
      result = p.out_;
      p.out_ = null;
      if (req_comp && req_comp != p.s.img_out_n) {
         result = convert_format(result, p.s.img_out_n, req_comp, p.s.img_x, p.s.img_y);
         p.s.img_out_n = req_comp;
         if (result == null) return result;
      }
      *x = p.s.img_x;
      *y = p.s.img_y;
      if (n) *n = p.s.img_n;
   }
   free(p.out_);      p.out_    = null;
   free(p.expanded); p.expanded = null;
   free(p.idata);    p.idata    = null;

   return result;
}

ubyte *stbi_png_load(stbi *s, int *x, int *y, int *comp, int req_comp)
{
   png p;
   p.s = s;
   return do_png(&p, x,y,comp,req_comp);
}
