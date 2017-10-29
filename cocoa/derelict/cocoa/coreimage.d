/*
* Copyright (c) 2004-2015 Derelict Developers
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
/**
    Dynamic bindings to the CoreImage framework.
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