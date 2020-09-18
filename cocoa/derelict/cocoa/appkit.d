/**
Dynamic bindings to the Appkit framework.

Copyright: Guillaume Piolat 2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module derelict.cocoa.appkit;

import std.string;

import derelict.cocoa.runtime;
import derelict.cocoa.foundation;
import derelict.cocoa.coreimage;
import derelict.cocoa.coregraphics;


// free functions
extern (C) nothrow @nogc
{
    alias bool function() pfNSApplicationLoad;
}

__gshared
{
    pfNSApplicationLoad NSApplicationLoad;
}

alias NSApplicationActivationPolicy = NSInteger;
enum : NSApplicationActivationPolicy
{
   NSApplicationActivationPolicyRegular = 0,
   NSApplicationActivationPolicyAccessory = 1,
   NSApplicationActivationPolicyProhibited = 2
}

struct NSApplication
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSApplication, "NSApplication");

    public static NSApplication sharedApplication ()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(lazyClass!"NSApplication", sel!"sharedApplication");
        return NSApplication(result);
    }

    void setDelegate (id object)
    {
        alias fun_t = extern(C) void function (id, SEL, id) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setDelegate:", object.id);
    }

    void setActivationPolicy(NSApplicationActivationPolicy policy)
    {
        alias fun_t = extern(C) void function (id, SEL, NSApplicationActivationPolicy) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setActivationPolicy:", policy);
    }

    void activateIgnoringOtherApps(BOOL b)
    {
        alias fun_t = extern(C) void function (id, SEL, BOOL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"activateIgnoringOtherApps:", b);
    }

    void run ()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"run");
    }

    void stop (id sender)
    {
        alias fun_t = extern(C) void function (id, SEL, id) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"stop:", sender);
    }

    void sendEvent(NSEvent event)
    {
        alias fun_t = extern(C) void function (id, SEL, id) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"sendEvent:", event._id);
    }
}


// NSResponder

struct NSResponder
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSResponder, "NSResponder");
}


// NSView

alias NSBorderType = NSUInteger;
enum : NSBorderType
{
    NSNoBorder     = 0,
    NSLineBorder   = 1,
    NSBezelBorder  = 2,
    NSGrooveBorder = 3
}

alias NSAutoresizingMaskOptions = NSUInteger;
enum : NSAutoresizingMaskOptions
{
    NSViewNotSizable     = 0,
    NSViewMinXMargin     = 1,
    NSViewWidthSizable   = 2,
    NSViewMaxXMargin     = 4,
    NSViewMinYMargin     = 8,
    NSViewHeightSizable  = 16,
    NSViewMaxYMargin     = 32
}


struct NSView
{
nothrow @nogc:

    NSResponder parent;
    alias parent this;

    mixin NSObjectTemplate!(NSView, "NSView");

    void initWithFrame(NSRect rect)
    {
        alias fun_t = extern(C) void function (id, SEL, NSRect) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"initWithFrame:", rect);
    }

    void addSubview(NSView subView)
    {
        alias fun_t = extern(C) void function (id, SEL, id) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"addSubview:", subView._id);
    }

    void removeFromSuperview()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"removeFromSuperview");
    }

    NSWindow window()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"window");
        return NSWindow(result);
    }

    void setNeedsDisplayInRect(NSRect rect)
    {
        alias fun_t = extern(C) void function (id, SEL, NSRect) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setNeedsDisplayInRect:", rect);
    }

    void display()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"display");
    }

    void setNeedsDisplay()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setNeedsDisplay:");
    }

    NSPoint convertPoint(NSPoint point, NSView view)
    {
        alias fun_t = extern(C) NSPoint function (id, const(SEL), NSPoint, id) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"convertPoint:fromView:", point, view._id);
    }

    NSRect convertRect(NSRect rect, NSView view)
    {
        alias fun_t = extern(C) NSRect function (id, const(SEL), NSRect, id) nothrow @nogc;
        return (cast(fun_t)objc_msgSend_stret)(_id, sel!"convertRect:fromView:", rect, view._id);
    }

    NSRect frame()
    {
        alias fun_t = extern(C) NSRect function (id, const(SEL)) nothrow @nogc;
        return (cast(fun_t)objc_msgSend_stret)(_id, sel!"frame");
    }

    NSRect bounds()
    {
        alias fun_t = extern(C) NSRect function (id, const(SEL)) nothrow @nogc;
        return (cast(fun_t)objc_msgSend_stret)(_id, sel!"bounds");
    }

    CALayer layer()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"layer");
        return CALayer(result);
    }

    void setWantsLayer(BOOL value)
    {
        alias fun_t = extern(C) void function (id, SEL, BOOL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setWantsLayer:", value);
    }

    void setFrameSize(NSSize newSize)
    {
        version(Debug)
        {
            import core.stdc.stdlib;
            fprintf(stderr, "this is a test");
        }
        alias fun_t = extern(C) void function (id, SEL, NSSize) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setFrameSize:", newSize);
    }
}

// CALayer
struct CALayer
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(CALayer, "CALayer");

    void setDrawsAsynchronously(BOOL value)
    {
        alias fun_t = extern(C) void function (id, SEL, BOOL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setDrawsAsynchronously:", value);
    }

    void setOpaque(BOOL value)
    {
        alias fun_t = extern(C) void function (id, SEL, BOOL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setOpaque:", value);
    }
}


// NSWindow

alias NSBackingStoreType = NSUInteger;
enum : NSBackingStoreType
{
    NSBackingStoreRetained     = 0,
    NSBackingStoreNonretained  = 1,
    NSBackingStoreBuffered     = 2
}

enum : NSUInteger
{
   NSBorderlessWindowMask = 0,
   NSTitledWindowMask = 1 << 0,
   NSClosableWindowMask = 1 << 1,
   NSMiniaturizableWindowMask = 1 << 2,
   NSResizableWindowMask = 1 << 3,
   NSTexturedBackgroundWindowMask = 1 << 8
}

struct NSWindow
{
nothrow @nogc:

    NSResponder parent;
    alias parent this;

    mixin NSObjectTemplate!(NSWindow, "NSWindow");

    void initWithContentRect(NSRect contentRect)
    {
        alias fun_t = extern(C) void function (id, SEL, NSRect) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"initWithContentRect:", contentRect);
    }

    void initWithContentRect(NSRect contentRect, NSUInteger windowStyle, NSBackingStoreType bufferingType, BOOL deferCreation)
    {
        alias fun_t = extern(C) void function (id, SEL, NSRect, NSUInteger, NSBackingStoreType, BOOL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"initWithContentRect:styleMask:backing:defer:", contentRect, windowStyle, bufferingType, deferCreation);
    }

    NSView contentView()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"contentView");
        return NSView(result);
    }

    void makeKeyAndOrderFront()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"makeKeyAndOrderFront:");
    }

    bool makeFirstResponder(NSResponder responder)
    {
        alias fun_t = extern(C) BOOL function (id, SEL, id) nothrow @nogc;
        BOOL result = (cast(fun_t)objc_msgSend)(_id, sel!"makeFirstResponder:", responder._id);
        return result != NO;
    }

    NSEvent nextEventMatchingMask(NSUInteger eventMask)
    {
        alias fun_t = extern(C) id function (id, SEL, NSUInteger) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"nextEventMatchingMask:", eventMask);
        return NSEvent(result);
    }

    NSPoint mouseLocationOutsideOfEventStream()
    {
        alias fun_t = extern(C) NSPoint function (id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"mouseLocationOutsideOfEventStream");
    }

    void setAcceptsMouseMovedEvents(bool b)
    {
        alias fun_t = extern(C) void function (id, SEL, BOOL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setAcceptsMouseMovedEvents:", b ? YES : NO);
    }

    void setFrameDisplay(NSRect frameRect, bool display)
    {
        alias fun_t = extern(C) void function(id, SEL, NSRect, BOOL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"setFrameDisplay", frameRect, display ? YES : NO);
    }
}


alias NSEventType = int;
enum : NSEventType
{
    NSLeftMouseDown       = 1,
    NSLeftMouseUp         = 2,
    NSRightMouseDown      = 3,
    NSRightMouseUp        = 4,
    NSMouseMoved          = 5,
    NSLeftMouseDragged    = 6,
    NSRightMouseDragged   = 7,
    NSMouseEntered        = 8,
    NSMouseExited         = 9,
    NSKeyDown             = 10,
    NSKeyUp               = 11,
    NSFlagsChanged        = 12,
    NSAppKitDefined       = 13,
    NSSystemDefined       = 14,
    NSApplicationDefined  = 15,
    NSPeriodic            = 16,
    NSCursorUpdate        = 17,
    NSScrollWheel         = 22,
    NSTabletPoint         = 23,
    NSTabletProximity     = 24,
    NSOtherMouseDown      = 25,
    NSOtherMouseUp        = 26,
    NSOtherMouseDragged   = 27,
    NSRotate              = 18,
    NSBeginGesture        = 19,
    NSEndGesture          = 20,
    NSMagnify             = 30,
    NSSwipe               = 31
}

enum : NSUInteger
{
    NSLeftMouseDownMask      = 1 << NSLeftMouseDown,
    NSLeftMouseUpMask        = 1 << NSLeftMouseUp,
    NSRightMouseDownMask     = 1 << NSRightMouseDown,
    NSRightMouseUpMask       = 1 << NSRightMouseUp,
    NSMouseMovedMask         = 1 << NSMouseMoved,
    NSLeftMouseDraggedMask   = 1 << NSLeftMouseDragged,
    NSRightMouseDraggedMask  = 1 << NSRightMouseDragged,
    NSMouseEnteredMask       = 1 << NSMouseEntered,
    NSMouseExitedMask        = 1 << NSMouseExited,
    NSKeyDownMask            = 1 << NSKeyDown,
    NSKeyUpMask              = 1 << NSKeyUp,
    NSFlagsChangedMask       = 1 << NSFlagsChanged,
    NSAppKitDefinedMask      = 1 << NSAppKitDefined,
    NSSystemDefinedMask      = 1 << NSSystemDefined,
    NSApplicationDefinedMask = 1 << NSApplicationDefined,
    NSPeriodicMask           = 1 << NSPeriodic,
    NSCursorUpdateMask       = 1 << NSCursorUpdate,
    NSScrollWheelMask        = 1 << NSScrollWheel,
    NSTabletPointMask        = 1 << NSTabletPoint,
    NSTabletProximityMask    = 1 << NSTabletProximity,
    NSOtherMouseDownMask     = 1 << NSOtherMouseDown,
    NSOtherMouseUpMask       = 1 << NSOtherMouseUp,
    NSOtherMouseDraggedMask  = 1 << NSOtherMouseDragged,
    NSRotateMask             = 1 << NSRotate,
    NSBeginGestureMask       = 1 << NSBeginGesture,
    NSEndGestureMask         = 1 << NSEndGesture,
    NSMagnifyMask            = 1 << NSMagnify,
    NSSwipeMask              = 1 << NSSwipe,
    NSAnyEventMask           = 0xffffffffU,
}

/// Keycodes
enum : ushort
{
    kVK_ANSI_A                    = 0x00,
    kVK_ANSI_S                    = 0x01,
    kVK_ANSI_D                    = 0x02,
    kVK_ANSI_F                    = 0x03,
    kVK_ANSI_H                    = 0x04,
    kVK_ANSI_G                    = 0x05,
    kVK_ANSI_Z                    = 0x06,
    kVK_ANSI_X                    = 0x07,
    kVK_ANSI_C                    = 0x08,
    kVK_ANSI_V                    = 0x09,
    kVK_ANSI_B                    = 0x0B,
    kVK_ANSI_Q                    = 0x0C,
    kVK_ANSI_W                    = 0x0D,
    kVK_ANSI_E                    = 0x0E,
    kVK_ANSI_R                    = 0x0F,
    kVK_ANSI_Y                    = 0x10,
    kVK_ANSI_T                    = 0x11,
    kVK_ANSI_1                    = 0x12,
    kVK_ANSI_2                    = 0x13,
    kVK_ANSI_3                    = 0x14,
    kVK_ANSI_4                    = 0x15,
    kVK_ANSI_6                    = 0x16,
    kVK_ANSI_5                    = 0x17,
    kVK_ANSI_Equal                = 0x18,
    kVK_ANSI_9                    = 0x19,
    kVK_ANSI_7                    = 0x1A,
    kVK_ANSI_Minus                = 0x1B,
    kVK_ANSI_8                    = 0x1C,
    kVK_ANSI_0                    = 0x1D,
    kVK_ANSI_RightBracket         = 0x1E,
    kVK_ANSI_O                    = 0x1F,
    kVK_ANSI_U                    = 0x20,
    kVK_ANSI_LeftBracket          = 0x21,
    kVK_ANSI_I                    = 0x22,
    kVK_ANSI_P                    = 0x23,
    kVK_ANSI_L                    = 0x25,
    kVK_ANSI_J                    = 0x26,
    kVK_ANSI_Quote                = 0x27,
    kVK_ANSI_K                    = 0x28,
    kVK_ANSI_Semicolon            = 0x29,
    kVK_ANSI_Backslash            = 0x2A,
    kVK_ANSI_Comma                = 0x2B,
    kVK_ANSI_Slash                = 0x2C,
    kVK_ANSI_N                    = 0x2D,
    kVK_ANSI_M                    = 0x2E,
    kVK_ANSI_Period               = 0x2F,
    kVK_ANSI_Grave                = 0x32,
    kVK_ANSI_KeypadDecimal        = 0x41,
    kVK_ANSI_KeypadMultiply       = 0x43,
    kVK_ANSI_KeypadPlus           = 0x45,
    kVK_ANSI_KeypadClear          = 0x47,
    kVK_ANSI_KeypadDivide         = 0x4B,
    kVK_ANSI_KeypadEnter          = 0x4C,
    kVK_ANSI_KeypadMinus          = 0x4E,
    kVK_ANSI_KeypadEquals         = 0x51,
    kVK_ANSI_Keypad0              = 0x52,
    kVK_ANSI_Keypad1              = 0x53,
    kVK_ANSI_Keypad2              = 0x54,
    kVK_ANSI_Keypad3              = 0x55,
    kVK_ANSI_Keypad4              = 0x56,
    kVK_ANSI_Keypad5              = 0x57,
    kVK_ANSI_Keypad6              = 0x58,
    kVK_ANSI_Keypad7              = 0x59,
    kVK_ANSI_Keypad8              = 0x5B,
    kVK_ANSI_Keypad9              = 0x5C
}

/// Keycodes for keys that are independent of keyboard layout.
enum : ushort
{
    kVK_Return                    = 0x24,
    kVK_Tab                       = 0x30,
    kVK_Space                     = 0x31,
    kVK_Delete                    = 0x33,
    kVK_Escape                    = 0x35,
    kVK_Command                   = 0x37,
    kVK_Shift                     = 0x38,
    kVK_CapsLock                  = 0x39,
    kVK_Option                    = 0x3A,
    kVK_Control                   = 0x3B,
    kVK_RightShift                = 0x3C,
    kVK_RightOption               = 0x3D,
    kVK_RightControl              = 0x3E,
    kVK_Function                  = 0x3F,
    kVK_F17                       = 0x40,
    kVK_VolumeUp                  = 0x48,
    kVK_VolumeDown                = 0x49,
    kVK_Mute                      = 0x4A,
    kVK_F18                       = 0x4F,
    kVK_F19                       = 0x50,
    kVK_F20                       = 0x5A,
    kVK_F5                        = 0x60,
    kVK_F6                        = 0x61,
    kVK_F7                        = 0x62,
    kVK_F3                        = 0x63,
    kVK_F8                        = 0x64,
    kVK_F9                        = 0x65,
    kVK_F11                       = 0x67,
    kVK_F13                       = 0x69,
    kVK_F16                       = 0x6A,
    kVK_F14                       = 0x6B,
    kVK_F10                       = 0x6D,
    kVK_F12                       = 0x6F,
    kVK_F15                       = 0x71,
    kVK_Help                      = 0x72,
    kVK_Home                      = 0x73,
    kVK_PageUp                    = 0x74,
    kVK_ForwardDelete             = 0x75,
    kVK_F4                        = 0x76,
    kVK_End                       = 0x77,
    kVK_F2                        = 0x78,
    kVK_PageDown                  = 0x79,
    kVK_F1                        = 0x7A,
    kVK_LeftArrow                 = 0x7B,
    kVK_RightArrow                = 0x7C,
    kVK_DownArrow                 = 0x7D,
    kVK_UpArrow                   = 0x7E
}

/// ISO keyboards only.
enum : ushort
{
  kVK_ISO_Section               = 0x0A
}

///JIS keyboards only.
enum : ushort
{
  kVK_JIS_Yen                   = 0x5D,
  kVK_JIS_Underscore            = 0x5E,
  kVK_JIS_KeypadComma           = 0x5F,
  kVK_JIS_Eisu                  = 0x66,
  kVK_JIS_Kana                  = 0x68
}

alias NSEventModifierFlags = int;
enum : NSEventModifierFlags
{
   NSAlphaShiftKeyMask = 1 << 16,
   NSShiftKeyMask      = 1 << 17,
   NSControlKeyMask    = 1 << 18,
   NSAlternateKeyMask  = 1 << 19,
   NSCommandKeyMask    = 1 << 20,
   NSNumericPadKeyMask = 1 << 21,
   NSHelpKeyMask       = 1 << 22,
   NSFunctionKeyMask   = 1 << 23,
   NSDeviceIndependentModifierFlagsMask = 0xffff0000U
}

struct NSEvent
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSEvent, "NSEvent");

    NSWindow window()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"window");
        return NSWindow(result);
    }

    NSEventType type()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"type");
        return cast(NSEventType)result;
    }

    int clickCount()
    {
        alias fun_t = extern(C) NSInteger function (id, SEL) nothrow @nogc;
        return cast(int)( (cast(fun_t)objc_msgSend)(_id, sel!"clickCount") );
    }

    int buttonNumber()
    {
        alias fun_t = extern(C) NSInteger function (id, SEL) nothrow @nogc;
        return cast(int)( (cast(fun_t)objc_msgSend)(_id, sel!"buttonNumber") );
    }

    uint pressedMouseButtons()
    {
        alias fun_t = extern(C) NSUInteger function (id, SEL) nothrow @nogc;
        return cast(uint)( (cast(fun_t)objc_msgSend)(getClassID(), sel!"pressedMouseButtons") );
    }

    NSEventModifierFlags modifierFlags()
    {
        alias fun_t = extern(C) NSEventModifierFlags function (id, SEL) nothrow @nogc;
        return cast(uint)( (cast(fun_t)objc_msgSend)(_id, sel!"modifierFlags") );
    }

    NSPoint mouseLocation()
    {
        alias fun_t = extern(C) NSPoint function (id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(getClassID(), sel!"mouseLocation");
    }

    double deltaX()
    {
        alias fun_t = extern(C) double function (id, SEL) nothrow @nogc;
        version(X86)
            return (cast(fun_t)objc_msgSend_fpret)(_id, sel!"deltaX");
        else version(X86_64)
            return (cast(fun_t)objc_msgSend)(_id, sel!"deltaX");
        else
            static assert(false);
    }

    double deltaY()
    {
        alias fun_t = extern(C) double function (id, SEL) nothrow @nogc;
        version(X86)
            return (cast(fun_t)objc_msgSend_fpret)(_id, sel!"deltaY");
        else version(X86_64)
            return (cast(fun_t)objc_msgSend)(_id, sel!"deltaY");
        else
            static assert(false);
    }

    ushort keyCode()
    {
        alias fun_t = extern(C) ushort function (id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"keyCode");
    }

    NSString charactersIgnoringModifiers()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        auto id = (cast(fun_t)objc_msgSend)(_id, sel!"charactersIgnoringModifiers");
        return NSString(id);
    }

    NSPoint locationInWindow()
    {
        alias fun_t = extern(C) NSPoint function (id, SEL) nothrow @nogc;
        fun_t fun = cast(fun_t)objc_msgSend;
        SEL sel = sel!"locationInWindow";
        return fun(_id, sel);
    }
}

struct NSGraphicsContext
{
nothrow @nogc:
    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSGraphicsContext, "NSGraphicsContext");

    static NSGraphicsContext currentContext()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(getClassID(), sel!"currentContext");
        return NSGraphicsContext(result);
    }

    void saveGraphicsState()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"saveGraphicsState");
    }

    void restoreGraphicsState()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(_id, sel!"restoreGraphicsState");
    }

    bool flipped()
    {
        alias fun_t = extern(C) BOOL function (id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"flipped") != NO;
    }

    CIContext getCIContext()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        id result = (cast(fun_t)objc_msgSend)(_id, sel!"CIContext");
        return CIContext(result);
    }
}

struct NSColorSpace
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSColorSpace, "NSColorSpace");

    static NSColorSpace sRGBColorSpace()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        return NSColorSpace( (cast(fun_t)objc_msgSend)(getClassID(), sel!"sRGBColorSpace") );
    }

    // Should the NSColorSpace outlive the returned reference? Documentation says nothing.
    CGColorSpaceRef CGColorSpace()
    {
        alias fun_t = extern(C) CGColorSpaceRef function (id, SEL) nothrow @nogc;
        return (cast(fun_t)objc_msgSend)(_id, sel!"CGColorSpace");
    }
}

struct NSCursor
{
nothrow @nogc:

    NSObject parent;
    alias parent this;

    mixin NSObjectTemplate!(NSCursor, "NSCursor");

    static NSCursor arrowCursor()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        return NSCursor( (cast(fun_t)objc_msgSend)(getClassID(), sel!"arrowCursor") );
    }

    static void hide()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(getClassID(), sel!"hide");
    }

    static void unhide()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(getClassID(), sel!"unhide");
    }

    static void pop()
    {
        alias fun_t = extern(C) id function (id, SEL) nothrow @nogc;
        (cast(fun_t)objc_msgSend)(getClassID(), sel!"pop");
    }

    void push()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        objc_msgSend(_id, sel!"push");
    }

    void set()
    {
        alias fun_t = extern(C) void function (id, SEL) nothrow @nogc;
        objc_msgSend(_id, sel!"set");
    }
}