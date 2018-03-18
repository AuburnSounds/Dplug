/// D translation of stb_truetype v0.7 by Sean Barrett
/// More information on http://nothings.org/stb/stb_truetype.h
/// Removed:
/// - texture baking API
/// - font finding in the TTF itself. Make sure there is only one font in the TTF.
module dplug.graphics.stb_truetype;

import core.stdc.stdlib : malloc, free, qsort;
import core.stdc.string : memcpy, memset;

import std.math : ceil, floor, sqrt;

import dplug.core.nogc;

int ifloor(float x) nothrow @nogc
{
   return cast(int)(floor(x));
}

int iceil(float x) nothrow @nogc
{
   return cast(int)(ceil(x));
}

/// The following structure is defined publically so you can declare one on
/// the stack or as a global or etc, but you should treat it as opaque.
struct stbtt_fontinfo
{
   const(ubyte)   * data;             // pointer to .ttf file
   int              fontstart;        // offset of start of font
   int numGlyphs;                     // number of glyphs, needed for range checking
   int loca,head,glyf,hhea,hmtx,kern; // table locations as offset from start of .ttf
   int index_map;                     // a cmap mapping for our chosen character encoding
   int indexToLocFormat;              // format needed to map from glyph index to glyph
}


enum STBTT_vmove = 1,
     STBTT_vline = 2,
     STBTT_vcurve = 3;

alias stbtt_vertex_type = short;
struct stbtt_vertex
{
   stbtt_vertex_type x,y,cx,cy;
   ubyte type, padding;
}

struct stbtt__bitmap
{
   int w,h,stride;
   ubyte *pixels;
}
enum   // platformID
   STBTT_PLATFORM_ID_UNICODE   =0,
   STBTT_PLATFORM_ID_MAC       =1,
   STBTT_PLATFORM_ID_ISO       =2,
   STBTT_PLATFORM_ID_MICROSOFT =3;

enum   // encodingID for STBTT_PLATFORM_ID_MICROSOFT
   STBTT_MS_EID_SYMBOL        =0,
   STBTT_MS_EID_UNICODE_BMP   =1,
   STBTT_MS_EID_SHIFTJIS      =2,
   STBTT_MS_EID_UNICODE_FULL  =10;

// Accessors to parse data from file

ubyte ttBYTE(const(ubyte)* p) nothrow @nogc
{
   return *p;
}

byte ttCHAR(const(ubyte)* p) nothrow @nogc
{
   return *p;
}

int ttFixed(const(ubyte)* p) nothrow @nogc
{
   return ttLONG(p);
}

ushort ttUSHORT(const(ubyte) *p) nothrow @nogc
{
    return p[0]*256 + p[1];
}

short ttSHORT(const(ubyte) *p) nothrow @nogc
{
    return cast(short)(p[0]*256 + p[1]);
}

uint ttULONG(const(ubyte) *p) nothrow @nogc
{
    return (p[0]<<24) + (p[1]<<16) + (p[2]<<8) + p[3];
}

int ttLONG(const(ubyte) *p) nothrow @nogc
{
    return (p[0]<<24) + (p[1]<<16) + (p[2]<<8) + p[3];
}

bool stbtt_tag4(const(ubyte) *p, ubyte c0, ubyte c1, ubyte c2, ubyte c3) nothrow @nogc
{
    return (p[0] == c0 && p[1] == c1 && p[2] == c2 && p[3] == c3);
}

bool stbtt_tag(const(ubyte) *p, string s) nothrow @nogc
{
    return stbtt_tag4(p, s[0], s[1], s[2], s[3]);
}

bool stbtt__isfont(const(ubyte) *font) nothrow @nogc
{
   // check the version number
   if (stbtt_tag4(font, '1',0,0,0))
       return true; // TrueType 1
   if (stbtt_tag(font, "typ1"))
       return true; // TrueType with type 1 font -- we don't support this!
   if (stbtt_tag(font, "OTTO"))
       return true; // OpenType with CFF
   if (stbtt_tag4(font, 0,1,0,0))
       return true; // OpenType 1.0
   return false;
}

// @OPTIMIZE: binary search
uint stbtt__find_table(const(ubyte)* data, uint fontstart, string tag) nothrow @nogc
{
   int num_tables = ttUSHORT(data+fontstart+4);
   uint tabledir = fontstart + 12;
   for (int i=0; i < num_tables; ++i) {
      uint loc = tabledir + 16*i;
      if (stbtt_tag(data+loc+0, tag))
         return ttULONG(data+loc+8);
   }
   return 0;
}

/// Each .ttf/.ttc file may have more than one font. Each font has a sequential
/// index number starting from 0. Call this function to get the font offset for
/// a given index; it returns -1 if the index is out of range. A regular .ttf
/// file will only define one font and it always be at offset 0, so it will
/// return '0' for index 0, and -1 for all other indices. You can just skip
/// this step if you know it's that kind of font.
int stbtt_GetFontOffsetForIndex(const(ubyte)* font_collection, int index) nothrow @nogc
{
   // if it's just a font, there's only one valid index
   if (stbtt__isfont(font_collection))
      return index == 0 ? 0 : -1;

   // check if it's a TTC
   if (stbtt_tag(font_collection, "ttcf")) {
      // version 1?
      if (ttULONG(font_collection+4) == 0x00010000 || ttULONG(font_collection+4) == 0x00020000) {
         int n = ttLONG(font_collection+8);
         if (index >= n)
            return -1;
         return ttULONG(font_collection+12+index*14);
      }
   }
   return -1;
}

/// Given an offset into the file that defines a font, this function builds
/// the necessary cached info for the rest of the system. You must allocate
/// the stbtt_fontinfo yourself, and stbtt_InitFont will fill it out. You don't
/// need to do anything special to free it, because the contents are pure
/// value data with no additional data structures. Returns 0 on failure.
int stbtt_InitFont(stbtt_fontinfo* info, const(ubyte)* data2, int fontstart) nothrow @nogc
{
   const(ubyte) *data = data2;
   uint cmap, t;
   int i,numTables;

   info.data = data;
   info.fontstart = fontstart;

   cmap = stbtt__find_table(data, fontstart, "cmap");       // required
   info.loca = stbtt__find_table(data, fontstart, "loca"); // required
   info.head = stbtt__find_table(data, fontstart, "head"); // required
   info.glyf = stbtt__find_table(data, fontstart, "glyf"); // required
   info.hhea = stbtt__find_table(data, fontstart, "hhea"); // required
   info.hmtx = stbtt__find_table(data, fontstart, "hmtx"); // required
   info.kern = stbtt__find_table(data, fontstart, "kern"); // not required
   if (!cmap || !info.loca || !info.head || !info.glyf || !info.hhea || !info.hmtx)
      return 0;

   t = stbtt__find_table(data, fontstart, "maxp");
   if (t)
      info.numGlyphs = ttUSHORT(data+t+4);
   else
      info.numGlyphs = 0xffff;

   // find a cmap encoding table we understand *now* to avoid searching
   // later. (todo: could make this installable)
   // the same regardless of glyph.
   numTables = ttUSHORT(data + cmap + 2);
   info.index_map = 0;
   for (i=0; i < numTables; ++i) {
      uint encoding_record = cmap + 4 + 8 * i;
      // find an encoding we understand:
      switch(ttUSHORT(data+encoding_record))
      {
         case STBTT_PLATFORM_ID_MICROSOFT:
            switch (ttUSHORT(data+encoding_record+2))
            {
               case STBTT_MS_EID_UNICODE_BMP:
               case STBTT_MS_EID_UNICODE_FULL:
                  // MS/Unicode
                  info.index_map = cmap + ttULONG(data+encoding_record+4);
                  break;
               default:
                  assert(0);
            }
            break;
            default:
               break;
      }
   }
   if (info.index_map == 0)
      return 0;

   info.indexToLocFormat = ttUSHORT(data+info.head + 50);
   return 1;
}

/// If you're going to perform multiple operations on the same character
/// and you want a speed-up, call this function with the character you're
/// going to process, then use glyph-based functions instead of the
/// codepoint-based functions.
int stbtt_FindGlyphIndex(const(stbtt_fontinfo) *info, int unicode_codepoint) nothrow @nogc
{
   const(ubyte)* data = info.data;
   uint index_map = info.index_map;

   ushort format = ttUSHORT(data + index_map + 0);
   if (format == 0) { // apple byte encoding
      int bytes = ttUSHORT(data + index_map + 2);
      if (unicode_codepoint < bytes-6)
         return ttBYTE(data + index_map + 6 + unicode_codepoint);
      return 0;
   } else if (format == 6) {
      uint first = ttUSHORT(data + index_map + 6);
      uint count = ttUSHORT(data + index_map + 8);
      if (cast(uint) unicode_codepoint >= first && cast(uint)unicode_codepoint < first+count)
         return ttUSHORT(data + index_map + 10 + (unicode_codepoint - first)*2);
      return 0;
   } else if (format == 2) {
      assert(0); // @TODO: high-byte mapping for japanese/chinese/korean
   } else if (format == 4) { // standard mapping for windows fonts: binary search collection of ranges
      ushort segcount = ttUSHORT(data+index_map+6) >> 1;
      ushort searchRange = ttUSHORT(data+index_map+8) >> 1;
      ushort entrySelector = ttUSHORT(data+index_map+10);
      ushort rangeShift = ttUSHORT(data+index_map+12) >> 1;
      ushort item, offset, start, end;

      // do a binary search of the segments
      uint endCount = index_map + 14;
      uint search = endCount;

      if (unicode_codepoint > 0xffff)
         return 0;

      // they lie from endCount .. endCount + segCount
      // but searchRange is the nearest power of two, so...
      if (unicode_codepoint >= ttUSHORT(data + search + rangeShift*2))
         search += rangeShift*2;

      // now decrement to bias correctly to find smallest
      search -= 2;
      while (entrySelector) {
         ushort start2, end2;
         searchRange >>= 1;
         start2 = ttUSHORT(data + search + 2 + segcount*2 + 2);
         end2 = ttUSHORT(data + search + 2);
         start2 = ttUSHORT(data + search + searchRange*2 + segcount*2 + 2);
         end2 = ttUSHORT(data + search + searchRange*2);
         if (unicode_codepoint > end2)
            search += searchRange*2;
         --entrySelector;
      }
      search += 2;

      item = cast(ushort) ((search - endCount) >> 1);

      assert(unicode_codepoint <= ttUSHORT(data + endCount + 2*item));
      start = ttUSHORT(data + index_map + 14 + segcount*2 + 2 + 2*item);
      end = ttUSHORT(data + index_map + 14 + 2 + 2*item);
      if (unicode_codepoint < start)
         return 0;

      offset = ttUSHORT(data + index_map + 14 + segcount*6 + 2 + 2*item);
      if (offset == 0)
         return cast(ushort) (unicode_codepoint + ttSHORT(data + index_map + 14 + segcount*4 + 2 + 2*item));

      return ttUSHORT(data + offset + (unicode_codepoint-start)*2 + index_map + 14 + segcount*6 + 2 + 2*item);
   } else if (format == 12 || format == 13) {
      uint ngroups = ttULONG(data+index_map+12);
      int low,high;
      low = 0;
      high = ngroups;
      // Binary search the right group.
      while (low < high) {
         int mid = low + ((high-low) >> 1); // rounds down, so low <= mid < high
         uint start_char = ttULONG(data+index_map+16+mid*12);
         uint end_char = ttULONG(data+index_map+16+mid*12+4);
         if (unicode_codepoint < start_char)
            high = mid;
         else if (unicode_codepoint > end_char)
            low = mid+1;
         else {
            uint start_glyph = ttULONG(data+index_map+16+mid*12+8);
            if (format == 12)
               return start_glyph + unicode_codepoint-start_char;
            else // format == 13
               return start_glyph;
         }
      }
      return 0; // not found
   }
   // @TODO
   assert(0);
}

/// Returns: Number of vertices and fills *vertices with the pointer to them.
///          These are expressed in "unscaled" coordinates.
int stbtt_GetCodepointShape(const stbtt_fontinfo *info, int unicode_codepoint, stbtt_vertex **vertices) nothrow @nogc
{
   return stbtt_GetGlyphShape(info, stbtt_FindGlyphIndex(info, unicode_codepoint), vertices);
}

void stbtt_setvertex(stbtt_vertex *v, ubyte type, int x, int y, int cx, int cy) nothrow @nogc
{
   v.type = type;
   v.x = cast(short) x;
   v.y = cast(short) y;
   v.cx = cast(short) cx;
   v.cy = cast(short) cy;
}

int stbtt__GetGlyfOffset(const stbtt_fontinfo *info, int glyph_index) nothrow @nogc
{
   int g1,g2;

   if (glyph_index >= info.numGlyphs) return -1; // glyph index out of range
   if (info.indexToLocFormat >= 2)    return -1; // unknown index.glyph map format

   if (info.indexToLocFormat == 0) {
      g1 = info.glyf + ttUSHORT(info.data + info.loca + glyph_index * 2) * 2;
      g2 = info.glyf + ttUSHORT(info.data + info.loca + glyph_index * 2 + 2) * 2;
   } else {
      g1 = info.glyf + ttULONG (info.data + info.loca + glyph_index * 4);
      g2 = info.glyf + ttULONG (info.data + info.loca + glyph_index * 4 + 4);
   }

   return g1==g2 ? -1 : g1; // if length is 0, return -1
}

/// As above, but takes one or more glyph indices for greater efficiency
int stbtt_GetGlyphBox(const stbtt_fontinfo *info, int glyph_index, int *x0, int *y0, int *x1, int *y1) nothrow @nogc
{
   int g = stbtt__GetGlyfOffset(info, glyph_index);
   if (g < 0) return 0;

   if (x0) *x0 = ttSHORT(info.data + g + 2);
   if (y0) *y0 = ttSHORT(info.data + g + 4);
   if (x1) *x1 = ttSHORT(info.data + g + 6);
   if (y1) *y1 = ttSHORT(info.data + g + 8);
   return 1;
}

/// Gets the bounding box of the visible part of the glyph, in unscaled coordinates
int stbtt_GetCodepointBox(const stbtt_fontinfo *info, int codepoint, int *x0, int *y0, int *x1, int *y1) nothrow @nogc
{
   return stbtt_GetGlyphBox(info, stbtt_FindGlyphIndex(info,codepoint), x0,y0,x1,y1);
}

/// Returns: non-zero if nothing is drawn for this glyph
int stbtt_IsGlyphEmpty(const stbtt_fontinfo *info, int glyph_index) nothrow @nogc
{
   short numberOfContours;
   int g = stbtt__GetGlyfOffset(info, glyph_index);
   if (g < 0) return 1;
   numberOfContours = ttSHORT(info.data + g);
   return numberOfContours == 0;
}

int stbtt__close_shape(stbtt_vertex *vertices, int num_vertices, int was_off, int start_off,
    int sx, int sy, int scx, int scy, int cx, int cy) nothrow @nogc
{
   if (start_off) {
      if (was_off)
         stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve, (cx+scx)>>1, (cy+scy)>>1, cx,cy);
      stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve, sx,sy,scx,scy);
   } else {
      if (was_off)
         stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve,sx,sy,cx,cy);
      else
         stbtt_setvertex(&vertices[num_vertices++], STBTT_vline,sx,sy,0,0);
   }
   return num_vertices;
}

/// Returns: Number of vertices and fills *vertices with the pointer to them.
///          These are expressed in "unscaled" coordinates.
int stbtt_GetGlyphShape(const stbtt_fontinfo *info, int glyph_index, stbtt_vertex **pvertices) nothrow @nogc
{
   short numberOfContours;
   const(ubyte)* endPtsOfContours;
   const(ubyte)* data = info.data;
   stbtt_vertex* vertices = null;
   int num_vertices=0;
   int g = stbtt__GetGlyfOffset(info, glyph_index);

   *pvertices = null;

   if (g < 0) return 0;

   numberOfContours = ttSHORT(data + g);

   if (numberOfContours > 0) {
      ubyte flags=0,flagcount;
      int ins, i,j=0,m,n, next_move, was_off=0, off, start_off=0;
      int x,y,cx,cy,sx,sy, scx,scy;
      const(ubyte)* points;
      endPtsOfContours = (data + g + 10);
      ins = ttUSHORT(data + g + 10 + numberOfContours * 2);
      points = data + g + 10 + numberOfContours * 2 + 2 + ins;

      n = 1+ttUSHORT(endPtsOfContours + numberOfContours*2-2);

      m = n + 2*numberOfContours;  // a loose bound on how many vertices we might need
      vertices = cast(stbtt_vertex *) malloc(m * stbtt_vertex.sizeof);
      if (vertices == null)
         return 0;

      next_move = 0;
      flagcount=0;

      // in first pass, we load uninterpreted data into the allocated array
      // above, shifted to the end of the array so we won't overwrite it when
      // we create our final data starting from the front

      off = m - n; // starting offset for uninterpreted data, regardless of how m ends up being calculated

      // first load flags

      for (i=0; i < n; ++i) {
         if (flagcount == 0) {
            flags = *points++;
            if (flags & 8)
               flagcount = *points++;
         } else
            --flagcount;
         vertices[off+i].type = flags;
      }

      // now load x coordinates
      x=0;
      for (i=0; i < n; ++i) {
         flags = vertices[off+i].type;
         if (flags & 2) {
            short dx = *points++;
            x += (flags & 16) ? dx : (-cast(int)dx);
         } else {
            if (!(flags & 16)) {
               x = x + cast(short) (points[0]*256 + points[1]);
               points += 2;
            }
         }
         vertices[off+i].x = cast(short) x;
      }

      // now load y coordinates
      y=0;
      for (i=0; i < n; ++i) {
         flags = vertices[off+i].type;
         if (flags & 4) {
            short dy = *points++;
            y += (flags & 32) ? dy : (-cast(int)dy);
         } else {
            if (!(flags & 32)) {
               y = y + cast(short) (points[0]*256 + points[1]);
               points += 2;
            }
         }
         vertices[off+i].y = cast(short) y;
      }

      // now convert them to our format
      num_vertices=0;
      sx = sy = cx = cy = scx = scy = 0;
      for (i=0; i < n; ++i) {
         flags = vertices[off+i].type;
         x     = cast(short) vertices[off+i].x;
         y     = cast(short) vertices[off+i].y;

         if (next_move == i) {
            if (i != 0)
               num_vertices = stbtt__close_shape(vertices, num_vertices, was_off, start_off, sx,sy,scx,scy,cx,cy);

            // now start the new one
            start_off = !(flags & 1);
            if (start_off) {
               // if we start off with an off-curve point, then when we need to find a point on the curve
               // where we can start, and we need to save some state for when we wraparound.
               scx = x;
               scy = y;
               if (!(vertices[off+i+1].type & 1)) {
                  // next point is also a curve point, so interpolate an on-point curve
                  sx = (x + cast(int) vertices[off+i+1].x) >> 1;
                  sy = (y + cast(int) vertices[off+i+1].y) >> 1;
               } else {
                  // otherwise just use the next point as our start point
                  sx = cast(int) vertices[off+i+1].x;
                  sy = cast(int) vertices[off+i+1].y;
                  ++i; // we're using point i+1 as the starting point, so skip it
               }
            } else {
               sx = x;
               sy = y;
            }
            stbtt_setvertex(&vertices[num_vertices++], STBTT_vmove,sx,sy,0,0);
            was_off = 0;
            next_move = 1 + ttUSHORT(endPtsOfContours+j*2);
            ++j;
         } else {
            if (!(flags & 1)) { // if it's a curve
               if (was_off) // two off-curve control points in a row means interpolate an on-curve midpoint
                  stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve, (cx+x)>>1, (cy+y)>>1, cx, cy);
               cx = x;
               cy = y;
               was_off = 1;
            } else {
               if (was_off)
                  stbtt_setvertex(&vertices[num_vertices++], STBTT_vcurve, x,y, cx, cy);
               else
                  stbtt_setvertex(&vertices[num_vertices++], STBTT_vline, x,y,0,0);
               was_off = 0;
            }
         }
      }
      num_vertices = stbtt__close_shape(vertices, num_vertices, was_off, start_off, sx,sy,scx,scy,cx,cy);
   } else if (numberOfContours == -1) {
      // Compound shapes.
      int more = 1;
      const(ubyte)* comp = data + g + 10;
      num_vertices = 0;
      vertices = null;
      while (more) {
         ushort flags, gidx;
         int comp_num_verts = 0, i;
         stbtt_vertex* comp_verts = null,
                       tmp = null;
         float[6] mtx = [1,0,0,1,0,0];
         float m, n;

         flags = ttSHORT(comp); comp+=2;
         gidx = ttSHORT(comp); comp+=2;

         if (flags & 2) { // XY values
            if (flags & 1) { // shorts
               mtx[4] = ttSHORT(comp); comp+=2;
               mtx[5] = ttSHORT(comp); comp+=2;
            } else {
               mtx[4] = ttCHAR(comp); comp+=1;
               mtx[5] = ttCHAR(comp); comp+=1;
            }
         }
         else {
            // @TODO handle matching point
            assert(0);
         }
         if (flags & (1<<3)) { // WE_HAVE_A_SCALE
            mtx[0] = mtx[3] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[1] = mtx[2] = 0;
         } else if (flags & (1<<6)) { // WE_HAVE_AN_X_AND_YSCALE
            mtx[0] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[1] = mtx[2] = 0;
            mtx[3] = ttSHORT(comp)/16384.0f; comp+=2;
         } else if (flags & (1<<7)) { // WE_HAVE_A_TWO_BY_TWO
            mtx[0] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[1] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[2] = ttSHORT(comp)/16384.0f; comp+=2;
            mtx[3] = ttSHORT(comp)/16384.0f; comp+=2;
         }

         // Find transformation scales.
         m = cast(float) sqrt(mtx[0]*mtx[0] + mtx[1]*mtx[1]);
         n = cast(float) sqrt(mtx[2]*mtx[2] + mtx[3]*mtx[3]);

         // Get indexed glyph.
         comp_num_verts = stbtt_GetGlyphShape(info, gidx, &comp_verts);
         if (comp_num_verts > 0) {
            // Transform vertices.
            for (i = 0; i < comp_num_verts; ++i) {
               stbtt_vertex* v = &comp_verts[i];
               stbtt_vertex_type x,y;
               x=v.x; y=v.y;
               v.x = cast(stbtt_vertex_type)(m * (mtx[0]*x + mtx[2]*y + mtx[4]));
               v.y = cast(stbtt_vertex_type)(n * (mtx[1]*x + mtx[3]*y + mtx[5]));
               x=v.cx; y=v.cy;
               v.cx = cast(stbtt_vertex_type)(m * (mtx[0]*x + mtx[2]*y + mtx[4]));
               v.cy = cast(stbtt_vertex_type)(n * (mtx[1]*x + mtx[3]*y + mtx[5]));
            }
            // Append vertices.
            tmp = cast(stbtt_vertex*) malloc((num_vertices+comp_num_verts)*stbtt_vertex.sizeof);
            if (!tmp) {
               if (vertices) free(vertices);
               if (comp_verts) free(comp_verts);
               return 0;
            }
            if (num_vertices > 0) memcpy(tmp, vertices, num_vertices*stbtt_vertex.sizeof);
            memcpy(tmp+num_vertices, comp_verts, comp_num_verts*stbtt_vertex.sizeof);
            if (vertices) free(vertices);
            vertices = tmp;
            free(comp_verts);
            num_vertices += comp_num_verts;
         }
         // More components ?
         more = flags & (1<<5);
      }
   } else if (numberOfContours < 0) {
      // @TODO other compound variations?
      assert(0);
   } else {
      // numberOfCounters == 0, do nothing
   }

   *pvertices = vertices;
   return num_vertices;
}

void stbtt_GetGlyphHMetrics(const stbtt_fontinfo *info, int glyph_index, int *advanceWidth, int *leftSideBearing) nothrow @nogc
{
   ushort numOfLongHorMetrics = ttUSHORT(info.data+info.hhea + 34);
   if (glyph_index < numOfLongHorMetrics) {
      if (advanceWidth)     *advanceWidth    = ttSHORT(info.data + info.hmtx + 4*glyph_index);
      if (leftSideBearing)  *leftSideBearing = ttSHORT(info.data + info.hmtx + 4*glyph_index + 2);
   } else {
      if (advanceWidth)     *advanceWidth    = ttSHORT(info.data + info.hmtx + 4*(numOfLongHorMetrics-1));
      if (leftSideBearing)  *leftSideBearing = ttSHORT(info.data + info.hmtx + 4*numOfLongHorMetrics + 2*(glyph_index - numOfLongHorMetrics));
   }
}

int  stbtt_GetGlyphKernAdvance(const(stbtt_fontinfo)* info, int glyph1, int glyph2) nothrow @nogc
{
   const(ubyte)* data = info.data + info.kern;
   uint needle, straw;
   int l, r, m;

   // we only look at the first table. it must be 'horizontal' and format 0.
   if (!info.kern)
      return 0;
   if (ttUSHORT(data+2) < 1) // number of tables, need at least 1
      return 0;
   if (ttUSHORT(data+8) != 1) // horizontal flag must be set in format
      return 0;

   l = 0;
   r = ttUSHORT(data+10) - 1;
   needle = glyph1 << 16 | glyph2;
   while (l <= r) {
      m = (l + r) >> 1;
      straw = ttULONG(data+18+(m*6)); // note: unaligned read
      if (needle < straw)
         r = m - 1;
      else if (needle > straw)
         l = m + 1;
      else
         return ttSHORT(data+22+(m*6));
   }
   return 0;
}

/// an additional amount to add to the 'advance' value between ch1 and ch2
/// @TODO; for now always returns 0!
int  stbtt_GetCodepointKernAdvance(const stbtt_fontinfo *info, int ch1, int ch2) nothrow @nogc
{
   if (!info.kern) // if no kerning table, don't waste time looking up both codepoint.glyphs
      return 0;
   return stbtt_GetGlyphKernAdvance(info, stbtt_FindGlyphIndex(info,ch1), stbtt_FindGlyphIndex(info,ch2));
}

/// leftSideBearing is the offset from the current horizontal position to the left edge of the character
/// advanceWidth is the offset from the current horizontal position to the next horizontal position
///   these are expressed in unscaled coordinates
void stbtt_GetCodepointHMetrics(const stbtt_fontinfo *info, int codepoint, int *advanceWidth, int *leftSideBearing) nothrow @nogc
{
   stbtt_GetGlyphHMetrics(info, stbtt_FindGlyphIndex(info,codepoint), advanceWidth, leftSideBearing);
}

/// Ascent is the coordinate above the baseline the font extends; descent
/// is the coordinate below the baseline the font extends (i.e. it is typically negative)
/// lineGap is the spacing between one row's descent and the next row's ascent...
/// so you should advance the vertical position by "*ascent - *descent + *lineGap"
///   these are expressed in unscaled coordinates, so you must multiply by
///   the scale factor for a given size
void stbtt_GetFontVMetrics(const stbtt_fontinfo *info, int *ascent, int *descent, int *lineGap) nothrow @nogc
{
   if (ascent ) *ascent  = ttSHORT(info.data+info.hhea + 4);
   if (descent) *descent = ttSHORT(info.data+info.hhea + 6);
   if (lineGap) *lineGap = ttSHORT(info.data+info.hhea + 8);
}

/// the bounding box around all possible characters
void stbtt_GetFontBoundingBox(const stbtt_fontinfo *info, int *x0, int *y0, int *x1, int *y1) nothrow @nogc
{
   *x0 = ttSHORT(info.data + info.head + 36);
   *y0 = ttSHORT(info.data + info.head + 38);
   *x1 = ttSHORT(info.data + info.head + 40);
   *y1 = ttSHORT(info.data + info.head + 42);
}

/// Computes a scale factor to produce a font whose "height" is 'pixels' tall.
/// Height is measured as the distance from the highest ascender to the lowest
/// descender; in other words, it's equivalent to calling stbtt_GetFontVMetrics
/// and computing:
///       scale = pixels / (ascent - descent)
/// so if you prefer to measure height by the ascent only, use a similar calculation.
float stbtt_ScaleForPixelHeight(const stbtt_fontinfo *info, float height) nothrow @nogc
{
   int fheight = ttSHORT(info.data + info.hhea + 4) - ttSHORT(info.data + info.hhea + 6);
   return cast(float) height / fheight;
}

/// computes a scale factor to produce a font whose EM size is mapped to
/// 'pixels' tall. This is probably what traditional APIs compute, but
/// I'm not positive.
float stbtt_ScaleForMappingEmToPixels(const stbtt_fontinfo *info, float pixels) nothrow @nogc
{
   int unitsPerEm = ttUSHORT(info.data + info.head + 18);
   return pixels / unitsPerEm;
}

///
void stbtt_FreeShape(const stbtt_fontinfo *info, stbtt_vertex *v) nothrow @nogc
{
   free(v);
}

//////////////////////////////////////////////////////////////////////////////
//
// antialiasing software rasterizer
//

void stbtt_GetGlyphBitmapBoxSubpixel(const stbtt_fontinfo *font, int glyph, float scale_x, float scale_y,float shift_x, float shift_y, int *ix0, int *iy0, int *ix1, int *iy1) nothrow @nogc
{
    int x0, y0, x1, y1;
    if (!stbtt_GetGlyphBox(font, glyph, &x0, &y0, &x1, &y1))
    {
        // e.g. space character
        if (ix0) *ix0 = 0;
        if (iy0) *iy0 = 0;
        if (ix1) *ix1 = 0;
        if (iy1) *iy1 = 0;
    }
    else
    {
        // move to integral bboxes (treating pixels as little squares, what pixels get touched)?
        if (ix0) *ix0 = ifloor( x0 * scale_x + shift_x);
        if (iy0) *iy0 = ifloor(-y1 * scale_y + shift_y);
        if (ix1) *ix1 = iceil( x1 * scale_x + shift_x);
        if (iy1) *iy1 = iceil(-y0 * scale_y + shift_y);
    }
}

void stbtt_GetGlyphBitmapBox(const stbtt_fontinfo *font, int glyph, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1) nothrow @nogc
{
   stbtt_GetGlyphBitmapBoxSubpixel(font, glyph, scale_x, scale_y,0.0f,0.0f, ix0, iy0, ix1, iy1);
}

/// Same as stbtt_GetCodepointBitmapBox, but you can specify a subpixel
/// shift for the character.
void stbtt_GetCodepointBitmapBoxSubpixel(const stbtt_fontinfo *font, int codepoint, float scale_x, float scale_y, float shift_x, float shift_y, int *ix0, int *iy0, int *ix1, int *iy1) nothrow @nogc
{
   stbtt_GetGlyphBitmapBoxSubpixel(font, stbtt_FindGlyphIndex(font,codepoint), scale_x, scale_y,shift_x,shift_y, ix0,iy0,ix1,iy1);
}

/// Gets the bbox of the bitmap centered around the glyph origin; so the
/// bitmap width is ix1-ix0, height is iy1-iy0, and location to place
/// the bitmap top left is (leftSideBearing*scale,iy0).
/// (Note that the bitmap uses y-increases-down, but the shape uses
/// y-increases-up, so CodepointBitmapBox and CodepointBox are inverted.)
void stbtt_GetCodepointBitmapBox(const stbtt_fontinfo *font, int codepoint, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1) nothrow @nogc
{
   stbtt_GetCodepointBitmapBoxSubpixel(font, codepoint, scale_x, scale_y,0.0f,0.0f, ix0,iy0,ix1,iy1);
}

struct stbtt__edge
{
   float x0,y0, x1,y1;
   int invert;
}

struct stbtt__active_edge
{
   int x,dx;
   float ey;
   stbtt__active_edge* next;
   int valid;
}

enum FIXSHIFT   = 10;
enum FIX        = (1 << FIXSHIFT);
enum FIXMASK    = (FIX-1);

stbtt__active_edge *new_active(stbtt__edge *e, int off_x, float start_point) nothrow @nogc
{
   stbtt__active_edge *z = cast(stbtt__active_edge *) malloc(stbtt__active_edge.sizeof); // @TODO: make a pool of these!!!
   float dxdy = (e.x1 - e.x0) / (e.y1 - e.y0);
   assert(e.y0 <= start_point);
   if (!z) return z;
   // round dx down to avoid going too far
   if (dxdy < 0)
      z.dx = -ifloor(FIX * -dxdy);
   else
      z.dx = ifloor(FIX * dxdy);
   z.x = ifloor(FIX * (e.x0 + dxdy * (start_point - e.y0)));
   z.x -= off_x * FIX;
   z.ey = e.y1;
   z.next = null;
   z.valid = e.invert ? 1 : -1;
   return z;
}

// note: this routine clips fills that extend off the edges... ideally this
// wouldn't happen, but it could happen if the truetype glyph bounding boxes
// are wrong, or if the user supplies a too-small bitmap
void stbtt__fill_active_edges(ubyte *scanline, int len, stbtt__active_edge *e, int max_weight) nothrow @nogc
{
   // non-zero winding fill
   int x0=0, w=0;

   while (e) {
      if (w == 0) {
         // if we're currently at zero, we need to record the edge start point
         x0 = e.x; w += e.valid;
      } else {
         int x1 = e.x; w += e.valid;
         // if we went to zero, we need to draw
         if (w == 0) {
            int i = x0 >> FIXSHIFT;
            int j = x1 >> FIXSHIFT;

            if (i < len && j >= 0) {
               if (i == j) {
                  // x0,x1 are the same pixel, so compute combined coverage
                  scanline[i] = cast(ubyte)( scanline[i] + ((x1 - x0) * max_weight >> FIXSHIFT) );
               } else {
                  if (i >= 0) // add antialiasing for x0
                     scanline[i] = cast(ubyte)( scanline[i] + (((FIX - (x0 & FIXMASK)) * max_weight) >> FIXSHIFT) ) ;
                  else
                     i = -1; // clip

                  if (j < len) // add antialiasing for x1
                     scanline[j] = cast(ubyte)( scanline[j] + (((x1 & FIXMASK) * max_weight) >> FIXSHIFT) );
                  else
                     j = len; // clip

                  for (++i; i < j; ++i) // fill pixels between x0 and x1
                     scanline[i] = cast(ubyte)( scanline[i] +  max_weight );
               }
            }
         }
      }

      e = e.next;
   }
}

void stbtt__rasterize_sorted_edges(stbtt__bitmap *result, stbtt__edge *e, int n, int vsubsample, int off_x, int off_y) nothrow @nogc
{
   stbtt__active_edge* active = null;
   int y,j=0;
   int max_weight = (255 / vsubsample);  // weight per vertical scanline
   int s; // vertical subsample index
   ubyte[512] scanline_data;
   ubyte* scanline;

   if (result.w > 512)
      scanline = cast(ubyte *) malloc(result.w);
   else
      scanline = scanline_data.ptr;

   y = off_y * vsubsample;
   e[n].y0 = (off_y + result.h) * cast(float) vsubsample + 1;

   while (j < result.h) {
      memset(scanline, 0, result.w);
      for (s=0; s < vsubsample; ++s) {
         // find center of pixel for this scanline
         float scan_y = y + 0.5f;
         stbtt__active_edge **step = &active;

         // update all active edges;
         // remove all active edges that terminate before the center of this scanline
         while (*step) {
            stbtt__active_edge * z = *step;
            if (z.ey <= scan_y) {
               *step = z.next; // delete from list
               assert(z.valid);
               z.valid = 0;
               free(z);
            } else {
               z.x += z.dx; // advance to position for current scanline
               step = &((*step).next); // advance through list
            }
         }

         // resort the list if needed
         for(;;) {
            int changed=0;
            step = &active;
            while (*step && (*step).next) {
               if ((*step).x > (*step).next.x) {
                  stbtt__active_edge *t = *step;
                  stbtt__active_edge *q = t.next;

                  t.next = q.next;
                  q.next = t;
                  *step = q;
                  changed = 1;
               }
               step = &(*step).next;
            }
            if (!changed) break;
         }

         // insert all edges that start before the center of this scanline -- omit ones that also end on this scanline
         while (e.y0 <= scan_y) {
            if (e.y1 > scan_y) {
               stbtt__active_edge *z = new_active(e, off_x, scan_y);
               // find insertion point
               if (active == null)
                  active = z;
               else if (z.x < active.x) {
                  // insert at front
                  z.next = active;
                  active = z;
               } else {
                  // find thing to insert AFTER
                  stbtt__active_edge *p = active;
                  while (p.next && p.next.x < z.x)
                     p = p.next;
                  // at this point, p.next.x is NOT < z.x
                  z.next = p.next;
                  p.next = z;
               }
            }
            ++e;
         }

         // now process all active edges in XOR fashion
         if (active)
            stbtt__fill_active_edges(scanline, result.w, active, max_weight);

         ++y;
      }
      memcpy(result.pixels + j * result.stride, scanline, result.w);
      ++j;
   }

   while (active) {
      stbtt__active_edge *z = active;
      active = active.next;
      free(z);
   }

   if (scanline != scanline_data.ptr)
      free(scanline);
}


struct stbtt__point
{
   float x,y;
}

void stbtt__rasterize(stbtt__bitmap *result, stbtt__point *pts, int *wcount, int windings, float scale_x, float scale_y, float shift_x, float shift_y, int off_x, int off_y, int invert) nothrow @nogc
{
   float y_scale_inv = invert ? -scale_y : scale_y;
   stbtt__edge *e;
   int n,i,j,k,m;
   int vsubsample = result.h < 8 ? 15 : 5;
   // vsubsample should divide 255 evenly; otherwise we won't reach full opacity

   // now we have to blow out the windings into explicit edge lists
   n = 0;
   for (i=0; i < windings; ++i)
      n += wcount[i];

   e = cast(stbtt__edge *) malloc(stbtt__edge.sizeof * (n+1)); // add an extra one as a sentinel
   if (e == null) return;
   n = 0;

   m=0;
   for (i=0; i < windings; ++i) {
      stbtt__point *p = pts + m;
      m += wcount[i];
      j = wcount[i]-1;
      for (k=0; k < wcount[i]; j=k++) {
         int a=k,b=j;
         // skip the edge if horizontal
         if (p[j].y == p[k].y)
            continue;
         // add edge from j to k to the list
         e[n].invert = 0;
         if (invert ? p[j].y > p[k].y : p[j].y < p[k].y) {
            e[n].invert = 1;
            a=j,b=k;
         }
         e[n].x0 = p[a].x * scale_x + shift_x;
         e[n].y0 = (p[a].y * y_scale_inv + shift_y) * vsubsample;
         e[n].x1 = p[b].x * scale_x + shift_x;
         e[n].y1 = (p[b].y * y_scale_inv + shift_y) * vsubsample;
         ++n;
      }
   }

   int edgeCompare(const(stbtt__edge) a, const(stbtt__edge) b) nothrow @nogc
   {
       if (a.y0 < b.y0) return -1;
       if (a.y0 > b.y0) return  1;
       return 0;
   }

   // now sort the edges by their highest point (should snap to integer, and then by x)
   grailSort!stbtt__edge(e[0..n], &edgeCompare);

   // now, traverse the scanlines and find the intersections on each scanline, use xor winding rule
   stbtt__rasterize_sorted_edges(result, e, n, vsubsample, off_x, off_y);

   free(e);
}

void stbtt__add_point(stbtt__point *points, int n, float x, float y) nothrow @nogc
{
   if (!points) return; // during first pass, it's unallocated
   points[n].x = x;
   points[n].y = y;
}

// tesselate until threshhold p is happy... @TODO warped to compensate for non-linear stretching
int stbtt__tesselate_curve(stbtt__point *points, int *num_points, double x0, double y0, double x1, double y1, double x2, double y2, double objspace_flatness_squared, int n) nothrow @nogc
{
    bool stopSubdiv = (n > 16);

    // midpoint
    double mx = (x0 + 2*x1 + x2)*0.25f;
    double my = (y0 + 2*y1 + y2)*0.25f;
    // versus directly drawn line
    double dx = (x0+x2)*0.5f - mx;
    double dy = (y0+y2)*0.5f - my;
    double squarexy = dx*dx+dy*dy;

    bool addThisPoint = true;

    if (squarexy > objspace_flatness_squared && !stopSubdiv)
    {
        // half-pixel error allowed... need to be smaller if AA
        int res1, res2;
        {
            double x01h = (x0 + x1) * 0.5f;
            double y01h = (y0 + y1) * 0.5f;
            res1 = stbtt__tesselate_curve(points, num_points, x0, y0, x01h, y01h, mx,my, objspace_flatness_squared,n+1);
        }

        {
            double x12h = (x1 + x2) * 0.5f;
            double y12h = (y1 + y2) * 0.5f;
            res2 = stbtt__tesselate_curve(points, num_points, mx, my, x12h, y12h, x2,y2, objspace_flatness_squared,n+1);
        }

        addThisPoint = false;
    }

    if (addThisPoint) // do stuff here even in subdivided case to avoid TCO
    {
        stbtt__add_point(points, *num_points,x2,y2);
        *num_points = *num_points+1;
    }
    return 1;
}

// returns number of contours
stbtt__point *stbtt_FlattenCurves(stbtt_vertex *vertices, int num_verts, float objspace_flatness, int **contour_lengths, int *num_contours) nothrow @nogc
{
   stbtt__point* points = null;
   int num_points=0;

   float objspace_flatness_squared = objspace_flatness * objspace_flatness;
   int i,n=0,start=0, pass;

   // count how many "moves" there are to get the contour count
   for (i=0; i < num_verts; ++i)
      if (vertices[i].type == STBTT_vmove)
         ++n;

   *num_contours = n;
   if (n == 0) return null;

   *contour_lengths = cast(int *) malloc(int.sizeof * n);

   if (*contour_lengths == null) {
      *num_contours = 0;
      return null;
   }

   // make two passes through the points so we don't need to realloc
   for (pass=0; pass < 2; ++pass) {
      float x=0,y=0;
      if (pass == 1) {
         points = cast(stbtt__point *) malloc(num_points * stbtt__point.sizeof);
         if (points == null) goto error;
      }
      num_points = 0;
      n= -1;
      for (i=0; i < num_verts; ++i) {
         switch (vertices[i].type) {
            case STBTT_vmove:
               // start the next contour
               if (n >= 0)
                  (*contour_lengths)[n] = num_points - start;
               ++n;
               start = num_points;

               x = vertices[i].x, y = vertices[i].y;
               stbtt__add_point(points, num_points++, x,y);
               break;
            case STBTT_vline:
               x = vertices[i].x, y = vertices[i].y;
               stbtt__add_point(points, num_points++, x, y);
               break;
            case STBTT_vcurve:
               stbtt__tesselate_curve(points, &num_points, x,y,
                                        vertices[i].cx, vertices[i].cy,
                                        vertices[i].x,  vertices[i].y,
                                        objspace_flatness_squared, 0);
               x = vertices[i].x, y = vertices[i].y;
               break;
            default:
               assert(0);
         }
      }
      (*contour_lengths)[n] = num_points - start;
   }

   return points;
error:
   free(points);
   free(*contour_lengths);
   *contour_lengths = null;
   *num_contours = 0;
   return null;
}

void stbtt_Rasterize(stbtt__bitmap *result, float flatness_in_pixels, stbtt_vertex *vertices, int num_verts, float scale_x, float scale_y, float shift_x, float shift_y, int x_off, int y_off, int invert) nothrow @nogc
{
   float scale = scale_x > scale_y ? scale_y : scale_x;
   int winding_count;
   int* winding_lengths;
   stbtt__point *windings = stbtt_FlattenCurves(vertices, num_verts, flatness_in_pixels / scale, &winding_lengths, &winding_count);
   if (windings) {
      stbtt__rasterize(result, windings, winding_lengths, winding_count, scale_x, scale_y, shift_x, shift_y, x_off, y_off, invert);
      free(winding_lengths);
      free(windings);
   }
}

/// Frees the allocated bitmap.
void stbtt_FreeBitmap(ubyte *bitmap) nothrow @nogc
{
   free(bitmap);
}

ubyte *stbtt_GetGlyphBitmapSubpixel(const stbtt_fontinfo *info, float scale_x, float scale_y, float shift_x, float shift_y, int glyph, int *width, int *height, int *xoff, int *yoff) nothrow @nogc
{
   int ix0,iy0,ix1,iy1;
   stbtt__bitmap gbm;
   stbtt_vertex *vertices;
   int num_verts = stbtt_GetGlyphShape(info, glyph, &vertices);

   if (scale_x == 0) scale_x = scale_y;
   if (scale_y == 0) {
      if (scale_x == 0) return null;
      scale_y = scale_x;
   }

   stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, scale_x, scale_y, shift_x, shift_y, &ix0,&iy0,&ix1,&iy1);

   // now we get the size
   gbm.w = (ix1 - ix0);
   gbm.h = (iy1 - iy0);
   gbm.pixels = null; // in case we error

   if (width ) *width  = gbm.w;
   if (height) *height = gbm.h;
   if (xoff  ) *xoff   = ix0;
   if (yoff  ) *yoff   = iy0;

   if (gbm.w && gbm.h) {
      gbm.pixels = cast(ubyte *) malloc(gbm.w * gbm.h);
      if (gbm.pixels) {
         gbm.stride = gbm.w;

         stbtt_Rasterize(&gbm, 0.35f, vertices, num_verts, scale_x, scale_y, shift_x, shift_y, ix0, iy0, 1);
      }
   }
   free(vertices);
   return gbm.pixels;
}

ubyte *stbtt_GetGlyphBitmap(const stbtt_fontinfo *info, float scale_x, float scale_y, int glyph, int *width, int *height, int *xoff, int *yoff) nothrow @nogc
{
   return stbtt_GetGlyphBitmapSubpixel(info, scale_x, scale_y, 0.0f, 0.0f, glyph, width, height, xoff, yoff);
}

void stbtt_MakeGlyphBitmapSubpixel(const stbtt_fontinfo *info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int glyph) nothrow @nogc
{
   int ix0,iy0;
   stbtt_vertex *vertices;
   int num_verts = stbtt_GetGlyphShape(info, glyph, &vertices);
   stbtt__bitmap gbm;

   stbtt_GetGlyphBitmapBoxSubpixel(info, glyph, scale_x, scale_y, shift_x, shift_y, &ix0,&iy0,null,null);
   gbm.pixels = output;
   gbm.w = out_w;
   gbm.h = out_h;
   gbm.stride = out_stride;

   if (gbm.w && gbm.h)
      stbtt_Rasterize(&gbm, 0.35f, vertices, num_verts, scale_x, scale_y, shift_x, shift_y, ix0,iy0, 1);

   free(vertices);
}

void stbtt_MakeGlyphBitmap(const stbtt_fontinfo *info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int glyph) nothrow @nogc
{
   stbtt_MakeGlyphBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, 0.0f,0.0f, glyph);
}

/// The same as stbtt_GetCodepoitnBitmap, but you can specify a subpixel
/// shift for the character.
ubyte *stbtt_GetCodepointBitmapSubpixel(const stbtt_fontinfo *info, float scale_x, float scale_y, float shift_x, float shift_y, int codepoint, int *width, int *height, int *xoff, int *yoff) nothrow @nogc
{
   return stbtt_GetGlyphBitmapSubpixel(info, scale_x, scale_y,shift_x,shift_y, stbtt_FindGlyphIndex(info,codepoint), width,height,xoff,yoff);
}

/// Same as stbtt_MakeCodepointBitmap, but you can specify a subpixel
/// shift for the character.
void stbtt_MakeCodepointBitmapSubpixel(const stbtt_fontinfo *info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, float shift_x, float shift_y, int codepoint) nothrow @nogc
{
   stbtt_MakeGlyphBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, shift_x, shift_y, stbtt_FindGlyphIndex(info,codepoint));
}

/// Allocates a large-enough single-channel 8bpp bitmap and renders the
/// specified character/glyph at the specified scale into it, with
/// antialiasing. 0 is no coverage (transparent), 255 is fully covered (opaque).
/// *width & *height are filled out with the width & height of the bitmap,
/// which is stored left-to-right, top-to-bottom.
///
/// xoff/yoff are the offset it pixel space from the glyph origin to the top-left of the bitmap
ubyte *stbtt_GetCodepointBitmap(const stbtt_fontinfo *info, float scale_x, float scale_y, int codepoint, int *width, int *height, int *xoff, int *yoff) nothrow @nogc
{
   return stbtt_GetCodepointBitmapSubpixel(info, scale_x, scale_y, 0.0f,0.0f, codepoint, width,height,xoff,yoff);
}

/// The same as stbtt_GetCodepointBitmap, but you pass in storage for the bitmap
/// in the form of 'output', with row spacing of 'out_stride' bytes. the bitmap
/// is clipped to out_w/out_h bytes. Call stbtt_GetCodepointBitmapBox to get the
/// width and height and positioning info for it first.
void stbtt_MakeCodepointBitmap(const stbtt_fontinfo *info, ubyte *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int codepoint) nothrow @nogc
{
   stbtt_MakeCodepointBitmapSubpixel(info, output, out_w, out_h, out_stride, scale_x, scale_y, 0.0f,0.0f, codepoint);
}

