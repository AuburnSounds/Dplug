/*
* Copyright (c) 2015 Guillaume Piolat
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are
* met:
*
* * Redistributions of source code must retain the above copyright
*   notice, this list of conditions and the following disclaimer.
*
* * Redistributions in binary form must reproduce the above copyright
*   notice, this list of conditions and the following disclaimer in the
*   documentation and/or other materials provided with the distribution.
*
* * Neither the names 'Derelict', 'DerelictSDL', nor the names of its contributors
*   may be used to endorse or promote products derived from this software
*   without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
* "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
* TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
* PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
* CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
* EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
* PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
* LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
* NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
module derelict.carbon.coregraphics;

// TODO: this should go in its own Derelict package

version(OSX):

import derelict.util.system;
import derelict.util.loader;

import derelict.carbon.corefoundation;

static if(Derelict_OS_Mac)
    // because CoreGraphics.framework did not exist in OSX 10.6
    enum libNames = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices";
else
    static assert(0, "Need to implement CoreGraphics libNames for this operating system.");


class DerelictCoreGraphicsLoader : SharedLibLoader
{
    protected
    {
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

__gshared DerelictCoreGraphicsLoader DerelictCoreGraphics;

shared static this()
{
    DerelictCoreGraphics = new DerelictCoreGraphicsLoader;
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

CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h)
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



