/*
  Copyright 2008-2016 David Robillard <http://drobilla.net>
  Copyright 2011 Gabriel M. Beddingfield <gabrbedd@gmail.com>
  Copyright 2018 Ethan Reker <http://cutthroughrecordings.com>

  Permission to use, copy, modify, and/or distribute this software for any
  purpose with or without fee is hereby granted, provided that the above
  copyright notice and this permission notice appear in all copies.

  THIS SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
*/
module dplug.lv2.urid;

/**
   @defgroup urid URID

   Features for mapping URIs to and from integers, see
   <http://lv2plug.in/ns/ext/urid> for details.

   @{
*/

enum LV2_URID_URI = "http://lv2plug.in/ns/ext/urid";  ///< http://lv2plug.in/ns/ext/urid
enum LV2_URID_PREFIX = LV2_URID_URI ~ "#";                 ///< http://lv2plug.in/ns/ext/urid#

enum LV2_URID__map  = LV2_URID_PREFIX ~ "map";    ///< http://lv2plug.in/ns/ext/urid#map
enum LV2_URID__unmap = LV2_URID_PREFIX ~ "unmap";  ///< http://lv2plug.in/ns/ext/urid#unmap

enum LV2_URID_MAP_URI   = LV2_URID__map;    ///< Legacy
enum LV2_URID_UNMAP_URI = LV2_URID__unmap;  ///< Legacy

import core.stdc.stdint;

extern(C) {

    /**
    Opaque pointer to host data for LV2_URID_Map.
    */
    alias LV2_URID_Map_Handle = void*;

    /**
    Opaque pointer to host data for LV2_URID_Unmap.
    */
    alias LV2_URID_Unmap_Handle = void*;

    /**
    URI mapped to an integer.
    */
    alias LV2_URID = uint32_t;

    /**
    URID Map Feature (LV2_URID__map)
    */
    struct _LV2_URID_Map {
        /**
        Opaque pointer to host data.

        This MUST be passed to map_uri() whenever it is called.
        Otherwise, it must not be interpreted in any way.
        */
        LV2_URID_Map_Handle handle;

        /**
        Get the numeric ID of a URI.

        If the ID does not already exist, it will be created.

        This function is referentially transparent; any number of calls with the
        same arguments is guaranteed to return the same value over the life of a
        plugin instance.  Note, however, that several URIs MAY resolve to the
        same ID if the host considers those URIs equivalent.

        This function is not necessarily very fast or RT-safe: plugins SHOULD
        cache any IDs they might need in performance critical situations.

        The return value 0 is reserved and indicates that an ID for that URI
        could not be created for whatever reason.  However, hosts SHOULD NOT
        return 0 from this function in non-exceptional circumstances (i.e. the
        URI map SHOULD be dynamic).

        @param handle Must be the callback_data member of this struct.
        @param uri The URI to be mapped to an integer ID.
        */
        LV2_URID function(LV2_URID_Map_Handle handle,
                        const char*         uri) map;
    }
    alias LV2_URID_Map = _LV2_URID_Map;

    /**
    URI Unmap Feature (LV2_URID__unmap)
    */
    struct _LV2_URID_Unmap {
        /**
        Opaque pointer to host data.

        This MUST be passed to unmap() whenever it is called.
        Otherwise, it must not be interpreted in any way.
        */
        LV2_URID_Unmap_Handle handle;

        /**
        Get the URI for a previously mapped numeric ID.

        Returns NULL if `urid` is not yet mapped.  Otherwise, the corresponding
        URI is returned in a canonical form.  This MAY not be the exact same
        string that was originally passed to LV2_URID_Map::map(), but it MUST be
        an identical URI according to the URI syntax specification (RFC3986).  A
        non-NULL return for a given `urid` will always be the same for the life
        of the plugin.  Plugins that intend to perform string comparison on
        unmapped URIs SHOULD first canonicalise URI strings with a call to
        map_uri() followed by a call to unmap_uri().

        @param handle Must be the callback_data member of this struct.
        @param urid The ID to be mapped back to the URI string.
        */
        const char* function(LV2_URID_Unmap_Handle handle,
                            LV2_URID              urid) unmap;
    }
    alias LV2_URID_Unmap = _LV2_URID_Unmap;

}