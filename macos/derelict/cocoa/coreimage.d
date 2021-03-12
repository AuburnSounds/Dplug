/**
Dynamic bindings to the CoreImage framework.

Copyright: Guillaume Piolat 2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.cocoa.coreimage;

import derelict.cocoa.runtime;
import derelict.cocoa.foundation;
import derelict.cocoa.coregraphics;


struct CIContext
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(CIContext, "CIContext");

    void drawImage(CIImage image, CGRect inRect, CGRect fromRect)
    {
        alias fun_t = extern(C) void function (id obj, SEL sel, id, CGRect, CGRect) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"drawImage:inRect:fromRect:", image._id, inRect, fromRect);
    }
}

alias CIFormat = int;

extern(C)
{
    __gshared CIFormat kCIFormatARGB8;
    __gshared CIFormat kCIFormatRGBA16;
    __gshared CIFormat kCIFormatRGBAf;
    __gshared CIFormat kCIFormatRGBAh;
}

struct CIImage
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(CIImage, "CIImage");

    static CIImage imageWithBitmapData(NSData d, size_t bytesPerRow, CGSize size, CIFormat f, CGColorSpaceRef cs)
    {
        alias fun_t = extern(C) id function (id obj, SEL sel, id, NSUInteger, CGSize, CIFormat, CGColorSpaceRef) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(),
                                 sel!"imageWithBitmapData:bytesPerRow:size:format:colorSpace:",
                                 d._id, cast(NSUInteger)bytesPerRow, size, f, cs);
        return CIImage(result);
    }
}