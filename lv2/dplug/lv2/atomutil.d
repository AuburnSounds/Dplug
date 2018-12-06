/*
  Copyright 2008-2015 David Robillard <http://drobilla.net>
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
   @file util.h Helper functions for the LV2 Atom extension.

   This header is non-normative, it is provided for convenience.
*/

/**
   @defgroup util Utilities
   @ingroup atom
   @{
*/
module dplug.lv2.atomutil;

import core.stdc.stdarg;
import core.stdc.stdint;
import core.stdc.string;

import dplug.lv2.atom;

extern(C) {

    /** Pad a size to 64 bits. */
    
    static uint32_t
    lv2_atom_pad_size(uint32_t size)
    {
        return (size + 7U) & (~7U);
    }

    /** Return the total size of `atom`, including the header. */
    
    static uint32_t
    lv2_atom_total_size(const LV2_Atom* atom)
    {
        return cast(uint32_t)(LV2_Atom.sizeof) + atom.size;
    }

    /** Return true iff `atom` is null. */
    
    static bool
    lv2_atom_is_null(const LV2_Atom* atom)
    {
        return !atom || (atom.type == 0 && atom.size == 0);
    }

    /** Return true iff `a` is equal to `b`. */
    
    static bool
    lv2_atom_equals(const LV2_Atom* a, const LV2_Atom* b)
    {
        return (a == b) || ((a.type == b.type) &&
                            (a.size == b.size) &&
                            !memcmp(a + 1, b + 1, a.size));
    }

    /**
    @name Sequence Iterator
    @{
    */

    /** Get an iterator pointing to the first event in a Sequence body. */
    
    static LV2_Atom_Event*
    lv2_atom_sequence_begin(const LV2_Atom_Sequence_Body* body)
    {
        return cast(LV2_Atom_Event*)(body + 1);
    }

    /** Get an iterator pointing to the end of a Sequence body. */
    
    static LV2_Atom_Event*
    lv2_atom_sequence_end(const LV2_Atom_Sequence_Body* body, uint32_t size)
    {
        return cast(LV2_Atom_Event*)(cast(const uint8_t*)body + lv2_atom_pad_size(size));
    }

    /** Return true iff `i` has reached the end of `body`. */
    
    static bool
    lv2_atom_sequence_is_end(const LV2_Atom_Sequence_Body* body,
                            uint32_t                      size,
                            const LV2_Atom_Event*         i)
    {
        return cast(const uint8_t*)i >= (cast(const uint8_t*)body + size);
    }

    /** Return an iterator to the element following `i`. */
    
    static LV2_Atom_Event*
    lv2_atom_sequence_next(const LV2_Atom_Event* i)
    {
        return cast(LV2_Atom_Event*)(cast(const uint8_t*)i
                                + LV2_Atom_Event.sizeof
                                + lv2_atom_pad_size(i.body.size));
    }

    /**
    A macro for iterating over all events in a Sequence.
    @param seq  The sequence to iterate over
    @param iter The name of the iterator

    This macro is used similarly to a for loop (which it expands to), e.g.:
    @code
    LV2_ATOM_SEQUENCE_FOREACH(sequence, ev) {
        // Do something with ev (an LV2_Atom_Event*) here...
    }
    @endcode
    */
    // #define LV2_ATOM_SEQUENCE_FOREACH(seq, iter) \
    //     for (LV2_Atom_Event* (iter) = lv2_atom_sequence_begin(&(seq).body); \
    //         !lv2_atom_sequence_is_end(&(seq).body, (seq).atom.size, (iter)); \
    //         (iter) = lv2_atom_sequence_next(iter))
    // mixin template LV2_ATOM_SEQUENCE_FOREACH(seq, iter)
    // {
    //     mixin("for (LV2_Atom_Event* (iter) = lv2_atom_sequence_begin(&(seq).body)
    //         !lv2_atom_sequence_is_end(&(seq).body, (seq).atom.size, (iter))
    //         (iter) = lv2_atom_sequence_next(iter))");
    // }

    // /** Like LV2_ATOM_SEQUENCE_FOREACH but for a headerless sequence body. */
    // #define LV2_ATOM_SEQUENCE_BODY_FOREACH(body, size, iter) \
    //     for (LV2_Atom_Event* (iter) = lv2_atom_sequence_begin(body); \
    //         !lv2_atom_sequence_is_end(body, size, (iter)); \
    //         (iter) = lv2_atom_sequence_next(iter))

    /**
    @}
    @name Sequence Utilities
    @{
    */

    /**
    Clear all events from `sequence`.

    This simply resets the size field, the other fields are left untouched.
    */
    
    static void
    lv2_atom_sequence_clear(LV2_Atom_Sequence* seq)
    {
        seq.atom.size = LV2_Atom_Sequence_Body.sizeof;
    }

    /**
    Append an event at the end of `sequence`.

    @param seq Sequence to append to.
    @param capacity Total capacity of the sequence atom
    (e.g. as set by the host for sequence output ports).
    @param event Event to write.

    @return A pointer to the newly written event in `seq`,
    or NULL on failure (insufficient space).
    */
    
    static LV2_Atom_Event*
    lv2_atom_sequence_append_event(LV2_Atom_Sequence*    seq,
                                uint32_t              capacity,
                                const LV2_Atom_Event* event)
    {
        const uint32_t total_size = cast(uint32_t)(*event).sizeof + event.body.size;
        if (capacity - seq.atom.size < total_size) {
            return null;
        }

        LV2_Atom_Event* e = lv2_atom_sequence_end(&seq.body, seq.atom.size);
        memcpy(e, event, total_size);

        seq.atom.size += lv2_atom_pad_size(total_size);

        return e;
    }

    /**
    @}
    @name Tuple Iterator
    @{
    */

    /** Get an iterator pointing to the first element in `tup`. */
    
    static LV2_Atom*
    lv2_atom_tuple_begin(const (LV2_Atom_Tuple)* tup)
    {
        return cast(LV2_Atom*)(cast(void*)(cast(uint8_t*)(tup) + LV2_Atom.sizeof));
    }

    /** Return true iff `i` has reached the end of `body`. */
    
    static bool
    lv2_atom_tuple_is_end(const void* body, uint32_t size, const LV2_Atom* i)
    {
        return cast(const uint8_t*)i >= (cast(const uint8_t*)body + size);
    }

    /** Return an iterator to the element following `i`. */
    
    static LV2_Atom*
    lv2_atom_tuple_next(const LV2_Atom* i)
    {
        return cast(LV2_Atom*)(
            cast(const uint8_t*)i + LV2_Atom.sizeof + lv2_atom_pad_size(i.size));
    }

    /**
    @}
    @name Object Iterator
    @{
    */

    /** Return a pointer to the first property in `body`. */
    
    static LV2_Atom_Property_Body*
    lv2_atom_object_begin(const LV2_Atom_Object_Body* body)
    {
        return cast(LV2_Atom_Property_Body*)(body + 1);
    }

    /** Return true iff `i` has reached the end of `obj`. */
    
    static bool
    lv2_atom_object_is_end(const LV2_Atom_Object_Body*   body,
                        uint32_t                      size,
                        const LV2_Atom_Property_Body* i)
    {
        return cast(const uint8_t*)i >= (cast(const uint8_t*)body + size);
    }

    /** Return an iterator to the property following `i`. */
    
    static LV2_Atom_Property_Body*
    lv2_atom_object_next(const LV2_Atom_Property_Body* i)
    {
        const LV2_Atom* value = cast(const LV2_Atom*)(
            cast(const uint8_t*)i + 2 * uint32_t.sizeof);
        return cast(LV2_Atom_Property_Body*)(
            cast(const uint8_t*)i + lv2_atom_pad_size(
                cast(uint32_t)LV2_Atom_Property_Body.sizeof + value.size));
    }

    /**
    A macro for iterating over all properties of an Object.
    @param obj The object to iterate over
    @param iter The name of the iterator

    This macro is used similarly to a for loop (which it expands to), e.g.:
    @code
    LV2_ATOM_OBJECT_FOREACH(object, i) {
        // Do something with prop (an LV2_Atom_Property_Body*) here...
    }
    @endcode
    */

    /**
    @}
    @name Object Query
    @{
    */

    /** A single entry in an Object query. */
    struct LV2_Atom_Object_Query {
        uint32_t         key;    /**< Key to query (input set by user) */
        const (LV2_Atom)** value;  /**< Found value (output set by query function) */
    }

    static const LV2_Atom_Object_Query LV2_ATOM_OBJECT_QUERY_END = { 0, null };

    /**
    Get an object's values for various keys.

    The value pointer of each item in `query` will be set to the location of
    the corresponding value in `object`.  Every value pointer in `query` MUST
    be initialised to NULL.  This function reads `object` in a single linear
    sweep.  By allocating `query` on the stack, objects can be "queried"
    quickly without allocating any memory.  This function is realtime safe.

    This function can only do "flat" queries, it is not smart enough to match
    variables in nested objects.

    For example:
    @code
    const LV2_Atom* name = NULL;
    const LV2_Atom* age  = NULL;
    LV2_Atom_Object_Query q[] = {
        { urids.eg_name, &name },
        { urids.eg_age,  &age },
        LV2_ATOM_OBJECT_QUERY_END
    };
    lv2_atom_object_query(obj, q);
    // name and age are now set to the appropriate values in obj, or NULL.
    @endcode
    */
    
    static int
    lv2_atom_object_query(const LV2_Atom_Object* object,
                        LV2_Atom_Object_Query* query)
    {
        int matches   = 0;
        int n_queries = 0;

        /* Count number of query keys so we can short-circuit when done */
        for (LV2_Atom_Object_Query* q = query; q.key; ++q) {
            ++n_queries;
        }

        for (LV2_Atom_Property_Body* prop = lv2_atom_object_begin(&(object).body);
             !lv2_atom_object_is_end(&(object).body, (object).atom.size, (prop));
             (prop) = lv2_atom_object_next(prop))
        {
            for (LV2_Atom_Object_Query* q = query; q.key; ++q) {
                if (q.key == prop.key && !*q.value) {
                    *q.value = &prop.value;
                    if (++matches == n_queries) {
                        return matches;
                    }
                    break;
                }
            }
        }
        return matches;
    }

    /**
    Body only version of lv2_atom_object_get().
    */
    
    static int
    lv2_atom_object_body_get(uint32_t size, const LV2_Atom_Object_Body* body, ...)
    {
        int matches   = 0;
        int n_queries = 0;

        /* Count number of keys so we can short-circuit when done */
        va_list args;
        va_start!(const LV2_Atom_Object_Body*)(args, body);
        for (n_queries = 0; va_arg!(uint32_t)(args); ++n_queries) {
            if (!va_arg!(const (LV2_Atom)**)(args)) {
                return -1;
            }
        }
        va_end(args);

        for (LV2_Atom_Property_Body* prop = lv2_atom_object_begin(body);
         !lv2_atom_object_is_end(body, size, prop);
         prop = lv2_atom_object_next(prop))
        {
            va_start!(const LV2_Atom_Object_Body*)(args, body);
            for (int i = 0; i < n_queries; ++i) {
                uint32_t         qkey = va_arg!(uint32_t)(args);
                const (LV2_Atom)** qval = va_arg!(const (LV2_Atom)**)(args);
                if (qkey == prop.key && !*qval) {
                    *qval = &prop.value;
                    if (++matches == n_queries) {
                        return matches;
                    }
                    break;
                }
            }
            va_end(args);
        }
        return matches;
    }

    /**
    Variable argument version of lv2_atom_object_query().

    This is nicer-looking in code, but a bit more error-prone since it is not
    type safe and the argument list must be terminated.

    The arguments should be a series of uint32_t key and const LV2_Atom** value
    pairs, terminated by a zero key.  The value pointers MUST be initialized to
    NULL.  For example:

    @code
    const LV2_Atom* name = NULL;
    const LV2_Atom* age  = NULL;
    lv2_atom_object_get(obj,
                        uris.name_key, &name,
                        uris.age_key,  &age,
                        0);
    @endcode
    */
    
    static int
    lv2_atom_object_get(const LV2_Atom_Object* object, ...)
    {
        int matches   = 0;
        int n_queries = 0;

        /* Count number of keys so we can short-circuit when done */
        va_list args;
        va_start!(const LV2_Atom_Object*)(args, object);
        for (n_queries = 0; va_arg!(uint32_t)(args); ++n_queries) {
            if (!va_arg!(const (LV2_Atom)**)(args)) {
                return -1;
            }
        }
        va_end(args);

        for (LV2_Atom_Property_Body* prop = lv2_atom_object_begin(&(object).body);
             !lv2_atom_object_is_end(&(object).body, (object).atom.size, (prop));
             (prop) = lv2_atom_object_next(prop))
        {
            va_start!(const LV2_Atom_Object*)(args, object);
            for (int i = 0; i < n_queries; ++i) {
                uint32_t         qkey = va_arg!(uint32_t)(args);
                const (LV2_Atom)** qval = va_arg!(const (LV2_Atom)**)(args);
                if (qkey == prop.key && !*qval) {
                    *qval = &prop.value;
                    if (++matches == n_queries) {
                        return matches;
                    }
                    break;
                }
            }
            va_end(args);
        }
        return matches;
    }
}
