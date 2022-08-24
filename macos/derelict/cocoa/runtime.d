/**
Objective-C runtime trickery for interfacing.

Copyright: Guillaume Piolat 2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)    

Unknown licence from:

Initial Version: Darrell Walisser <dwaliss1@purdue.edu>
Non-NIB-Code & other changes: Max Horn <max@quendi.de>
Port to the D programming language: Jacob Carlborg <jacob.carlborg@gmail.com>
Resurrected by: Guillaume Piolat <contact@auburnsounds.com> for the purpose of audio plug-ins

It just says "Feel free to customize this file for your purpose"

TODO ask original authors of the runtime trickery for a licence
*/
module derelict.cocoa.runtime;


/// Important reading: The "OS X ABI Function Call Guide"
/// https://developer.apple.com/library/mac/documentation/DeveloperTools/Conceptual/LowLevelABI/

import core.stdc.config;
import core.atomic;

import std.string;

import dplug.core.nogc;


version(X86)
    version = AnyX86;
version(X86_64)
    version = AnyX86;

//version = useTLS;

// NSGeometry.h

alias NSInteger = ptrdiff_t;
alias NSUInteger = size_t;

static if ((void*).sizeof > int.sizeof) // 64bit
    alias CGFloat = double;
else
    alias CGFloat = float;

struct NSPoint
{
    CGFloat x;
    CGFloat y;
}

struct NSRange
{
    NSUInteger location;
    NSUInteger length;
}

struct NSRect
{
    NSPoint origin;
    NSSize size;
}

NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) nothrow @nogc
{
    return NSRect(NSPoint(x, y), NSSize(w, h));
}

struct NSSize
{
    CGFloat width;
    CGFloat height;
}

alias SEL = char*;
alias Class = objc_class*;
alias id = objc_object*;


alias BOOL = char;
enum : BOOL
{
    NO = 0,
    YES = 1
}

alias Ivar = objc_ivar*;
alias Method = objc_method*;
alias Protocol = objc_object;



alias IMP = extern (C) id function(id, SEL, ...);

struct objc_object
{
    Class isa;
}

struct objc_super
{
    id receiver;
    Class clazz;
}

struct objc_class
{
    Class isa;
    Class super_class;
    const char* name;
    c_long versionn;
    c_long info;
    c_long instance_size;
    objc_ivar_list* ivars;
    objc_method_list** methodLists;
    objc_cache* cache;
    objc_protocol_list* protocols;
}

alias objc_property_t = void*;

struct objc_ivar
{
    char* ivar_name;
    char* ivar_type;
    int ivar_offset;

    version (X86_64)
        int space;
}

struct objc_ivar_list
{
    int ivar_count;

    version (X86_64)
        int space;

    /* variable length structure */
    objc_ivar[1] ivar_list;
}

struct objc_method
{
    SEL method_name;
    char* method_types;
    IMP method_imp;
}

struct objc_method_list
{
    objc_method_list* obsolete;

    int method_count;

    version (X86_64)
        int space;

    /* variable length structure */
    objc_method[1] method_list;
}

struct objc_cache
{
    uint mask /* total = mask + 1 */;
    uint occupied;
    Method[1] buckets;
}

struct objc_protocol_list
{
    objc_protocol_list* next;
    long count;
    Protocol*[1] list;
}

//Objective-C runtime bindings from the Cocoa framework
extern (C) nothrow @nogc
{
    alias Class function (Class superclass) pfobjc_registerClassPair;

    alias bool function (Class cls, const(char)* name, size_t size, byte alignment, const(char)* types) pfclass_addIvar;
    alias bool function (Class cls, const(SEL) name, IMP imp, const(char)* types) pfclass_addMethod;
    alias Class function (Class superclass, const(char)* name, size_t extraBytes) pfobjc_allocateClassPair;
    alias void function(Class cls) pfobjc_disposeClassPair;
    alias id function (const(char)* name) pfobjc_getClass;
    alias id function (const(char)* name) pfobjc_lookUpClass;

    alias id function (id theReceiver, SEL theSelector, ...) pfobjc_msgSend;
    alias id function (objc_super* superr, SEL op, ...) pfobjc_msgSendSuper;

    version (AnyX86)
        alias void function (void* stretAddr, id theReceiver, SEL theSelector, ...) pfobjc_msgSend_stret;

    alias const(char)* function (id obj) pfobject_getClassName;
    alias Ivar function (id obj, const(char)* name, void** outValue) pfobject_getInstanceVariable;
    alias Ivar function (id obj, const(char)* name, void* value) pfobject_setInstanceVariable;
    alias SEL function (const(char)* str) pfsel_registerName;
    version (X86)
        alias double function (id self, SEL op, ...) pfobjc_msgSend_fpret;

    alias Method function (Class aClass, const(SEL) aSelector) pfclass_getInstanceMethod;
    alias IMP function (Method method, IMP imp) pfmethod_setImplementation;


    // like pfobjc_msgSend except for returning NSPoint
    alias NSPoint function (id theReceiver, const(SEL) theSelector, ...) pfobjc_msgSend_NSPointret;


    alias pfobjc_getProtocol = Protocol* function (const(char)* name);
    alias pfclass_addProtocol = BOOL function (Class cls, Protocol* protocol);
    alias pfobjc_allocateProtocol = Protocol* function(const(char)* name);
    alias pfobjc_registerProtocol = void function(Protocol *proto);
    alias pfclass_conformsToProtocol = BOOL function(Class cls, Protocol *protocol);

    alias pfprotocol_addMethodDescription = void function(Protocol *proto, SEL name, const char *types, BOOL isRequiredMethod, BOOL isInstanceMethod);
}

__gshared
{
    pfobjc_registerClassPair objc_registerClassPair;

    pfclass_addIvar varclass_addIvar;
    pfclass_addMethod varclass_addMethod;
    pfobjc_allocateClassPair varobjc_allocateClassPair;
    pfobjc_disposeClassPair objc_disposeClassPair;
    pfobjc_getClass varobjc_getClass;
    pfobjc_lookUpClass varobjc_lookUpClass;

    pfobjc_msgSend objc_msgSend;
    pfobjc_msgSendSuper objc_msgSendSuper;

    version(AnyX86)
        pfobjc_msgSend_stret objc_msgSend_stret;

    version(X86)
        pfobjc_msgSend_fpret objc_msgSend_fpret;

    pfobject_getClassName varobject_getClassName;
    pfobject_getInstanceVariable object_getInstanceVariable;
    pfobject_setInstanceVariable object_setInstanceVariable;
    pfsel_registerName varsel_registerName;

    pfclass_getInstanceMethod varclass_getInstanceMethod;
    pfmethod_setImplementation method_setImplementation;

    pfobjc_getProtocol objc_getProtocol;
    pfclass_addProtocol class_addProtocol;
    pfobjc_allocateProtocol objc_allocateProtocol;
    pfobjc_registerProtocol objc_registerProtocol;
    pfclass_conformsToProtocol class_conformsToProtocol;
    pfprotocol_addMethodDescription protocol_addMethodDescription;
}

bool class_addIvar (Class cls, string name, size_t size, byte alignment, string types) nothrow @nogc
{
    return varclass_addIvar(cls, CString(name), size, alignment, CString(types));
}

bool class_addMethod (Class cls, SEL name, IMP imp, string types) nothrow @nogc
{
    return varclass_addMethod(cls, name, imp, CString(types));
}

Class objc_allocateClassPair (Class superclass, const(char)* name, size_t extraBytes) nothrow @nogc
{
    return varobjc_allocateClassPair(superclass, name, extraBytes);
}

id objc_getClass (string name) nothrow @nogc
{
    return varobjc_getClass(CString(name));
}

id objc_getClass (char* name) nothrow @nogc
{
    return varobjc_getClass(name);
}

id objc_lookUpClass (string name) nothrow @nogc
{
    return varobjc_lookUpClass(CString(name));
}
/*
string object_getClassName (id obj) nothrow @nogc
{
    return fromStringz(varobject_getClassName(obj)).idup;
}
*/
SEL sel_registerName (string str) nothrow @nogc
{
    return varsel_registerName(CString(str));
}

Method class_getInstanceMethod (Class aClass, string aSelector) nothrow @nogc
{
    return varclass_getInstanceMethod(aClass, CString(aSelector));
}

// Lazy selector literal
// eg: sel!"init"
SEL sel(string selectorName)() nothrow @nogc
{
    version(useTLS)
    {
        // Use of TLS here
        static size_t cached = 0;
        if (cached == 0)
        {
            cached = cast(size_t)( sel_registerName(selectorName) );        
        }
        return cast(SEL) cached;
    }
    else
    {
        // we use type-punning here because deep shared(T) is annoying
        shared(size_t) cached = 0;
        size_t got = atomicLoad(cached);
        if (got == 0)
        {
            got = cast(size_t)( sel_registerName(selectorName) );
            atomicStore(cached, got);
        }
        return cast(SEL) got;
    }
}

// Lazy class object
// eg: lazyClass!"NSObject"
id lazyClass(string className)() nothrow @nogc
{
    version(useTLS)
    {
        // Use of TLS here
        static size_t cached = 0;
        if (cached == 0)
        {
            cached = cast(size_t)( objc_getClass(className) );        
        }
        return cast(id) cached;
    }
    else
    {
        // we use type-punning here because deep shared(T) is annoying
        shared(size_t) cached = 0;
        size_t got = atomicLoad(cached);
        if (got == 0)
        {
            got = cast(size_t)( objc_getClass(className) );
            atomicStore(cached, got);
        }
        return cast(id) got;
    }
}

Protocol* lazyProtocol(string className)() nothrow @nogc
{
    version(useTLS)
    {
        static size_t cached = 0;
        if (cached == 0)
        {
            cached = cast(size_t)( objc_getProtocol(className) );        
        }
        return cast(Protocol*) cached;
    }
    else
    {
        // we use type-punning here because deep shared(T) is annoying
        shared(size_t) cached = 0;
        size_t got = atomicLoad(cached);
        if (got == 0)
        {
            got = cast(size_t)( objc_getProtocol(className) );
            atomicStore(cached, got);
        }
        return cast(Protocol*) got;
    }
}

// @encode replacement
template encode(T)
{
    static if (is(T == int))
        enum encode = "i";
    else static if (is(T == NSRect))
    {
        enum encode = "{_NSRect={_NSPoint=dd}{_NSSize=dd}}";
    }
    else static if (is(T == NSSize))
    {
        enum encode = "{_NSSize=dd}";
    }
    else
        static assert(false, "TODO implement encode for type " ~ T.stringof);
}