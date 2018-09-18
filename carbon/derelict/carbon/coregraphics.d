/**
Dynamic bindings to the CoreGraphics framework.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.carbon.coregraphics;

import dplug.core.sharedlib;
import derelict.carbon.corefoundation;
import dplug.core.nogc;

version(OSX)
    // because CoreGraphics.framework did not exist in OSX 10.6
    enum libNames = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";
else
    enum libNames = "";


class DerelictCoreGraphicsLoader : SharedLibLoader
{
    public
    {
        nothrow @nogc:
        this()
        {
            super(libNames);
        }

        override void loadSymbols()
        {
            bindFunc(cast(void**)&CGColorSpaceCreateDeviceRGB, "CGColorSpaceCreateDeviceRGB");
            bindFunc(cast(void**)&CGColorSpaceRelease, "CGColorSpaceRelease");
            bindFunc(cast(void**)&CGContextDrawImage, "CGContextDrawImage");
            bindFunc(cast(void**)&CGContextScaleCTM, "CGContextScaleCTM");
            bindFunc(cast(void**)&CGContextTranslateCTM, "CGContextTranslateCTM");
            bindFunc(cast(void**)&CGDataProviderCreateWithData, "CGDataProviderCreateWithData");
            bindFunc(cast(void**)&CGDataProviderRelease, "CGDataProviderRelease");
            bindFunc(cast(void**)&CGImageRelease, "CGImageRelease");
            bindFunc(cast(void**)&CGImageCreate, "CGImageCreate");
            bindFunc(cast(void**)&CGColorSpaceCreateWithName, "CGColorSpaceCreateWithName");
        }
    }
}

private __gshared DerelictCoreGraphicsLoader DerelictCoreGraphics;

private __gshared loaderCounterCG = 0;

// Call this each time a novel owner uses these functions
// TODO: hold a mutex, because this isn't thread-safe
void acquireCoreGraphicsFunctions() nothrow @nogc
{
    if (DerelictCoreGraphics is null)  // You only live once
    {
        DerelictCoreGraphics = mallocNew!DerelictCoreGraphicsLoader();
        DerelictCoreGraphics.load();
    }
}

// Call this each time a novel owner releases a Cocoa functions
// TODO: hold a mutex, because this isn't thread-safe
void releaseCoreGraphicsFunctions() nothrow @nogc
{
    /*if (--loaderCounterCG == 0)
    {
        DerelictCoreGraphics.unload();
        DerelictCoreGraphics.destroyFree();
    }*/
}

unittest
{
    version(OSX)
    {
        acquireCoreGraphicsFunctions();
        releaseCoreGraphicsFunctions();
    }
}


// <CoreGraphics/CGBase.h>

static if ((void*).sizeof > int.sizeof) // 64bit
    alias CGFloat = double;
else
    alias CGFloat = float;


// <CoreGraphics/CGColorSpace.h>

alias CGColorSpaceRef = void*;

alias CGColorRenderingIntent = int;
enum : CGColorRenderingIntent
{
    kCGRenderingIntentDefault,
    kCGRenderingIntentAbsoluteColorimetric,
    kCGRenderingIntentRelativeColorimetric,
    kCGRenderingIntentPerceptual,
    kCGRenderingIntentSaturation
}

extern (C) nothrow @nogc
{
    alias da_CGColorSpaceCreateDeviceRGB = CGColorSpaceRef function();
    alias da_CGColorSpaceRelease = void function(CGColorSpaceRef);
    alias da_CGColorSpaceCreateWithName = CGColorSpaceRef function(CFStringRef);
}

__gshared
{
    da_CGColorSpaceCreateDeviceRGB CGColorSpaceCreateDeviceRGB;
    da_CGColorSpaceRelease CGColorSpaceRelease;
    da_CGColorSpaceCreateWithName CGColorSpaceCreateWithName;
}


// <CoreGraphics/CGContext.h>

alias CGContextRef = void*;

extern (C) nothrow @nogc
{
    alias da_CGContextDrawImage = void function(CGContextRef, CGRect, CGImageRef);
    alias da_CGContextScaleCTM = void function(CGContextRef, CGFloat, CGFloat);
    alias da_CGContextTranslateCTM = void function(CGContextRef c, CGFloat sx, CGFloat sy);
}

__gshared
{
    da_CGContextDrawImage CGContextDrawImage;
    da_CGContextScaleCTM CGContextScaleCTM;
    da_CGContextTranslateCTM CGContextTranslateCTM;
}



// <CoreGraphics/CGDataProvider.h>

alias CGDataProviderRef = void*;

extern(C) nothrow
{
    alias CGDataProviderReleaseDataCallback = void function(void* info, const(void)* data, size_t size);
}

extern(C) nothrow @nogc
{
    alias da_CGDataProviderCreateWithData = CGDataProviderRef function(void*, const(void)*, size_t, CGDataProviderReleaseDataCallback);
    alias da_CGDataProviderRelease = void function(CGDataProviderRef);
}

__gshared
{
    da_CGDataProviderCreateWithData CGDataProviderCreateWithData;
    da_CGDataProviderRelease CGDataProviderRelease;
}



// <CoreGraphics/CGGeometry.h>

struct CGPoint
{
    CGFloat x;
    CGFloat y;
}

struct CGSize
{
    CGFloat width;
    CGFloat height;
}

struct CGVector
{
    CGFloat dx;
    CGFloat dy;
}

struct CGRect
{
    CGPoint origin;
    CGSize size;
}

static immutable CGPoint CGPointZero = CGPoint(0, 0);
static immutable CGSize CGSizeZero = CGSize(0, 0);
static immutable CGRect CGRectZero = CGRect(CGPoint(0, 0), CGSize(0, 0));

CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) nothrow @nogc
{
    return CGRect(CGPoint(x, y), CGSize(w, h));
}



// <CoreGraphics/CGImage.h>

alias CGImageRef = void*;

alias CGBitmapInfo = uint;
enum : CGBitmapInfo
{
    kCGBitmapAlphaInfoMask = 0x1F,
    kCGBitmapFloatComponents = (1 << 8),
    kCGBitmapByteOrderMask = 0x7000,
    kCGBitmapByteOrderDefault = (0 << 12),
    kCGBitmapByteOrder16Little = (1 << 12),
    kCGBitmapByteOrder32Little = (2 << 12),
    kCGBitmapByteOrder16Big = (3 << 12),
    kCGBitmapByteOrder32Big = (4 << 12)
}

extern (C) nothrow @nogc
{
    alias da_CGImageRelease = void function(CGImageRef);

    alias da_CGImageCreate = CGImageRef function(size_t width, size_t height, size_t bitsPerComponent,
                                                 size_t bitsPerPixel, size_t bytesPerRow,
                                                 CGColorSpaceRef space, CGBitmapInfo bitmapInfo,
                                                 CGDataProviderRef provider, const CGFloat *decode,
                                                 bool shouldInterpolate, CGColorRenderingIntent intent);
}

__gshared
{
    da_CGImageRelease CGImageRelease;
    da_CGImageCreate CGImageCreate;
}



