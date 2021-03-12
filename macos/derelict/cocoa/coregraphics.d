/**
Utilities from the CoreGraphics framework.

Copyright: Guillaume Piolat 2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.cocoa.coregraphics;

import derelict.cocoa.runtime;
import derelict.cocoa.foundation;
import dplug.core.sharedlib;

import dplug.core.nogc;


version(OSX)
    enum libNames = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics";
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
            bindFunc(cast(void**)&CGContextDrawImage, "CGContextDrawImage");

            bindFunc(cast(void**)&CGImageCreate, "CGImageCreate");
            bindFunc(cast(void**)&CGImageRelease, "CGImageRelease");

            bindFunc(cast(void**)&CGDataProviderCreateWithData, "CGDataProviderCreateWithData");
            bindFunc(cast(void**)&CGDataProviderRelease, "CGDataProviderRelease");            
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
        DerelictCoreServices.unload();
        DerelictCoreServices.destroyFree();
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


alias CGPoint = NSPoint;
alias CGSize = NSSize;
alias CGRect = NSRect;

alias CGMakeRect = NSMakeRect;

CGRect NSRectToCGRect(NSRect rect) pure nothrow @nogc
{
    return rect;
}

NSRect CGRectToNSRect(CGRect rect) pure nothrow @nogc
{
    return rect;
}

alias CGColorSpaceRef = void*;
alias CGContextRef = void*;


extern(C) nothrow @nogc
{
    alias da_CGContextDrawImage = void function(CGContextRef c, CGRect rect, CGImageRef image);

}
__gshared
{
    da_CGContextDrawImage CGContextDrawImage;
}

alias CGImageRef = void*;

extern(C) nothrow @nogc
{
    alias da_CGImageCreate = CGImageRef function(size_t width, 
                                                 size_t height, 
                                                 size_t bitsPerComponent, 
                                                 size_t bitsPerPixel, 
                                                 size_t bytesPerRow, 
                                                 CGColorSpaceRef space, 
                                                 CGBitmapInfo bitmapInfo, 
                                                 CGDataProviderRef provider, 
                                                 const(CGFloat)*decode, 
                                                 bool shouldInterpolate, 
                                                 CGColorRenderingIntent intent);
    alias da_CGImageRelease = void function(CGImageRef image);
}
__gshared
{
    da_CGImageCreate CGImageCreate;
    da_CGImageRelease CGImageRelease;
}

alias CGImageByteOrderInfo = uint;

enum : CGImageByteOrderInfo
{
    kCGImageByteOrderMask     = 0x7000,
    kCGImageByteOrderDefault  = (0 << 12),
    kCGImageByteOrder16Little = (1 << 12),
    kCGImageByteOrder32Little = (2 << 12),
    kCGImageByteOrder16Big    = (3 << 12),
    kCGImageByteOrder32Big    = (4 << 12)
}

enum : uint
{
    kCGImageAlphaNone               = 0,
    kCGImageAlphaPremultipliedLast  = 1,
    kCGImageAlphaPremultipliedFirst = 2,
    kCGImageAlphaLast               = 3,
    kCGImageAlphaFirst              = 4,
    kCGImageAlphaNoneSkipLast       = 5,
    kCGImageAlphaNoneSkipFirst      = 6,
}

alias CGBitmapInfo = uint;
enum : CGBitmapInfo
{
    kCGBitmapAlphaInfoMask = 0x1F,
    kCGBitmapFloatInfoMask = 0xF00,
    kCGBitmapFloatComponents = (1 << 8),
    kCGBitmapByteOrderMask     = kCGImageByteOrderMask,
    kCGBitmapByteOrderDefault  = kCGImageByteOrderDefault,
    kCGBitmapByteOrder16Little = kCGImageByteOrder16Little,
    kCGBitmapByteOrder32Little = kCGImageByteOrder32Little,
    kCGBitmapByteOrder16Big    = kCGImageByteOrder16Big,
    kCGBitmapByteOrder32Big    = kCGImageByteOrder32Big
}

alias CGColorRenderingIntent = uint;
enum : CGColorRenderingIntent
{
    kCGRenderingIntentDefault              = 0,
    kCGRenderingIntentAbsoluteColorimetric = 1,
    kCGRenderingIntentRelativeColorimetric = 2,
    kCGRenderingIntentPerceptual           = 3,
    kCGRenderingIntentSaturation           = 4,
}



alias CGDataProviderRef = void*;
alias CGDataProviderReleaseDataCallback = void*;

extern(C) nothrow @nogc
{
    alias da_CGDataProviderCreateWithData = CGDataProviderRef function(void *info, 
                                                                       const(void) *data, 
                                                                       size_t size, 
                                                                       CGDataProviderReleaseDataCallback releaseData);
    alias da_CGDataProviderRelease = void function(CGDataProviderRef provider);
}
__gshared
{
    da_CGDataProviderCreateWithData CGDataProviderCreateWithData;
    da_CGDataProviderRelease CGDataProviderRelease;
}
