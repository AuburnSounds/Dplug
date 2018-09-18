/**
Dynamic bindings to the Foundation framework.

Copyright: Guillaume Piolat 2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.cocoa.foundation;

import std.string;
import std.utf;

import dplug.core.nogc;

import derelict.cocoa.runtime;


// NSZone

extern (C) nothrow @nogc
{
    alias void* function(NSUInteger bytes) pfNSAllocateMemoryPages;
    alias void function (void* ptr, NSUInteger bytes) pfNSDeallocateMemoryPages;
    alias void function(id format, ...) pfNSLog;
}

__gshared
{
    pfNSDeallocateMemoryPages NSDeallocateMemoryPages;
    pfNSAllocateMemoryPages NSAllocateMemoryPages;
    pfNSLog NSLog;
}

__gshared
{
    //NSString NSDefaultRunLoopMode;
    NSString NSRunLoopCommonModes;
}

alias NSTimeInterval = double;


// Mixin'd by all Cocoa objects
mixin template NSObjectTemplate(T, string className)
{
nothrow @nogc:

    // create from an id
    this (id id_)
    {
        this._id = id_;
    }

    /// Allocates, but do not init
    static T alloc()
    {
        alias fun_t = extern(C) id function (id obj, SEL sel) nothrow @nogc;
        return T( (cast(fun_t)objc_msgSend)(getClassID(), sel!"alloc") );
    }

    static Class getClass()
    {
        return cast(Class)( lazyClass!className() );
    }

    static id getClassID()
    {
        return lazyClass!className();
    }
}

struct NSObject
{
nothrow @nogc:

    // The only field available in all NSObject hierarchy
    // That makes all these destructs idempotent with an id,
    // and the size of a pointer.
    id _id = null;

    // Subtype id
    bool opCast()
    {
        return _id != null;
    }

    mixin NSObjectTemplate!(NSObject, "NSObject");

    ~this()
    {
    }

    NSObject init_()
    {
        alias fun_t = extern(C) id function (id, const(SEL)) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"init");
        return NSObject(result);
    }

    void retain()
    {
        alias fun_t = extern(C) void function (id, const(SEL)) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"retain");
    }

    void release()
    {
        alias fun_t = extern(C) void function (id, const(SEL)) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"release");
    }
}

struct NSData
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSData, "NSData");

    static NSData data()
    {
        alias fun_t = extern(C) id function (id obj, const(SEL) sel) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"data");
        return NSData(result);
    }

    static NSData dataWithBytesNoCopy(void* bytes, NSUInteger length, bool freeWhenDone)
    {
        alias fun_t = extern(C) id function(id, const(SEL), void*, NSUInteger, BOOL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"dataWithBytesNoCopy:length:freeWhenDone:",
            bytes, length, freeWhenDone ? YES : NO);
        return NSData(result);
    }
}

struct NSString
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSString, "NSString");

    static NSString stringWith (wstring str) nothrow @nogc
    {
        alias fun_t = extern(C) id function(id, SEL, const(wchar)*, NSUInteger) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"stringWithCharacters:length:",
                                 CString16(str).storage, cast(NSUInteger)(str.length));
        return NSString(result);
    }

    size_t length ()
    {
        alias fun_t = extern(C) NSUInteger function(id, SEL) nothrow @nogc;
        return cast(size_t)( (cast(fun_t)objc_msgSend)(_id, sel!"length") );
    }

    char* UTF8String ()
    {
        alias fun_t = extern(C) char* function(id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"UTF8String");
    }

    void getCharacters (wchar* buffer, NSRange range)
    {
        alias fun_t = extern(C) void function(id, SEL, wchar*, NSRange) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"getCharacters:range:", buffer, range);
    }

    NSString stringWithCharacters (wchar* chars, size_t length)
    {
        alias fun_t = extern(C) id function(id, SEL, wchar*, NSUInteger) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"stringWithCharacters:length:", chars, cast(NSUInteger)length);
        return NSString(result);
    }

    NSRange rangeOfString (NSString aString)
    {
        alias fun_t = extern(C) NSRange function(id, SEL, id) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"rangeOfString", aString._id);
    }

    NSString stringByAppendingString (NSString aString)
    {
        alias fun_t = extern(C) id function(id, SEL, id) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"stringByAppendingString:", aString._id);
        return NSString(result);
    }

    /// Returns: The character at a given UTF-16 code unit index.
    wchar characterAtIndex(int index)
    {
        alias fun_t = extern(C) wchar function(id, SEL, NSUInteger) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"characterAtIndex:", cast(NSUInteger)index);
    }
}

struct NSURL
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSURL, "NSURL");

    static NSURL URLWithString(NSString str)
    {
        alias fun_t = extern(C) id function(id, SEL, id) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"URLWithString:", str._id);
        return NSURL(result);
    }

}

struct NSEnumerator
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSEnumerator, "NSEnumerator");

    id nextObject ()
    {
        alias fun_t = extern(C) id function(id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"nextObject");
    }
}

struct NSArray
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSArray, "NSArray");

    NSEnumerator objectEnumerator ()
    {
        alias fun_t = extern(C) id function(id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"objectEnumerator");
        return NSEnumerator(result);
    }
}


struct NSProcessInfo
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSProcessInfo, "NSProcessInfo");

    static NSProcessInfo processInfo ()
    {
        alias fun_t = extern(C) id function(id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(lazyClass!"NSProcessInfo", sel!"processInfo");
        return NSProcessInfo(result);
    }

    NSString processName ()
    {
        alias fun_t = extern(C) id function(id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"processName");
        return NSString(result);
    }
}

struct NSNotification
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSNotification, "NSNotification");
}

struct NSDictionary
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSDictionary, "NSDictionary");

    static NSDictionary dictionaryWithObjectsAndKeys(Args...)(id firstObject, Args args)
    {
        alias fun_t = extern(C) id function(id, SEL, id, ...) nothrow @nogc;
        auto result = (cast(fun_t) objc_msgSend)(getClassID(), sel!"dictionaryWithObjectsAndKeys:", firstObject, args);

        return NSDictionary(result);
    }

    id objectForKey(id key)
    {
        alias fun_t = extern(C) id function(id, SEL, id) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"objectForKey:", key);
        return result;
    }
}

struct NSAutoreleasePool
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSAutoreleasePool, "NSAutoreleasePool");
}

enum : int
{
    NSFileErrorMaximum = 1023,
    NSFileErrorMinimum = 0,
    NSFileLockingError = 255,
    NSFileNoSuchFileError = 4,
    NSFileReadCorruptFileError = 259,
    NSFileReadInapplicableStringEncodingError = 261,
    NSFileReadInvalidFileNameError = 258,
    NSFileReadNoPermissionError = 257,
    NSFileReadNoSuchFileError = 260,
    NSFileReadUnknownError = 256,
    NSFileReadUnsupportedSchemeError = 262,
    NSFileWriteInapplicableStringEncodingError = 517,
    NSFileWriteInvalidFileNameError = 514,
    NSFileWriteNoPermissionError = 513,
    NSFileWriteOutOfSpaceError = 640,
    NSFileWriteUnknownError = 512,
    NSFileWriteUnsupportedSchemeError = 518,
    NSFormattingError = 2048,
    NSFormattingErrorMaximum = 2559,
    NSFormattingErrorMinimum = 2048,
    NSKeyValueValidationError = 1024,
    NSUserCancelledError = 3072,
    NSValidationErrorMaximum = 2047,
    NSValidationErrorMinimum = 1024,

    NSExecutableArchitectureMismatchError = 3585,
    NSExecutableErrorMaximum = 3839,
    NSExecutableErrorMinimum = 3584,
    NSExecutableLinkError = 3588,
    NSExecutableLoadError = 3587,
    NSExecutableNotLoadableError = 3584,
    NSExecutableRuntimeMismatchError = 3586,
    NSFileReadTooLargeError = 263,
    NSFileReadUnknownStringEncodingError = 264,

    GSFoundationPlaceHolderError = 9999
}

struct NSError
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSError, "NSError");

    NSString localizedDescription()
    {
        alias fun_t = extern(C) id function(id, SEL) nothrow @nogc;
        id res = (cast(fun_t)objc_msgSend)(_id, sel!"localizedDescription");
        return NSString(res);
    }
}

struct NSBundle
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSBundle, "NSBundle");

    void initWithPath(NSString path)
    {
        alias fun_t = extern(C) void function(id, SEL, id) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"initWithPath:", path._id);
    }

    bool load()
    {
        alias fun_t = extern(C) BOOL function(id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"load") != NO;
    }

    bool unload()
    {
        alias fun_t = extern(C) BOOL function(id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"unload") != NO;
    }

    bool loadAndReturnError(NSError error)
    {
        alias fun_t = extern(C) BOOL function(id, SEL, id) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"loadAndReturnError:", error._id) != NO;
    }
}

struct NSTimer
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSTimer, "NSTimer");

    static NSTimer timerWithTimeInterval(double seconds, NSObject target, SEL selector, void* userInfo, bool repeats)
    {
        alias fun_t = extern(C) id function(id, SEL, double, id, SEL, id, BOOL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"timerWithTimeInterval:target:selector:userInfo:repeats:",
                    seconds, target._id, selector, cast(id)userInfo, repeats ? YES : NO);
        return NSTimer(result);
    }

    void invalidate()
    {
        alias fun_t = extern(C) void function(id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"invalidate");
    }
}

struct NSRunLoop
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSRunLoop, "NSRunLoop");

    static NSRunLoop currentRunLoop()
    {
        alias fun_t = extern(C) id function(id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"currentRunLoop");
        return NSRunLoop(result);
    }

    static NSRunLoop mainRunLoop()
    {
        alias fun_t = extern(C) id function(id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"mainRunLoop");
        return NSRunLoop(result);
    }

    void runUntilDate(NSDate limitDate)
    {
        alias fun_t = extern(C) void function(id, SEL, id) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"runUntilDate:", limitDate._id);
    }

    void addTimer(NSTimer aTimer, NSString forMode)
    {
        alias fun_t = extern(C) void function(id, SEL, id, id) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"addTimer:forMode:", aTimer._id, forMode._id);
    }
}

struct NSDate
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSDate, "NSDate");

    static NSDate date()
    {
        return NSDate(objc_msgSend(getClassID(), sel!"date"));
    }

    static NSTimeInterval timeIntervalSinceReferenceDate()
    {
        alias fun_t = extern(C) NSTimeInterval function(id, SEL) nothrow @nogc;

        version(X86)
            return (cast(fun_t)objc_msgSend_fpret)(getClassID(), sel!"timeIntervalSinceReferenceDate");
        else version(X86_64)
            return (cast(fun_t)objc_msgSend)(getClassID(), sel!"timeIntervalSinceReferenceDate");
        else
            static assert(false);
    }

    static NSDate dateWithTimeIntervalSinceNow(double secs)
    {
        alias fun_t = extern(C) id function(id, SEL, double) nothrow @nogc;
        id res = (cast(fun_t)objc_msgSend)(getClassID(), sel!"dateWithTimeIntervalSinceNow:", secs);

        return NSDate(res);
    }

    NSString description()
    {
        alias fun_t = extern(C) id function(id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"description");

        return NSString(result);
    }

    NSString descriptionWithLocale()
    {
        alias fun_t = extern(C) id function(id, SEL, void*) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"descriptionWithLocale:", null);
        return NSString(result);
    }
}

struct NSNumber
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSNumber, "NSNumber");

    static NSNumber numberWithUnsignedInt(uint value)
    {
        alias fun_t = extern(C) id function(id, SEL, uint) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"numberWithUnsignedInt:", value);

        return NSNumber(result);
    }
}
