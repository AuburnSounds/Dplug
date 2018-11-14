//-----------------------------------------------------------------------------
// Project     : SDK Core
//
// Category    : SDK Core Interfaces
// Filename    : pluginterfaces/base/funknown.h
// Created by  : Steinberg, 01/2004
// Description : Basic Interface
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------
module dplug.vst3.funknown;

import dplug.vst3.ftypes;
import dplug.vst3.fplatform;

nothrow:
@nogc:

/+
#include "pluginterfaces/base/smartpointer.h"
#include <string.h>

+/

static if (COM_COMPATIBLE)
{
    TUID INLINE_UID(uint l1, uint l2, uint l3, uint l4) pure @safe
    {
        return 
        [
            cast(byte)((l1 & 0x000000FF)      ), cast(byte)((l1 & 0x0000FF00) >>  8),
            cast(byte)((l1 & 0x00FF0000) >> 16), cast(byte)((l1 & 0xFF000000) >> 24),
            cast(byte)((l2 & 0x00FF0000) >> 16), cast(byte)((l2 & 0xFF000000) >> 24),
            cast(byte)((l2 & 0x000000FF)      ), cast(byte)((l2 & 0x0000FF00) >>  8),
            cast(byte)((l3 & 0xFF000000) >> 24), cast(byte)((l3 & 0x00FF0000) >> 16),
            cast(byte)((l3 & 0x0000FF00) >>  8), cast(byte)((l3 & 0x000000FF)      ),
            cast(byte)((l4 & 0xFF000000) >> 24), cast(byte)((l4 & 0x00FF0000) >> 16),
            cast(byte)((l4 & 0x0000FF00) >>  8), cast(byte)((l4 & 0x000000FF)      ) 
        ];
    }
}
else
{
    TUID INLINE_UID(uint l1, uint l2, uint l3, uint l4) pure @safe
    {
        return 
        [
            cast(byte)((l1 & 0xFF000000) >> 24), cast(byte)((l1 & 0x00FF0000) >> 16),
            cast(byte)((l1 & 0x0000FF00) >>  8), cast(byte)((l1 & 0x000000FF)      ),
            cast(byte)((l2 & 0xFF000000) >> 24), cast(byte)((l2 & 0x00FF0000) >> 16),
            cast(byte)((l2 & 0x0000FF00) >>  8), cast(byte)((l2 & 0x000000FF)      ),
            cast(byte)((l3 & 0xFF000000) >> 24), cast(byte)((l3 & 0x00FF0000) >> 16),
            cast(byte)((l3 & 0x0000FF00) >>  8), cast(byte)((l3 & 0x000000FF)      ),
            cast(byte)((l4 & 0xFF000000) >> 24), cast(byte)((l4 & 0x00FF0000) >> 16),
            cast(byte)((l4 & 0x0000FF00) >>  8), cast(byte)((l4 & 0x000000FF)      ) 
        ];
    }
}
/+
//------------------------------------------------------------------------
#define DECLARE_UID(name, l1, l2, l3, l4) ::Steinberg::TUID name = INLINE_UID (l1, l2, l3, l4);

//------------------------------------------------------------------------
#define EXTERN_UID(name) extern const ::Steinberg::TUID name;

#ifdef INIT_CLASS_IID
#define DECLARE_CLASS_IID(ClassName, l1, l2, l3, l4)                              \
    static const ::Steinberg::TUID ClassName##_iid = INLINE_UID (l1, l2, l3, l4); \
    \
const ::Steinberg::FUID ClassName::iid (ClassName##_iid);
#else
#define DECLARE_CLASS_IID(ClassName, l1, l2, l3, l4) \
    static const ::Steinberg::TUID ClassName##_iid = INLINE_UID (l1, l2, l3, l4);
#endif

#define DEF_CLASS_IID(ClassName) const ::Steinberg::FUID ClassName::iid (ClassName##_iid);

#define INLINE_UID_OF(ClassName) ClassName##_iid

#define INLINE_UID_FROM_FUID(x) \
    INLINE_UID (x.getLong1 (), x.getLong2 (), x.getLong3 (), x.getLong4 ())

//------------------------------------------------------------------------
//  FUnknown implementation macros
//------------------------------------------------------------------------
+/
/*
mixin template DECLARE_FUNKNOWN_METHODS()
{
    public nothrow @nogc
    {
        override tresult queryInterface (const ::Steinberg::TUID _iid, void** obj)
        override uint addRef ()
        override uint release ()

    }
    
}*/


/+
#define DELEGATE_REFCOUNT(ClassName)                                                    \
public:                                                                                 \
    virtual ::Steinberg::uint32 PLUGIN_API addRef () SMTG_OVERRIDE { return ClassName::addRef ();  } \
    virtual ::Steinberg::uint32 PLUGIN_API release () SMTG_OVERRIDE { return ClassName::release (); }

+/

mixin template IMPLEMENT_REFCOUNT()
{
    public nothrow @nogc
    {
        override uint addRef()
        {
            return atomicAdd(_funknownRefCount, 1);
        }

        override uint release()
        {
            import dplug.core.nogc: destroyFree;

            int decremented = atomicAdd(_funknownRefCount, -1);
            if (decremented == 0)
                destroyFree(this);
            return decremented;
        }
    }

    protected shared(int) _funknownRefCount = 1; // when constructed, first value is 1
}

mixin template QUERY_INTERFACE(Interfaces...)// interfaces)
{
    override tresult queryInterface (ref const TUID _iid, void** obj)
    {
        foreach(initer; Interfaces)
        {
            if (iidEqual (_iid, initer.iid.toTUID))
            {
                addRef();
                *obj = cast(void*)( cast(initer)(this) );
                return kResultOk;
            }
        }
        *obj = null;
        return kNoInterface;
    }
}

// speical case, when asking for a IUnknown return a richer interface
mixin template QUERY_INTERFACE_SPECIAL_CASE_IUNKNOWN(Interfaces...)// interfaces)
{
    override tresult queryInterface (ref const TUID _iid, void** obj)
    {
        foreach(initer; Interfaces)
        {
            if (iidEqual (_iid, initer.iid.toTUID))
            {
                addRef();
                *obj = cast(void*)( cast(initer)(this) );
                return kResultOk;
            }
        }

        if (iidEqual (_iid, FUnknown_iid))
        {
            addRef();
            *obj = cast(void*)( cast(Interfaces[0])(this) );
            return kResultOk;
        }

        *obj = null;
        return kNoInterface;
    }
}


/+
//------------------------------------------------------------------------
#define IMPLEMENT_QUERYINTERFACE(ClassName, InterfaceName, ClassIID)                                \
::Steinberg::tresult PLUGIN_API ClassName::queryInterface (const ::Steinberg::TUID _iid, void** obj)\
{                                                                                                   \
    QUERY_INTERFACE (_iid, obj, ::Steinberg::FUnknown::iid, InterfaceName)                          \
    QUERY_INTERFACE (_iid, obj, ClassIID, InterfaceName)                                            \
    *obj = nullptr;                                                                                 \
    return ::Steinberg::kNoInterface;                                                               \
}

//------------------------------------------------------------------------
#define IMPLEMENT_FUNKNOWN_METHODS(ClassName,InterfaceName,ClassIID) \
    IMPLEMENT_REFCOUNT (ClassName)                                   \
    IMPLEMENT_QUERYINTERFACE (ClassName, InterfaceName, ClassIID)

//------------------------------------------------------------------------
//  Result Codes
//------------------------------------------------------------------------
+/

static if (COM_COMPATIBLE)
{
    version(Windows)
    {
        enum : tresult
        {
            kNoInterface        = cast(tresult)(0x80004002L),   // E_NOINTERFACE
            kResultOk           = cast(tresult)(0x00000000L),   // S_OK
            kResultTrue         = kResultOk,
            kResultFalse        = cast(tresult)(0x00000001L),   // S_FALSE
            kInvalidArgument    = cast(tresult)(0x80070057L),   // E_INVALIDARG
            kNotImplemented     = cast(tresult)(0x80004001L),   // E_NOTIMPL
            kInternalError      = cast(tresult)(0x80004005L),   // E_FAIL
            kNotInitialized     = cast(tresult)(0x8000FFFFL),   // E_UNEXPECTED
            kOutOfMemory        = cast(tresult)(0x8007000EL)        // E_OUTOFMEMORY
        }
    }
    else
    {
        enum : tresult
        {
            kNoInterface        = cast(tresult)(0x80000004L),   // E_NOINTERFACE
            kResultOk           = cast(tresult)(0x00000000L),   // S_OK
            kResultTrue         = kResultOk,
            kResultFalse        = cast(tresult)(0x00000001L),   // S_FALSE
            kInvalidArgument    = cast(tresult)(0x80000003L),   // E_INVALIDARG
            kNotImplemented     = cast(tresult)(0x80000001L),   // E_NOTIMPL
            kInternalError      = cast(tresult)(0x80000008L),   // E_FAIL
            kNotInitialized     = cast(tresult)(0x8000FFFFL),   // E_UNEXPECTED
            kOutOfMemory        = cast(tresult)(0x80000002L)        // E_OUTOFMEMORY
        }
    }
}
else
{
    enum : tresult
    {
        kNoInterface = -1,
        kResultOk,
        kResultTrue = kResultOk,
        kResultFalse,
        kInvalidArgument,
        kNotImplemented,
        kInternalError,
        kNotInitialized,
        kOutOfMemory
    }
}

//------------------------------------------------------------------------
alias LARGE_INT = int64 ; // obsolete


//------------------------------------------------------------------------
//  FUID class declaration
//------------------------------------------------------------------------
alias TUID = byte[16]; ///< plain UID type

//------------------------------------------------------------------------
/* FUnknown private */


public bool iidEqual (const(TUID) iid1, const(TUID) iid2) pure
{
    return iid1 == iid2;
}

//int32 PLUGIN_API atomicAdd (int32& value, int32 amount);

//------------------------------------------------------------------------
/** Handling 16 Byte Globally Unique Identifiers.
\ingroup pluginBase

Each interface declares its identifier as static member inside the interface
namespace (e.g. FUnknown::iid).
*/
//------------------------------------------------------------------------

struct FUID
{
public:
nothrow:
@nogc:

    this(TUID iid)
    {
        data = iid;
    }

    this(FUID other)
    {
        data[] = other.data[];
    }

    this(uint32 l1, uint32 l2, uint32 l3, uint32 l4)
    {
        from4Int(l1, l2, l3, l4);
    }

    // Note: C++ destructor was virtual but as it's only declared as static member I doubt it need polymorphism
    ~this()
    {
    }

    /** Generates a new Unique Identifier (UID).
        Will return true for success. If the return value is false, either no
        UID is generated or the UID is not guaranteed to be unique worldwide. */
    deprecated bool generate()
    {
        assert(false); //TODO
      
        /*
        bool FUID::generate ()
        {
            #if SMTG_OS_WINDOWS
            #if defined(_M_ARM64) || defined(_M_ARM)
            //#warning implement me!
            return false;
            #else
            GUID guid;
            HRESULT hr = CoCreateGuid (&guid);
            switch (hr)
            {
                case RPC_S_OK: memcpy (data, (char*)&guid, sizeof (TUID)); return true;

                case RPC_S_UUID_LOCAL_ONLY:
                default: return false;
            }
            #endif

            #elif SMTG_OS_MACOS
            CFUUIDRef uuid = CFUUIDCreate (kCFAllocatorDefault);
            if (uuid)
            {
                CFUUIDBytes bytes = CFUUIDGetUUIDBytes (uuid);
                memcpy (data, (char*)&bytes, sizeof (TUID));
                CFRelease (uuid);
                return true;
            }
            return false;

            #else
            #warning implement me!
            return false;
            #endif
        }
        */
    }

    /** Checks if the UID data is valid.
        The default constructor initializes the memory with zeros. */
    bool isValid () pure const
    {
        return data != data.init;
    }

    bool opEquals(ref const(FUID) other) pure const 
    { 
        return data == other.data;
    }

    //bool operator < (const FUID& f) const { return memcmp (data, f.data, sizeof (TUID)) < 0; }

    uint32 getLong1 () pure const
    {
        static if (COM_COMPATIBLE)
            return makeLong (data[3], data[2], data[1], data[0]);
        else
            return makeLong (data[0], data[1], data[2], data[3]);
    }

    uint32 getLong2 () pure const
    {
        static if (COM_COMPATIBLE)
            return makeLong (data[5], data[4], data[7], data[6]);
        else
            return makeLong (data[4], data[5], data[6], data[7]);
    }

    uint32 getLong3 () pure const
    {
        return makeLong (data[8], data[9], data[10], data[11]);
    }

    uint32 getLong4 () pure const
    {
        return makeLong (data[12], data[13], data[14], data[15]);
    }

    void from4Int (uint32 l1, uint32 l2, uint32 l3, uint32 l4) pure
    {
        static if (COM_COMPATIBLE)
        {
            data [0]  = cast(byte)((l1 & 0x000000FF)      );
            data [1]  = cast(byte)((l1 & 0x0000FF00) >>  8);
            data [2]  = cast(byte)((l1 & 0x00FF0000) >> 16);
            data [3]  = cast(byte)((l1 & 0xFF000000) >> 24);
            data [4]  = cast(byte)((l2 & 0x00FF0000) >> 16);
            data [5]  = cast(byte)((l2 & 0xFF000000) >> 24);
            data [6]  = cast(byte)((l2 & 0x000000FF)      );
            data [7]  = cast(byte)((l2 & 0x0000FF00) >>  8);
            data [8]  = cast(byte)((l3 & 0xFF000000) >> 24);
            data [9]  = cast(byte)((l3 & 0x00FF0000) >> 16);
            data [10] = cast(byte)((l3 & 0x0000FF00) >>  8);
            data [11] = cast(byte)((l3 & 0x000000FF)      );
            data [12] = cast(byte)((l4 & 0xFF000000) >> 24);
            data [13] = cast(byte)((l4 & 0x00FF0000) >> 16);
            data [14] = cast(byte)((l4 & 0x0000FF00) >>  8);
            data [15] = cast(byte)((l4 & 0x000000FF)      );
        }
        else
        {
            data [0]  = cast(byte)((l1 & 0xFF000000) >> 24);
            data [1]  = cast(byte)((l1 & 0x00FF0000) >> 16);
            data [2]  = cast(byte)((l1 & 0x0000FF00) >>  8);
            data [3]  = cast(byte)((l1 & 0x000000FF)      );
            data [4]  = cast(byte)((l2 & 0xFF000000) >> 24);
            data [5]  = cast(byte)((l2 & 0x00FF0000) >> 16);
            data [6]  = cast(byte)((l2 & 0x0000FF00) >>  8);
            data [7]  = cast(byte)((l2 & 0x000000FF)      );
            data [8]  = cast(byte)((l3 & 0xFF000000) >> 24);
            data [9]  = cast(byte)((l3 & 0x00FF0000) >> 16);
            data [10] = cast(byte)((l3 & 0x0000FF00) >>  8);
            data [11] = cast(byte)((l3 & 0x000000FF)      );
            data [12] = cast(byte)((l4 & 0xFF000000) >> 24);
            data [13] = cast(byte)((l4 & 0x00FF0000) >> 16);
            data [14] = cast(byte)((l4 & 0x0000FF00) >>  8);
            data [15] = cast(byte)((l4 & 0x000000FF)      );
        }
    }

    void to4Int (ref uint32 d1, ref uint32 d2, ref uint32 d3, ref uint32 d4) pure const
    {
        d1 = getLong1 ();
        d2 = getLong2 ();
        d3 = getLong3 ();
        d4 = getLong4 ();
    }
/+
    typedef char8 String[64];

    /** Converts UID to a string.
        The string will be 32 characters long, representing the hexadecimal values
        of each data byte (e.g. "9127BE30160E4BB69966670AA6087880"). 
        
        Typical use-case is:
        \code
        char8[33] strUID = {0};
        FUID uid;
        if (uid.generate ())
            uid.toString (strUID);
        \endcode
        */
    void toString (char8* string) const;

    /** Sets the UID data from a string.
        The string has to be 32 characters long, where each character-pair is
        the ASCII-encoded hexadecimal value of the corresponding data byte. */
    bool fromString (const char8* string);

    /** Converts UID to a string in Microsoft® OLE format.
    (e.g. "{c200e360-38c5-11ce-ae62-08002b2b79ef}") */
    void toRegistryString (char8* string) const;

    /** Sets the UID data from a string in Microsoft® OLE format. */
    bool fromRegistryString (const char8* string);

    enum UIDPrintStyle
    {
        kINLINE_UID,  ///< "INLINE_UID (0x00000000, 0x00000000, 0x00000000, 0x00000000)"
        kDECLARE_UID, ///< "DECLARE_UID (0x00000000, 0x00000000, 0x00000000, 0x00000000)"
        kFUID,        ///< "FUID (0x00000000, 0x00000000, 0x00000000, 0x00000000)"
        kCLASS_UID    ///< "DECLARE_CLASS_IID (Interface, 0x00000000, 0x00000000, 0x00000000, 0x00000000)"
    };
    /** Prints the UID to a string (or debug output if string is NULL).
        \param string is the output string if not NULL.
        \param style can be chosen from the FUID::UIDPrintStyle enumeration. */
    void print (char8* string = 0, int32 style = kINLINE_UID) const;+/

  
    void toTUID(ref TUID result) const 
    { 
        result = data;
    }    

    ref const(TUID) toTUID() const 
    { 
        return data; 
    }

    static FUID fromTUID ( const(TUID)* uid)
    {
        FUID res;
        if (uid)
            res.data = *uid;
        return res;
    }

private:
    TUID data = [0, 0, 0, 0, 
                 0, 0, 0, 0, 
                 0, 0, 0, 0, 
                 0, 0, 0, 0];

    //------------------------------------------------------------------------
    //  helpers
    //------------------------------------------------------------------------
    static uint makeLong (ubyte b1, ubyte b2, ubyte b3, ubyte b4) pure
    {
        return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
    }
}

static assert(TUID.sizeof == FUID.sizeof);


interface IUnknown 
{
@nogc:
nothrow:
    tresult queryInterface(ref const(TUID) _iid, void** obj);
    uint addRef();
    uint release();
}


//------------------------------------------------------------------------
interface FUnknown : IUnknown
{
public:
    __gshared immutable FUID iid = FUID(FUnknown_iid); // TODO: why both?
}

static immutable TUID FUnknown_iid = INLINE_UID(0x00000000, 0x00000000, 0xC0000000, 0x00000046);

/+
//------------------------------------------------------------------------
// FUnknownPtr
//------------------------------------------------------------------------
/** FUnknownPtr - automatic interface conversion and smart pointer in one.
    This template class can be used for interface conversion like this:
 \code
    IPtr<IPath> path = owned (FHostCreate (IPath, hostClasses));
    FUnknownPtr<IPath2> path2 (path); // does a query interface for IPath2
    if (path2)
        ...
 \endcode
*/
//------------------------------------------------------------------------
template <class I>
class FUnknownPtr : public IPtr<I>
{
public:
//------------------------------------------------------------------------
    inline FUnknownPtr (FUnknown* unknown); // query interface
    inline FUnknownPtr (const FUnknownPtr& p) : IPtr<I> (p) {}
    inline FUnknownPtr () {}

    inline FUnknownPtr& operator= (const FUnknownPtr& p)
    {
        IPtr<I>::operator= (p);
        return *this;
    }
    inline I* operator= (FUnknown* unknown);
    inline I* getInterface () { return this->ptr; }
};

//------------------------------------------------------------------------
template <class I>
inline FUnknownPtr<I>::FUnknownPtr (FUnknown* unknown)
{
    if (unknown && unknown->queryInterface (I::iid, (void**)&this->ptr) != kResultOk)
        this->ptr = 0;
}

//------------------------------------------------------------------------
template <class I>
inline I* FUnknownPtr<I>::operator= (FUnknown* unknown)
{
    I* newPtr = 0;
    if (unknown && unknown->queryInterface (I::iid, (void**)&newPtr) == kResultOk)
    {
        OPtr<I> rel (newPtr);
        return IPtr<I>::operator= (newPtr);
    }

    return IPtr<I>::operator= (0);
}




//-----------------------------------------------------------------------------
// Project     : SDK Core
//
// Category    : SDK Core Interfaces
// Filename    : pluginterfaces/base/funknown.cpp
// Created by  : Steinberg, 01/2004
// Description : Basic Interface
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------

#include "funknown.h"

#include "fstrdefs.h"

#include <stdio.h>

#if SMTG_OS_WINDOWS
#include <objbase.h>
#endif

#if SMTG_OS_MACOS
#include <CoreFoundation/CoreFoundation.h>
#include <libkern/OSAtomic.h>

#if defined(__GNUC__) && (__GNUC__ >= 4) && !__LP64__
// on 32 bit Mac OS X we can safely ignore the format warnings as sizeof(int) == sizeof(long)
#pragma GCC diagnostic ignored "-Wformat"
#endif

#endif

#if SMTG_OS_LINUX
#include <ext/atomicity.h>
#endif

namespace Steinberg {

//------------------------------------------------------------------------
#if COM_COMPATIBLE
#if SMTG_OS_WINDOWS
#define GuidStruct GUID
#else
struct GuidStruct
{
uint32 Data1;
uint16 Data2;
uint16 Data3;
uint8 Data4[8];
};
#endif
#endif

static void toString8 (char8* string, const char* data, int32 i1, int32 i2);
static void fromString8 (const char8* string, char* data, int32 i1, int32 i2);
static uint32 makeLong (uint8 b1, uint8 b2, uint8 b3, uint8 b4);

+/


int atomicAdd(ref shared(int) var, int32 d)
{
    import core.atomic;
    return atomicOp!"+="(var, d); // Note: return the new value
}

/+



//------------------------------------------------------------------------
FUID& FUID::operator= (const FUID& f)
{
memcpy (data, f.data, sizeof (TUID));
return *this;
}

//------------------------------------------------------------------------





//------------------------------------------------------------------------
void FUID::toString (char8* string) const
{
if (!string)
return;

#if COM_COMPATIBLE
GuidStruct* g = (GuidStruct*)data;

char8 s[17];
Steinberg::toString8 (s, data, 8, 16);

sprintf (string, "%08X%04X%04X%s", g->Data1, g->Data2, g->Data3, s);
#else
Steinberg::toString8 (string, data, 0, 16);
#endif
}

//------------------------------------------------------------------------
bool FUID::fromString (const char8* string)
{
if (!string || !*string)
return false;
if (strlen (string) != 32)
return false;

#if COM_COMPATIBLE
GuidStruct g;
char s[33];

strcpy (s, string);
s[8] = 0;
sscanf (s, "%x", &g.Data1);
strcpy (s, string + 8);
s[4] = 0;
sscanf (s, "%hx", &g.Data2);
strcpy (s, string + 12);
s[4] = 0;
sscanf (s, "%hx", &g.Data3);

memcpy (data, &g, 8);
Steinberg::fromString8 (string + 16, data, 8, 16);
#else
Steinberg::fromString8 (string, data, 0, 16);
#endif

return true;
}

//------------------------------------------------------------------------
bool FUID::fromRegistryString (const char8* string)
{
if (!string || !*string)
return false;
if (strlen (string) != 38)
return false;

// e.g. {c200e360-38c5-11ce-ae62-08002b2b79ef}

#if COM_COMPATIBLE
GuidStruct g;
char8 s[10];

strncpy (s, string + 1, 8);
s[8] = 0;
sscanf (s, "%x", &g.Data1);
strncpy (s, string + 10, 4);
s[4] = 0;
sscanf (s, "%hx", &g.Data2);
strncpy (s, string + 15, 4);
s[4] = 0;
sscanf (s, "%hx", &g.Data3);
memcpy (data, &g, 8);

Steinberg::fromString8 (string + 20, data, 8, 10);
Steinberg::fromString8 (string + 25, data, 10, 16);
#else
Steinberg::fromString8 (string + 1, data, 0, 4);
Steinberg::fromString8 (string + 10, data, 4, 6);
Steinberg::fromString8 (string + 15, data, 6, 8);
Steinberg::fromString8 (string + 20, data, 8, 10);
Steinberg::fromString8 (string + 25, data, 10, 16);
#endif

return true;
}

//------------------------------------------------------------------------
void FUID::toRegistryString (char8* string) const
{
// e.g. {c200e360-38c5-11ce-ae62-08002b2b79ef}

#if COM_COMPATIBLE
GuidStruct* g = (GuidStruct*)data;

char8 s1[5];
Steinberg::toString8 (s1, data, 8, 10);

char8 s2[13];
Steinberg::toString8 (s2, data, 10, 16);

sprintf (string, "{%08X-%04X-%04X-%s-%s}", g->Data1, g->Data2, g->Data3, s1, s2);
#else
char8 s1[9];
Steinberg::toString8 (s1, data, 0, 4);
char8 s2[5];
Steinberg::toString8 (s2, data, 4, 6);
char8 s3[5];
Steinberg::toString8 (s3, data, 6, 8);
char8 s4[5];
Steinberg::toString8 (s4, data, 8, 10);
char8 s5[13];
Steinberg::toString8 (s5, data, 10, 16);

sprintf (string, "{%s-%s-%s-%s-%s}", s1, s2, s3, s4, s5);
#endif
}

//------------------------------------------------------------------------
void FUID::print (char8* string, int32 style) const
{
if (!string) // no string: debug output
{
char8 str[128];
print (str, style);

#if SMTG_OS_WINDOWS
OutputDebugStringA (str);
OutputDebugStringA ("\n");
#else
fprintf (stdout, "%s\n", str);
#endif
return;
}

uint32 l1, l2, l3, l4;
to4Int (l1, l2, l3, l4);

switch (style)
{
case kINLINE_UID:
sprintf (string, "INLINE_UID (0x%08X, 0x%08X, 0x%08X, 0x%08X)", l1, l2, l3, l4);
break;

case kDECLARE_UID:
sprintf (string, "DECLARE_UID (0x%08X, 0x%08X, 0x%08X, 0x%08X)", l1, l2, l3, l4);
break;

case kFUID:
sprintf (string, "FUID (0x%08X, 0x%08X, 0x%08X, 0x%08X)", l1, l2, l3, l4);
break;

case kCLASS_UID:
default:
sprintf (string, "DECLARE_CLASS_IID (Interface, 0x%08X, 0x%08X, 0x%08X, 0x%08X)", l1,
l2, l3, l4);
break;
}
}



//------------------------------------------------------------------------
static void toString8 (char8* string, const char* data, int32 i1, int32 i2)
{
*string = 0;
for (int32 i = i1; i < i2; i++)
{
char8 s[3];
sprintf (s, "%02X", (uint8)data[i]);
strcat (string, s);
}
}

//------------------------------------------------------------------------
static void fromString8 (const char8* string, char* data, int32 i1, int32 i2)
{
for (int32 i = i1; i < i2; i++)
{
char8 s[3];
s[0] = *string++;
s[1] = *string++;
s[2] = 0;

int32 d = 0;
sscanf (s, "%2x", &d);
data[i] = (char)d;
}
}

//------------------------------------------------------------------------
} // namespace Steinberg

+/