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
            if (iidEqual (_iid, initer.iid))
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
            if (iidEqual (_iid, initer.iid))
            {
                addRef();
                *obj = cast(void*)( cast(initer)(this) );
                return kResultOk;
            }
        }

        if (iidEqual (_iid, FUnknown.iid))
        {
            addRef();
            *obj = cast(void*)( cast(Interfaces[0])(this) );
            return kResultOk;
        }

        *obj = null;
        return kNoInterface;
    }
}


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

alias LARGE_INT = int64 ; // obsolete

alias TUID = byte[16]; ///< plain UID type

public bool iidEqual (const(TUID) iid1, const(TUID) iid2) pure
{
    return iid1 == iid2;
}

interface IUnknown 
{
public:
@nogc:
nothrow:
    tresult queryInterface(ref const(TUID) _iid, void** obj);
    uint addRef();
    uint release();
}

interface FUnknown : IUnknown
{

    __gshared immutable TUID iid = INLINE_UID(0x00000000, 0x00000000, 0xC0000000, 0x00000046);
}

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
+/


int atomicAdd(ref shared(int) var, int32 d)
{
    import core.atomic;
    return atomicOp!"+="(var, d); // Note: return the new value
}
