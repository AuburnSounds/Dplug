//------------------------------------------------------------------------
// Project     : SDK Base
// Version     : 1.0
//
// Category    : Helpers
// Filename    : base/source/fobject.h and base/source/fobject.cpp
// Created by  : Steinberg, 2008
// Description : Basic Object implementing FUnknown
//
//-----------------------------------------------------------------------------
// LICENSE
// (c) 2018, Steinberg Media Technologies GmbH, All Rights Reserved
//-----------------------------------------------------------------------------
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
//   * Redistributions of source code must retain the above copyright notice, 
//     this list of conditions and the following disclaimer.
//   * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation 
//     and/or other materials provided with the distribution.
//   * Neither the name of the Steinberg Media Technologies nor the names of its
//     contributors may be used to endorse or promote products derived from this 
//     software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
// IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
// INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
// BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE  OF THIS SOFTWARE, EVEN IF ADVISED
// OF THE POSSIBILITY OF SUCH DAMAGE.
module dplug.vst3.fobject;

import core.stdc.string;

import dplug.core.nogc;

import dplug.vst3.ftypes;
import dplug.vst3.funknown;
import dplug.vst3.iupdatehandler;

alias FClassID = FIDString;

//------------------------------------------------------------------------
// Basic FObject - implements FUnknown + IDependent
//------------------------------------------------------------------------
/** Implements FUnknown and IDependent.

FObject is a polymorphic class that implements IDependent (of SKI module)
and therefore derived from FUnknown, which is the most abstract base class of all. 

All COM-like virtual methods of FUnknown such as queryInterface(), addRef(), release()
are implemented here. On top of that, dependency-related methods are implemented too.

Pointer casting is done via the template methods FCast, either FObject to FObject or
FUnknown to FObject.

FObject supports a new singleton concept, therefore these objects are deleted automatically upon program termination.

- Runtime type information: An object can be queried at runtime, of what class
it is. To do this correctly, every class must override some methods. This
is simplified by using the OBJ_METHODS macros


@see 
    - FUnknown
    - IDependent
    - IUpdateHandler
*/
//------------------------------------------------------------------------
class FObject : IDependent
{
public:
nothrow:
@nogc:

    ///< default constructor...
    this()
    {
    }

    this(ref const(FObject) other)
    {
    }

//    FObject& operator = (const FObject&) { return *this; }                  ///< overloads operator "=" as the reference assignment

    // OBJECT_METHODS
    static FClassID getFClassID () 
    {
        return "FObject".ptr;
    }           

    FClassID isA () const 
    {
        return getFClassID ();
    }

    ///< a local alternative to getFClassID ()
    bool isA (FClassID s) const 
    {
        return isTypeOf (s, false); ///< evaluates if the passed ID is of the FObject type
    }       

    bool isTypeOf (FClassID s, bool askBaseClass = true) const
    {
        return classIDsEqual (s, getFClassID ());
    }
                                                                            ///< evaluates if the passed ID is of the FObject type
    final int getRefCount() ///< returns the current interface reference count
    {
        return refCount;
    }       

    final FUnknown unknownCast () ///< get FUnknown interface from object
    {
        return this;
    }                                 

    // FUnknown
    mixin QUERY_INTERFACE!(FUnknown, IDependent, FObject);
    
    override uint addRef ()
    {
        return atomicAdd(refCount, 1);
    }

    override uint release () 
    {
        if (atomicAdd (refCount, -1) == 0)
        {
            refCount = -1000;
            destroyFree(this);
            return 0;
        }                                   
        return refCount;   
    }

    // IDependent
    ///< empty virtual method that should be overridden by derived classes for data updates upon changes    
    override void update (FUnknown changedUnknown, int32 message)
    {
    }
                                                                            
    // IDependency
    void addDependent (IDependent dep)                            ///< adds dependency to the object
    {
        if (gUpdateHandler)
            gUpdateHandler.addDependent (unknownCast (), dep);
    }

    void removeDependent (IDependent dep)                         ///< removes dependency from the object
    {
        if (gUpdateHandler)
            gUpdateHandler.removeDependent (unknownCast (), dep);
    }

    void changed (int32 msg = kChanged)                            ///< Inform all dependents, that the object has changed.
    {
        if (gUpdateHandler)
            gUpdateHandler.triggerUpdates (unknownCast (), msg);
        else
            updateDone(msg);
    }

    void deferUpdate (int32 msg = kChanged)                        ///< Similar to triggerUpdates, except only delivered in idle (usefull in collecting updates).
    {
        if (gUpdateHandler)
            gUpdateHandler.deferUpdates (unknownCast (), msg);
        else
            updateDone (msg);
    }

    void updateDone (int32 msg)                                            ///< empty virtual method that should be overridden by derived classes
    {
    }

    bool isEqualInstance (FUnknown d) 
    {
        return this is d;
    }
    
    static void setUpdateHandler (IUpdateHandler handler)  ///< set method for the local attribute
    {
        gUpdateHandler = handler;
    }

    static IUpdateHandler getUpdateHandler ()  ///< get method for the local attribute 
    {
        return gUpdateHandler;
    }                 

    // static helper functions
    static bool classIDsEqual (FClassID ci1, FClassID ci2)
    {
        return (ci1 && ci2) ? (strcmp (ci1, ci2) == 0) : false;
    }

    static FObject unknownToObject (FUnknown unknown)            ///< pointer conversion from FUnknown to FObject
    {
        FObject object = null;
        if (unknown) 
        {
            unknown.queryInterface(iid, cast(void**)&object);
            if (object)
                object.release (); // queryInterface has added ref     
        }
        return object;
    }

    /** Special UID that is used to cast an FUnknown pointer to a FObject */
    //static const FUID iid;

//------------------------------------------------------------------------
protected:
    shared(int) refCount = 1;                                                         ///< COM-model local reference count

    __gshared IUpdateHandler gUpdateHandler;
}

/+

//-----------------------------------------------------------------------
/** FCast overload 1 - FObject to FObject */
//-----------------------------------------------------------------------
template <class C>
inline C* FCast (const FObject* object)
{
    if (object && object->isTypeOf (C::getFClassID (), true))
        return (C*) object;
    return 0;
}

//-----------------------------------------------------------------------
/** FCast overload 2 - FUnknown to FObject */
//-----------------------------------------------------------------------
template <class C>
inline C* FCast (FUnknown* unknown)
{
    FObject* object = FObject::unknownToObject (unknown);
    return FCast<C> (object);
}

//-----------------------------------------------------------------------
/** FUCast - casting from FUnknown to Interface */
//-----------------------------------------------------------------------
template <class C>
inline C* FUCast (FObject* object)
{
    return FUnknownPtr<C> (object ? object->unknownCast () : 0);
}

template <class C>
inline C* FUCast (FUnknown* object)
{
    return FUnknownPtr<C> (object);
}

//------------------------------------------------------------------------
/** @name Convenience methods that call release or delete respectively
    on a pointer if it is non-zero, and then set the pointer to zero.
    Note: you should prefer using IPtr or OPtr instead of these methods
    whenever possible. 
    <b>Examples:</b>
    @code
    ~Foo ()
    {
        // instead of ...
        if (somePointer)
        {
            somePointer->release ();
            somePointer = 0;
        }
        // ... just being lazy I write
        SafeRelease (somePointer)
    }
    @endcode
*/
///@{
//-----------------------------------------------------------------------
template <class I>
inline void SafeRelease (I *& ptr) 
{ 
    if (ptr) 
    {
        ptr->release (); 
        ptr = 0;
    }
}

//-----------------------------------------------------------------------
template <class I>
inline void SafeRelease (IPtr<I> & ptr) 
{ 
    ptr = 0;
}


//-----------------------------------------------------------------------
template <class T>
inline void SafeDelete (T *& ptr)
{
    if (ptr) 
    {
        delete ptr;
        ptr = 0;
    }
}
///@}

//-----------------------------------------------------------------------
template <class T>
inline void AssignShared (T*& dest, T* newPtr)
{
    if (dest == newPtr)
        return;
    
    if (dest) 
        dest->release (); 
    dest = newPtr; 
    if (dest) 
        dest->addRef ();
}

//-----------------------------------------------------------------------
template <class T>
inline void AssignSharedDependent (IDependent* _this, T*& dest, T* newPtr)
{
    if (dest == newPtr)
        return;

    if (dest)
        dest->removeDependent (_this);
    AssignShared (dest, newPtr);
    if (dest)
        dest->addDependent (_this);
}

//-----------------------------------------------------------------------
template <class T>
inline void AssignSharedDependent (IDependent* _this, IPtr<T>& dest, T* newPtr)
{
    if (dest == newPtr)
        return;

    if (dest)
        dest->removeDependent (_this);
    dest = newPtr;
    if (dest)
        dest->addDependent (_this);
}
    
//-----------------------------------------------------------------------
template <class T>
inline void SafeReleaseDependent (IDependent* _this, T*& dest)
{
    if (dest)
        dest->removeDependent (_this);
    SafeRelease (dest);
}
    
//-----------------------------------------------------------------------
template <class T>
inline void SafeReleaseDependent (IDependent* _this, IPtr<T>& dest)
{
    if (dest)
        dest->removeDependent (_this);
    SafeRelease (dest);
}


//------------------------------------------------------------------------
/** Automatic creation and destruction of singleton instances. */
namespace Singleton {
    /** registers an instance (type FObject) */
    void registerInstance (FObject** o);

    /** Returns true when singleton instances were already released. */
    bool isTerminated ();

    /** lock and unlock the singleton registration for multi-threading safety */
    void lockRegister ();
    void unlockRegister ();
}

//------------------------------------------------------------------------
} // namespace Steinberg

//-----------------------------------------------------------------------
#define SINGLETON(ClassName)    \
    static ClassName* instance (bool create = true) \
    { \
        static Steinberg::FObject* inst = nullptr; \
        if (inst == nullptr && create && Steinberg::Singleton::isTerminated () == false) \
        {   \
            Steinberg::Singleton::lockRegister (); \
            if (inst == nullptr) \
            { \
                inst = NEW ClassName; \
                Steinberg::Singleton::registerInstance (&inst); \
            } \
            Steinberg::Singleton::unlockRegister (); \
        }   \
        return (ClassName*)inst; \
    }

//-----------------------------------------------------------------------
#define OBJ_METHODS(className, baseClass)                               \
    static inline Steinberg::FClassID getFClassID () {return (#className);}     \
    virtual Steinberg::FClassID isA () const SMTG_OVERRIDE {return className::getFClassID ();}  \
    virtual bool isA (Steinberg::FClassID s) const SMTG_OVERRIDE {return isTypeOf (s, false);}  \
    virtual bool isTypeOf (Steinberg::FClassID s, bool askBaseClass = true) const SMTG_OVERRIDE \
    {  return (classIDsEqual (s, #className) ? true : (askBaseClass ? baseClass::isTypeOf (s, true) : false)); } 

//------------------------------------------------------------------------
/** Delegate refcount functions to BaseClass.
    BaseClase must implement ref counting. 
*/
//------------------------------------------------------------------------
#define REFCOUNT_METHODS(BaseClass) \
virtual Steinberg::uint32 PLUGIN_API addRef ()SMTG_OVERRIDE{ return BaseClass::addRef (); } \
virtual Steinberg::uint32 PLUGIN_API release ()SMTG_OVERRIDE{ return BaseClass::release (); }

//------------------------------------------------------------------------
/** @name Macros to implement FUnknown::queryInterface ().

    <b>Examples:</b>
    @code
    class Foo : public FObject, public IFoo2, public IFoo3 
    {
        ...
        DEFINE_INTERFACES
            DEF_INTERFACE (IFoo2)
            DEF_INTERFACE (IFoo3)
        END_DEFINE_INTERFACES (FObject)
        REFCOUNT_METHODS(FObject)
        // Implement IFoo2 interface ...
        // Implement IFoo3 interface ...
        ...
    };
    @endcode    
*/
///@{
//------------------------------------------------------------------------
/** Start defining interfaces. */
//------------------------------------------------------------------------
#define DEFINE_INTERFACES \
Steinberg::tresult PLUGIN_API queryInterface (const Steinberg::TUID iid, void** obj) SMTG_OVERRIDE \
{

//------------------------------------------------------------------------
/** Add a interfaces. */
//------------------------------------------------------------------------
#define DEF_INTERFACE(InterfaceName) \
    QUERY_INTERFACE (iid, obj, InterfaceName::iid, InterfaceName)

//------------------------------------------------------------------------
/** End defining interfaces. */
//------------------------------------------------------------------------
#define END_DEFINE_INTERFACES(BaseClass) \
    return BaseClass::queryInterface (iid, obj); \
}
///@}

//------------------------------------------------------------------------
/** @name Convenient macros to implement Steinberg::FUnknown::queryInterface ().
    <b>Examples:</b>
    @code
    class Foo : public FObject, public IFoo2, public IFoo3 
    {
        ...
        DEF_INTERFACES_2(IFoo2,IFoo3,FObject)
        REFCOUNT_METHODS(FObject)
        ...
    };
    @endcode
*/
///@{
//------------------------------------------------------------------------
#define DEF_INTERFACES_1(InterfaceName,BaseClass) \
DEFINE_INTERFACES \
DEF_INTERFACE (InterfaceName) \
END_DEFINE_INTERFACES (BaseClass)

//------------------------------------------------------------------------
#define DEF_INTERFACES_2(InterfaceName1,InterfaceName2,BaseClass) \
DEFINE_INTERFACES \
DEF_INTERFACE (InterfaceName1) \
DEF_INTERFACE (InterfaceName2) \
END_DEFINE_INTERFACES (BaseClass)

//------------------------------------------------------------------------
#define DEF_INTERFACES_3(InterfaceName1,InterfaceName2,InterfaceName3,BaseClass) \
DEFINE_INTERFACES \
DEF_INTERFACE (InterfaceName1) \
DEF_INTERFACE (InterfaceName2) \
DEF_INTERFACE (InterfaceName3) \
END_DEFINE_INTERFACES (BaseClass)

//------------------------------------------------------------------------
#define DEF_INTERFACES_4(InterfaceName1,InterfaceName2,InterfaceName3,InterfaceName4,BaseClass) \
    DEFINE_INTERFACES \
    DEF_INTERFACE (InterfaceName1) \
    DEF_INTERFACE (InterfaceName2) \
    DEF_INTERFACE (InterfaceName3) \
    DEF_INTERFACE (InterfaceName4) \
    END_DEFINE_INTERFACES (BaseClass)
///@}

//------------------------------------------------------------------------
/** @name Convenient macros to implement Steinberg::FUnknown methods.
    <b>Examples:</b>
    @code
    class Foo : public FObject, public IFoo2, public IFoo3 
    {
        ...
        FUNKNOWN_METHODS2(IFoo2,IFoo3,FObject)
        ...
    };
    @endcode
*/
///@{
#define FUNKNOWN_METHODS(InterfaceName,BaseClass) \
DEF_INTERFACES_1(InterfaceName,BaseClass) \
REFCOUNT_METHODS(BaseClass)

#define FUNKNOWN_METHODS2(InterfaceName1,InterfaceName2,BaseClass) \
DEF_INTERFACES_2(InterfaceName1,InterfaceName2,BaseClass) \
REFCOUNT_METHODS(BaseClass)

#define FUNKNOWN_METHODS3(InterfaceName1,InterfaceName2,InterfaceName3,BaseClass) \
DEF_INTERFACES_3(InterfaceName1,InterfaceName2,InterfaceName3,BaseClass) \
REFCOUNT_METHODS(BaseClass)

#define FUNKNOWN_METHODS4(InterfaceName1,InterfaceName2,InterfaceName3,InterfaceName4,BaseClass) \
DEF_INTERFACES_4(InterfaceName1,InterfaceName2,InterfaceName3,InterfaceName4,BaseClass) \
REFCOUNT_METHODS(BaseClass)
///@}


//------------------------------------------------------------------------
//------------------------------------------------------------------------
#if COM_COMPATIBLE
//------------------------------------------------------------------------
/** @name Macros to implement IUnknown interfaces with FObject.
    <b>Examples:</b>
    @code
    class MyEnumFormat : public FObject, IEnumFORMATETC
    {
        ...
        COM_UNKNOWN_METHODS (IEnumFORMATETC, IUnknown)
        ...
    };
    @endcode
*/
///@{
//------------------------------------------------------------------------
#define IUNKNOWN_REFCOUNT_METHODS(BaseClass) \
STDMETHOD_ (ULONG, AddRef) (void) {return BaseClass::addRef ();} \
STDMETHOD_ (ULONG, Release) (void) {return BaseClass::release ();}

//------------------------------------------------------------------------
#define COM_QUERY_INTERFACE(iid, obj, InterfaceName)     \
if (riid == __uuidof(InterfaceName))                     \
{                                                        \
    addRef ();                                           \
    *obj = (InterfaceName*)this;                         \
    return kResultOk;                                    \
}

//------------------------------------------------------------------------
#define COM_OBJECT_QUERY_INTERFACE(InterfaceName,BaseClass)        \
STDMETHOD (QueryInterface) (REFIID riid, void** object)            \
{                                                                  \
    COM_QUERY_INTERFACE (riid, object, InterfaceName)              \
    return BaseClass::queryInterface ((FIDString)&riid, object);   \
}

//------------------------------------------------------------------------
#define COM_UNKNOWN_METHODS(InterfaceName,BaseClass) \
COM_OBJECT_QUERY_INTERFACE(InterfaceName,BaseClass) \
IUNKNOWN_REFCOUNT_METHODS(BaseClass)
///@}

#endif // COM_COMPATIBLE




#include "base/source/fobject.h"
#include "base/thread/include/flock.h"

#include <vector>

namespace Steinberg {

IUpdateHandler* FObject::gUpdateHandler = 0;

//------------------------------------------------------------------------
const FUID FObject::iid;

//------------------------------------------------------------------------
struct FObjectIIDInitializer
{
    // the object iid is always generated so that different components
    // only can cast to their own objects
    // this initializer must be after the definition of FObject::iid, otherwise
    //  the default constructor of FUID will clear the generated iid
    FObjectIIDInitializer () 
    { 
        const_cast<FUID&> (FObject::iid).generate (); 
    }
} gFObjectIidInitializer;
+/

/+
//------------------------------------------------------------------------
/** Automatic creation and destruction of singleton instances. */
//------------------------------------------------------------------------
namespace Singleton 
{
    typedef std::vector<FObject**> ObjectVector;
    ObjectVector* singletonInstances = 0;
    bool singletonsTerminated = false;
    Steinberg::Base::Thread::FLock* singletonsLock;

    bool isTerminated () {return singletonsTerminated;}

    void lockRegister ()
    {
        if (!singletonsLock) // assume first call not from multiple threads
            singletonsLock = NEW Steinberg::Base::Thread::FLock;
        singletonsLock->lock ();
    }
    void unlockRegister () 
    { 
        singletonsLock->unlock ();
    }

    void registerInstance (FObject** o)
    {
        SMTG_ASSERT (singletonsTerminated == false)
        if (singletonsTerminated == false)
        {
            if (singletonInstances == 0)
                singletonInstances = NEW std::vector<FObject**>;
            singletonInstances->push_back (o);
        }
    }

    struct Deleter
    {
        ~Deleter ()
        {
            singletonsTerminated = true;
            if (singletonInstances)
            {
                for (ObjectVector::iterator it = singletonInstances->begin (),
                                            end = singletonInstances->end ();
                     it != end; ++it)
                {
                    FObject** obj = (*it);
                    (*obj)->release ();
                    *obj = 0;
                    obj = 0;
                }

                delete singletonInstances;
                singletonInstances = 0;
            }
            delete singletonsLock;
            singletonsLock = 0;
        }
    } deleter;
}

//------------------------------------------------------------------------
} // namespace Steinberg
+/