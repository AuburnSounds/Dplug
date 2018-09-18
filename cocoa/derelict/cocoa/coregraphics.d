/**
Utilities from the CoreGraphics framework.

Copyright: Guillaume Piolat 2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.cocoa.coregraphics;

import derelict.cocoa.runtime;
import derelict.cocoa.foundation;

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
