/*
  Copyright 2010-2016 David Robillard <http://drobilla.net>
  Copyright 2010 Leonard Ritter <paniq@paniq.org>
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

/**
   @defgroup state State

   An interface for LV2 plugins to save and restore state, see
   <http://lv2plug.in/ns/ext/state> for details.

   @{
*/
module dplug.lv2.state;

version(LV2):

nothrow @nogc:

import core.stdc.stddef;
import core.stdc.stdint;

import dplug.lv2.lv2;

enum LV2_STATE_URI    = "http://lv2plug.in/ns/ext/state";  ///< http://lv2plug.in/ns/ext/state
enum LV2_STATE_PREFIX = LV2_STATE_URI ~ "#";                 ///< http://lv2plug.in/ns/ext/state#

enum LV2_STATE__State             = LV2_STATE_PREFIX ~ "State";              ///< http://lv2plug.in/ns/ext/state#State
enum LV2_STATE__interface         = LV2_STATE_PREFIX ~ "interface";          ///< http://lv2plug.in/ns/ext/state#interface
enum LV2_STATE__loadDefaultState  = LV2_STATE_PREFIX ~ "loadDefaultState";   ///< http://lv2plug.in/ns/ext/state#loadDefaultState
enum LV2_STATE__makePath          = LV2_STATE_PREFIX ~ "makePath";           ///< http://lv2plug.in/ns/ext/state#makePath
enum LV2_STATE__mapPath           = LV2_STATE_PREFIX ~ "mapPath";            ///< http://lv2plug.in/ns/ext/state#mapPath
enum LV2_STATE__state             = LV2_STATE_PREFIX ~ "state";              ///< http://lv2plug.in/ns/ext/state#state
enum LV2_STATE__threadSafeRestore = LV2_STATE_PREFIX ~ "threadSafeRestore";  ///< http://lv2plug.in/ns/ext/state#threadSafeRestore

alias LV2_State_Handle           = void*; ///b< Opaque handle for state save/restore
alias LV2_State_Map_Path_Handle  = void*; ///< Opaque handle for state:mapPath feature
alias LV2_State_Make_Path_Handle = void*; ///< Opaque handle for state:makePath feature

/**
   Flags describing value characteristics.

   These flags are used along with the value's type URI to determine how to
   (de-)serialise the value data, or whether it is even possible to do so.
*/
alias LV2_State_Flags = int;
enum : LV2_State_Flags {
   /**
      Plain Old Data.

      Values with this flag contain no pointers or references to other areas
      of memory.  It is safe to copy POD values with a simple memcpy and store
      them for the duration of the process.  A POD value is not necessarily
      safe to transmit between processes or machines (e.g. filenames are POD),
      see LV2_STATE_IS_PORTABLE for details.

      Implementations MUST NOT attempt to copy or serialise a non-POD value if
      they do not understand its type (and thus know how to correctly do so).
   */
   LV2_STATE_IS_POD = 1,

   /**
      Portable (architecture independent) data.

      Values with this flag are in a format that is usable on any
      architecture.  A portable value saved on one machine can be restored on
      another machine regardless of architecture.  The format of portable
      values MUST NOT depend on architecture-specific properties like
      endianness or alignment.  Portable values MUST NOT contain filenames.
   */
   LV2_STATE_IS_PORTABLE = 1 << 1,

   /**
      Native data.

      This flag is used by the host to indicate that the saved data is only
      going to be used locally in the currently running process (e.g. for
      instance duplication or snapshots), so the plugin should use the most
      efficient representation possible and not worry about serialisation
      and portability.
   */
   LV2_STATE_IS_NATIVE = 1 << 2
}

/** A status code for state functions. */
alias LV2_State_Status = int;
enum : int {
   LV2_STATE_SUCCESS         = 0,  /**< Completed successfully. */
   LV2_STATE_ERR_UNKNOWN     = 1,  /**< Unknown error. */
   LV2_STATE_ERR_BAD_TYPE    = 2,  /**< Failed due to unsupported type. */
   LV2_STATE_ERR_BAD_FLAGS   = 3,  /**< Failed due to unsupported flags. */
   LV2_STATE_ERR_NO_FEATURE  = 4,  /**< Failed due to missing features. */
   LV2_STATE_ERR_NO_PROPERTY = 5,  /**< Failed due to missing property. */
   LV2_STATE_ERR_NO_SPACE    = 6   /**< Failed due to insufficient space. */
}

/**
   A host-provided function to store a property.
   @param handle Must be the handle passed to LV2_State_Interface.save().
   @param key The key to store `value` under (URID).
   @param value Pointer to the value to be stored.
   @param size The size of `value` in bytes.
   @param type The type of `value` (URID).
   @param flags LV2_State_Flags for `value`.
   @return 0 on success, otherwise a non-zero error code.

   The host passes a callback of this type to LV2_State_Interface.save(). This
   callback is called repeatedly by the plugin to store all the properties that
   describe its current state.

   DO NOT INVENT NONSENSE URI SCHEMES FOR THE KEY.  Best is to use keys from
   existing vocabularies.  If nothing appropriate is available, use http URIs
   that point to somewhere you can host documents so documentation can be made
   resolvable (e.g. a child of the plugin or project URI).  If this is not
   possible, invent a URN scheme, e.g. urn:myproj:whatever.  The plugin MUST
   NOT pass an invalid URI key.

   The host MAY fail to store a property for whatever reason, but SHOULD
   store any property that is LV2_STATE_IS_POD and LV2_STATE_IS_PORTABLE.
   Implementations SHOULD use the types from the LV2 Atom extension
   (http://lv2plug.in/ns/ext/atom) wherever possible.  The plugin SHOULD
   attempt to fall-back and avoid the error if possible.

   Note that `size` MUST be > 0, and `value` MUST point to a valid region of
   memory `size` bytes long (this is required to make restore unambiguous).

   The plugin MUST NOT attempt to use this function outside of the
   LV2_State_Interface.restore() context.
*/
extern(C)
{
    alias LV2_State_Store_Function = LV2_State_Status function(LV2_State_Handle handle, uint key, const(void)* value, size_t size, uint type, uint flags);
}

/**
   A host-provided function to retrieve a property.
   @param handle Must be the handle passed to LV2_State_Interface.restore().
   @param key The key of the property to retrieve (URID).
   @param size (Output) If non-NULL, set to the size of the restored value.
   @param type (Output) If non-NULL, set to the type of the restored value.
   @param flags (Output) If non-NULL, set to the flags for the restored value.
   @return A pointer to the restored value (object), or NULL if no value
   has been stored under `key`.

   A callback of this type is passed by the host to
   LV2_State_Interface.restore().  This callback is called repeatedly by the
   plugin to retrieve any properties it requires to restore its state.

   The returned value MUST remain valid until LV2_State_Interface.restore()
   returns.  The plugin MUST NOT attempt to use this function, or any value
   returned from it, outside of the LV2_State_Interface.restore() context.
*/
extern(C)
{
    alias LV2_State_Retrieve_Function = const(void)* function(LV2_State_Handle handle, uint key, size_t* size, uint* type, uint* flags);
}

/**
   LV2 Plugin State Interface.

   When the plugin's extension_data is called with argument
   LV2_STATE__interface, the plugin MUST return an LV2_State_Interface
   structure, which remains valid for the lifetime of the plugin.

   The host can use the contained function pointers to save and restore the
   state of a plugin instance at any time, provided the threading restrictions
   of the functions are met.

   Stored data is only guaranteed to be compatible between instances of plugins
   with the same URI (i.e. if a change to a plugin would cause a fatal error
   when restoring state saved by a previous version of that plugin, the plugin
   URI MUST change just as it must when ports change incompatibly).  Plugin
   authors should consider this possibility, and always store sensible data
   with meaningful types to avoid such problems in the future.
*/
struct LV2_State_Interface 
{
nothrow @nogc:
   /**
      Save plugin state using a host-provided `store` callback.

      @param instance The instance handle of the plugin.
      @param store The host-provided store callback.
      @param handle An opaque pointer to host data which MUST be passed as the
      handle parameter to `store` if it is called.
      @param flags Flags describing desired properties of this save.  These
      flags may be used to determine the most appropriate values to store.
      @param features Extensible parameter for passing any additional
      features to be used for this save.

      The plugin is expected to store everything necessary to completely
      restore its state later.  Plugins SHOULD store simple POD data whenever
      possible, and consider the possibility of state being restored much
      later on a different machine.

      The `handle` pointer and `store` function MUST NOT be used
      beyond the scope of save().

      This function has its own special threading class: it may not be called
      concurrently with any "Instantiation" function, but it may be called
      concurrently with functions in any other class, unless the definition of
      that class prohibits it (e.g. it may not be called concurrently with a
      "Discovery" function, but it may be called concurrently with an "Audio"
      function.  The plugin is responsible for any locking or lock-free
      techniques necessary to make this possible.

      Note that in the simple case where state is only modified by restore(),
      there are no synchronization issues since save() is never called
      concurrently with restore() (though run() may read it during a save).

      Plugins that dynamically modify state while running, however, must take
      care to do so in such a way that a concurrent call to save() will save a
      consistent representation of plugin state for a single instant in time.
   */
    extern(C)
    {
        alias saveFun_t = LV2_State_Status function(LV2_Handle                 instance,
                                                  LV2_State_Store_Function   store,
                                                  LV2_State_Handle           handle,
                                                  uint                   flags,
                                                  const(LV2_Feature*)*       features);
    }
    saveFun_t save;

   /**
      Restore plugin state using a host-provided `retrieve` callback.

      @param instance The instance handle of the plugin.
      @param retrieve The host-provided retrieve callback.
      @param handle An opaque pointer to host data which MUST be passed as the
      handle parameter to `retrieve` if it is called.
      @param flags Currently unused.
      @param features Extensible parameter for passing any additional
      features to be used for this restore.

      The plugin MAY assume a restored value was set by a previous call to
      LV2_State_Interface.save() by a plugin with the same URI.

      The plugin MUST gracefully fall back to a default value when a value can
      not be retrieved.  This allows the host to reset the plugin state with
      an empty map.

      The `handle` pointer and `store` function MUST NOT be used
      beyond the scope of restore().

      This function is in the "Instantiation" threading class as defined by
      LV2. This means it MUST NOT be called concurrently with any other
      function on the same plugin instance.
   */
   extern(C)
   {
       alias restoreFun_t = LV2_State_Status function(LV2_Handle                  instance,
                                                   LV2_State_Retrieve_Function retrieve,
                                                   LV2_State_Handle            handle,
                                                   uint                    flags,
                                                   const(LV2_Feature*)*       features);
   }
   restoreFun_t restore;
   
};
