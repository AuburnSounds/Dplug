/**
* Cocoa window implementation.
* Copyright: Copyright Guillaume Piolat 2015 - 2021.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.window.cocoawindow;

import core.stdc.stdlib;

import std.string;
import std.uuid;

import dplug.math.vector;
import dplug.math.box;
import dplug.graphics.image;

import dplug.core.sync;
import dplug.core.runtime;
import dplug.core.nogc;
import dplug.core.random;
import dplug.core.thread;
import dplug.window.window;

import derelict.cocoa;

version(legacyMouseCursor)
{
    version = noCursors; // FUTURE: tell to replace with Dplug_NoMouseCursor
}
else version(Dplug_NoMouseCursor)
{
    version = noCursors;
}


version = useCoreGraphicsContext;

final class CocoaWindow : IWindow
{
nothrow:
@nogc:
private:
    IWindowListener _listener;

    NSColorSpace _nsColorSpace;
    CGColorSpaceRef _cgColorSpaceRef;
    NSData _imageData;
    NSString _logFormatStr;

    // Only used by host windows
    NSWindow _nsWindow;
    NSApplication _nsApplication;

    DPlugCustomView _view = null;

    bool _terminated = false;

    int _lastMouseX, _lastMouseY;
    bool _firstMouseMove = true;

    int _width;
    int _height;

    ImageRef!RGBA _wfb;

    uint _timeAtCreationInMs;
    uint _lastMeasturedTimeInMs;
    bool _dirtyAreasAreNotYetComputed;

    bool _isHostWindow;
    bool _drawRectWorkaround; // See Issue #505 & #705, drawRect: returning always one big rectangle, killing CPU

    MouseCursor _lastMouseCursor;

public:

    this(WindowUsage usage, void* parentWindow, IWindowListener listener, int width, int height)
    {
        _isHostWindow = (usage == WindowUsage.host);

        _listener = listener;

        acquireCocoaFunctions();
        acquireCoreGraphicsFunctions();
        NSApplicationLoad(); // to use Cocoa in Carbon applications
        bool parentViewExists = parentWindow !is null;

        _width = 0;
        _height = 0;

        _nsColorSpace = NSColorSpace.sRGBColorSpace();
        // hopefully not null else the colors will be brighter
        _cgColorSpaceRef = _nsColorSpace.CGColorSpace();

        _logFormatStr = NSString.stringWith("%@");

        _timeAtCreationInMs = getTimeMs();
        _lastMeasturedTimeInMs = _timeAtCreationInMs;

        _dirtyAreasAreNotYetComputed = true;

        // The drawRect: failure of having small rectangles started with 11.0 Big Sur beta 9.
        // It was afterwards removed for Issue #705, it's no longer useful in Monterey, and in Ardour was making things worse.
        version(OSX)
            _drawRectWorkaround = (getMacOSVersion().major == 11);

        if (!_isHostWindow)
        {
            DPlugCustomView.generateClassName();
            DPlugCustomView.registerSubclass();

            _view = DPlugCustomView.alloc();
            _view.initialize(this, width, height);

            // GOAL: Force display by the GPU, this is supposed to solve
            // resampling problems on HiDPI like 4k and 5k
            // REALITY: QA reports this to be blurrier AND slower than previously
            // Layer has to be there for the drawRect workaround.
            if (_drawRectWorkaround)
                _view.setWantsLayer(YES);

            //_view.layer.setDrawsAsynchronously(YES);
            // This is supposed to make things faster, but doesn't
            //_view.layer.setOpaque(YES);

            // In VST, add the view to the parent view.
            // In AU (parentWindow == null), a reference to the view is returned instead and the host does it.
            if (parentWindow !is null)
            {
                NSView parentView = NSView(cast(id)parentWindow);
                parentView.addSubview(_view);
            }

            // See Issue #688: when changing the buffer size or sampling rate,
            // Logic destroy and reloads the plugin, with same settings. The window
            // is reused, thus layout doesn't get called and the plugin is unsized!
            layout();
        }
        else
        {
            _nsApplication = NSApplication.sharedApplication;
            _nsApplication.setActivationPolicy(NSApplicationActivationPolicyRegular);
            _nsWindow = NSWindow.alloc();
            _nsWindow.initWithContentRect(NSMakeRect(0, 0, width, height),
                                            NSBorderlessWindowMask, NSBackingStoreBuffered, NO);
            _nsWindow.makeKeyAndOrderFront();
            _nsApplication.activateIgnoringOtherApps(YES);
        }
    }

    ~this()
    {
        if (!_isHostWindow)
        {
            _terminated = true;

            {
                _view.killTimer();
            }

            _view.removeFromSuperview();
            _view.release();
            _view = DPlugCustomView(null);

            DPlugCustomView.unregisterSubclass();
        }
        else
        {
            _nsWindow.destroy();
        }

        releaseCocoaFunctions();
    }

    // Implements IWindow
    override void waitEventAndDispatch()
    {
        if (!_isHostWindow)
            assert(false); // only valid for a host window

        NSEvent event = _nsWindow.nextEventMatchingMask(cast(NSUInteger)-1);
        _nsApplication.sendEvent(event);
    }

    override bool terminated()
    {
        return _terminated;
    }

    override uint getTimeMs()
    {
        double timeMs = NSDate.timeIntervalSinceReferenceDate() * 1000.0;

        // WARNING: ARM and x86 do not convert float to int in the same way.
        // Convert to 64-bit and use integer truncation rather than UB.
        // See: https://github.com/ldc-developers/ldc/issues/3603
        long timeMs_integer = cast(long)timeMs;
        uint ms = cast(uint)(timeMs_integer);
        return ms;
    }

    override void* systemHandle()
    {
        if (_isHostWindow)
            return _nsWindow.contentView()._id; // return the main NSView
        else
            return _view._id;
    }

    override bool requestResize(int widthLogicalPixels, int heightLogicalPixels, bool alsoResizeParentWindow)
    {
        assert(!alsoResizeParentWindow); // unsupported here
        NSSize size = NSSize(cast(CGFloat)widthLogicalPixels,
                             cast(CGFloat)heightLogicalPixels);
        _view.setFrameSize(size);
        return true;
    }

private:

    MouseState getMouseState(NSEvent event)
    {
        // not working
        MouseState state;
        uint pressedMouseButtons = event.pressedMouseButtons();
        if (pressedMouseButtons & 1)
            state.leftButtonDown = true;
        if (pressedMouseButtons & 2)
            state.rightButtonDown = true;
        if (pressedMouseButtons & 4)
            state.middleButtonDown = true;

        NSEventModifierFlags mod = event.modifierFlags();
        if (mod & NSControlKeyMask)
            state.ctrlPressed = true;
        if (mod & NSShiftKeyMask)
            state.shiftPressed = true;
        if (mod & NSAlternateKeyMask)
            state.altPressed = true;

        return state;
    }

    void handleMouseWheel(NSEvent event)
    {
        double ddeltaX = event.deltaX;
        double ddeltaY = event.deltaY;
        int deltaX = 0;
        int deltaY = 0;
        if (ddeltaX > 0) deltaX = 1;
        if (ddeltaX < 0) deltaX = -1;
        if (ddeltaY > 0) deltaY = 1;
        if (ddeltaY < 0) deltaY = -1;
        if (deltaX || deltaY)
        {
            vec2i mousePos = getMouseXY(_view, event, _height);
            _listener.onMouseWheel(mousePos.x, mousePos.y, deltaX, deltaY, getMouseState(event));
        }
    }

    bool handleKeyEvent(NSEvent event, bool released)
    {
        uint keyCode = event.keyCode();
        Key key;
        switch (keyCode)
        {
            case kVK_ANSI_Keypad0: key = Key.digit0; break;
            case kVK_ANSI_Keypad1: key = Key.digit1; break;
            case kVK_ANSI_Keypad2: key = Key.digit2; break;
            case kVK_ANSI_Keypad3: key = Key.digit3; break;
            case kVK_ANSI_Keypad4: key = Key.digit4; break;
            case kVK_ANSI_Keypad5: key = Key.digit5; break;
            case kVK_ANSI_Keypad6: key = Key.digit6; break;
            case kVK_ANSI_Keypad7: key = Key.digit7; break;
            case kVK_ANSI_Keypad8: key = Key.digit8; break;
            case kVK_ANSI_Keypad9: key = Key.digit9; break;
            case kVK_Return: key = Key.enter; break;
            case kVK_Escape: key = Key.escape; break;
            case kVK_LeftArrow: key = Key.leftArrow; break;
            case kVK_RightArrow: key = Key.rightArrow; break;
            case kVK_DownArrow: key = Key.downArrow; break;
            case kVK_UpArrow: key = Key.upArrow; break;
            case kVK_Delete: key = Key.backspace; break;
            case kVK_ForwardDelete: key = Key.suppr; break;
            default:
            {
                NSString characters = event.charactersIgnoringModifiers();
                if (characters.length() == 0)
                {
                    key = Key.unsupported;
                }
                else
                {
                    wchar ch = characters.characterAtIndex(0);
                    if (ch >= '0' && ch <= '9')
                        key = cast(Key)(Key.digit0 + (ch - '0'));
                    else if (ch >= 'A' && ch <= 'Z')
                        key = cast(Key)(Key.A + (ch - 'A'));
                    else if (ch >= 'a' && ch <= 'z')
                        key = cast(Key)(Key.a + (ch - 'a'));
                    else
                        key = Key.unsupported;
                }
            }
        }

        bool handled = false;

        if (released)
        {
            if (_listener.onKeyDown(key))
                handled = true;
        }
        else
        {
            if (_listener.onKeyUp(key))
                handled = true;
        }

        return handled;
    }

    void handleMouseMove(NSEvent event)
    {
        vec2i mousePos = getMouseXY(_view, event, _height);

        if (_firstMouseMove)
        {
            _firstMouseMove = false;
            _lastMouseX = mousePos.x;
            _lastMouseY = mousePos.y;
        }

        _listener.onMouseMove(mousePos.x, mousePos.y, mousePos.x - _lastMouseX, mousePos.y - _lastMouseY,
            getMouseState(event));

        version(noCursors)
        {}
        else
        {
            setMouseCursor(_listener.getMouseCursor());
        }

        _lastMouseX = mousePos.x;
        _lastMouseY = mousePos.y;
    }

    void handleMouseEntered(NSEvent event)
    {
        // Welcome to Issue #737.
        //
        // Consider the mouse cursor has changed, since the mouse was elsewhere.
        // Give it an impossible mouse cursor cached value.
        _lastMouseCursor = cast(MouseCursor) -1;

        // Furthermore, because:
        // 1. either the cursor might not be set by subsequent
        // 2. either the mouseMove event might not be called, because the window is hosted in another process
        //    and isn't active yet (macOS has "click through", a sort of mouse focus)
        // then we need to set the mouse cursor upon entry. Tricky!
        version(noCursors)
        {
            setMouseCursor(MouseCursor.pointer);
        }
        else
        {
            setMouseCursor(_listener.getMouseCursor());
        }
    }

    void handleMouseClicks(NSEvent event, MouseButton mb, bool released)
    {
        vec2i mousePos = getMouseXY(_view, event, _height);

        if (released)
            _listener.onMouseRelease(mousePos.x, mousePos.y, mb, getMouseState(event));
        else
        {
            // Fix Issue #281
            // This resets _lastMouseX and _lastMouseY on new clicks,
            // necessary if the focus was lost for a while.
            _firstMouseMove = true;

            int clickCount = event.clickCount();
            bool isDoubleClick = clickCount >= 2;
            _listener.onMouseClick(mousePos.x, mousePos.y, mb, isDoubleClick, getMouseState(event));
        }
    }

    void layout()
    {
        // Updates internal buffers in case of startup/resize
        {
            NSRect frameRect = _view.frame();
            // Note: even if the frame rect is wrong, we can support any internal size with cropping etc.
            // TODO: is it really wrong though?
            int width = cast(int)(frameRect.size.width);   // truncating down the dimensions of bounds
            int height = cast(int)(frameRect.size.height);
            updateSizeIfNeeded(width, height);
        }
    }

    void viewWillDraw()
    {
        if (_drawRectWorkaround)
        {
            CALayer layer = _view.layer();

            if (layer)
            {
                // On Big Sur this is technically a no-op, but that reverts the drawRect behaviour!
                // This workaround is sanctionned by Apple: https://gist.github.com/lukaskubanek/9a61ac71dc0db8bb04db2028f2635779#gistcomment-3901461
                layer.setContentsFormat(kCAContentsFormatRGBA8Uint);
            }
        }
    }

    void drawRect(NSRect rect)
    {
        NSGraphicsContext nsContext = NSGraphicsContext.currentContext();

        // The first drawRect callback occurs before the timer triggers.
        // But because recomputeDirtyAreas() wasn't called before there is nothing to draw.
        // Hence, do it.
        if (_dirtyAreasAreNotYetComputed)
        {
            _dirtyAreasAreNotYetComputed = false;
            _listener.recomputeDirtyAreas();
        }

        _listener.onDraw(WindowPixelFormat.ARGB8);

        version(useCoreGraphicsContext)
        {
            CGContextRef cgContext = nsContext.getCGContext();

            enum bool fullDraw = false;

            //import core.stdc.stdio;
            //printf("drawRect: _wfb WxH = %dx%d\n", _wfb.w, _wfb.h);
            //printf("          width = %d  height = %d\n", _width, _height);
            //printf("          rect = %f %f %f %f\n",
            //    rect.origin.x,
            //    rect.origin.y,
            //    rect.origin.x+rect.size.width,
            //    rect.origin.y+rect.size.height);

            // Some combinations, like Studio One 7 + CLAP, send an
            // invalid rect first (say: -1,0 580x500 instead of
            // 0,0 500x500).
            // However subsequent code can deal with it. I'm warey of the
            // optimizer removing the workaround for the condition we
            // asserted on!
            //assert(_wfb.w == _width);
            //assert(_wfb.h == _height);
            //assert(_wfb.w >= cast(int)(rect.origin.x+rect.size.width));
            //assert(_wfb.h >= cast(int)(rect.origin.y+rect.size.height));

            static if (fullDraw)
            {
                size_t sizeNeeded = _wfb.pitch * _wfb.h;
                size_t bytesPerRow = _wfb.pitch;

                CGDataProviderRef provider = CGDataProviderCreateWithData(null, _wfb.pixels, sizeNeeded, null);
                CGImageRef image = CGImageCreate(_width,
                                                 _height,
                                                 8,
                                                 32,
                                                 bytesPerRow,
                                                 _cgColorSpaceRef,
                                                 kCGImageByteOrderDefault | kCGImageAlphaNoneSkipFirst,
                                                 provider,
                                                 null,
                                                 true,
                                                 kCGRenderingIntentDefault);
                // "on return, you may safely release [the provider]"
                CGDataProviderRelease(provider);
                scope(exit) CGImageRelease(image);
                CGRect fullRect = CGMakeRect(0, 0, _width, _height);
                CGContextDrawImage(cgContext, fullRect, image);
            }
            else
            {
                /// rect can be outside frame and needs clipping.
                ///              
                /// "Some patterns that have historically worked will require adjustment:
                ///  Filling the dirty rect of a view inside of -drawRect. A fairly common
                ///  pattern is to simply rect fill the dirty rect passed into an override
                ///  of NSView.draw(). The dirty rect can now extend outside of your view's
                ///  bounds. This pattern can be adjusted by filling the bounds instead of
                ///  the dirty rect, or by setting clipsToBounds = true.
                ///  Confusing a view’s bounds and its dirty rect. The dirty rect passed to .drawRect()
                ///  should be used to determine what to draw, not where to draw it. Use NSView.bounds
                ///  when determining the layout of what your view draws." (10905750)
                ///
                /// Thus is the story of Issue #835 (and afterwards, Issue #885)

                int rectOrigX = cast(int)rect.origin.x;
                int rectOrigY = cast(int)rect.origin.y;
                int rectWidth = cast(int)rect.size.width;
                int rectHeight = cast(int)rect.size.height;

                box2i dirtyRect = box2i.rectangle(rectOrigX, rectOrigY, rectWidth, rectHeight);
                box2i bounds = box2i(0, 0, _width, _height);

                // clip dirtyRect to bounds
                // it CAN be made empty with energetic resizing, the
                // base offset might already be outside a window that
                // is shrinking
                box2i clipped = dirtyRect.intersection(bounds);
                if (!clipped.empty)
                {
                    int clippedOrigX = clipped.min.x;
                    int clippedOrigY = clipped.min.y;
                    int clippedWidth  = clipped.width;
                    int clippedHeight = clipped.height;

                    int ysource = -clippedOrigY + _height - clippedHeight;

                    assert(ysource >= 0);
                    assert(ysource < _height);

                    const (RGBA)* firstPixel = &(_wfb.scanline(ysource)[clippedOrigX]);
                    size_t sizeNeeded = _wfb.pitch * clippedHeight;
                    size_t bytesPerRow = _wfb.pitch;

                    CGDataProviderRef provider = CGDataProviderCreateWithData(null, firstPixel, sizeNeeded, null);

                    CGImageRef image = CGImageCreate(clippedWidth,
                                                     clippedHeight,
                                                     8,
                                                     32,
                                                     bytesPerRow,
                                                     _cgColorSpaceRef,
                                                     kCGImageByteOrderDefault | kCGImageAlphaNoneSkipFirst,
                                                     provider,
                                                     null,
                                                     true,
                                                     kCGRenderingIntentDefault);
                    // "on return, you may safely release [the provider]"
                    CGDataProviderRelease(provider);
                    scope(exit) CGImageRelease(image);

                    CGRect clippedDirtyRect = CGMakeRect(clippedOrigX, clippedOrigY, clippedWidth, clippedHeight);
                    CGContextDrawImage(cgContext, clippedDirtyRect, image);
                }
            }
        }
        else
        {
            size_t sizeNeeded = _wfb.pitch * _wfb.h;
            size_t bytesPerRow = _wfb.pitch;
            CIContext ciContext = nsContext.getCIContext();
            _imageData = NSData.dataWithBytesNoCopy(_wfb.pixels, sizeNeeded, false);

            CIImage image = CIImage.imageWithBitmapData(_imageData,
                                                        bytesPerRow,
                                                        CGSize(_width, _height),
                                                        kCIFormatARGB8,
                                                        _cgColorSpaceRef);
            ciContext.drawImage(image, rect, rect);
        }
    }

    /// Returns: true if window size changed.
    bool updateSizeIfNeeded(int newWidth, int newHeight)
    {
        // only do something if the client size has changed
        if ( (newWidth != _width) || (newHeight != _height) )
        {
            _width = newWidth;
            _height = newHeight;
            _wfb = _listener.onResized(_width, _height);
            return true;
        }
        else
            return false;
    }

    void doAnimation()
    {
        uint now = getTimeMs();
        double dt = (now - _lastMeasturedTimeInMs) * 0.001;
        double time = (now - _timeAtCreationInMs) * 0.001; // hopefully no plug-in will be open more than 49 days
        _lastMeasturedTimeInMs = now;
        _listener.onAnimate(dt, time);
    }

    void onTimer()
    {
        // Deal with animation
        doAnimation();

        _listener.recomputeDirtyAreas();
        _dirtyAreasAreNotYetComputed = false;
        box2i dirtyRect = _listener.getDirtyRectangle();
        if (!dirtyRect.empty())
        {

            NSRect boundsRect = _view.bounds();
            int height = cast(int)(boundsRect.size.height);
            NSRect r = NSMakeRect(dirtyRect.min.x,
                                    height - dirtyRect.min.y - dirtyRect.height,
                                    dirtyRect.width,
                                    dirtyRect.height);
            _view.setNeedsDisplayInRect(r);
        }
    }

    void setMouseCursor(MouseCursor dplugCursor)
    {
        if(dplugCursor != _lastMouseCursor)
        {
            if(dplugCursor == MouseCursor.hidden)
            {
                NSCursor.hide();
            }
            else
            {
                if(_lastMouseCursor == MouseCursor.hidden)
                {
                    NSCursor.unhide();
                }

                NSCursor.pop();
                NSCursor nsCursor;
                switch(dplugCursor)
                {
                    case MouseCursor.linkSelect:
                        nsCursor = NSCursor.pointingHandCursor();
                        break;
                    case MouseCursor.drag:
                        nsCursor = NSCursor.crosshairCursor();
                        break;
                    case MouseCursor.move:
                        nsCursor = NSCursor.openHandCursor();
                        break;
                    case MouseCursor.verticalResize:
                        nsCursor = NSCursor.resizeUpDownCursor();
                        break;
                    case MouseCursor.horizontalResize:
                        nsCursor = NSCursor.resizeLeftRightCursor();
                        break;
                    case MouseCursor.diagonalResize:
                        nsCursor = NSCursor.crosshairCursor(); // macOS doesn't seem to have this
                        break;
                    case MouseCursor.pointer:
                    default:
                        nsCursor = NSCursor.arrowCursor();
                }
                nsCursor.push();
            }

            _lastMouseCursor = dplugCursor;
        }
    }
}

struct DPlugCustomView
{
public:
nothrow:
@nogc:

    NSView parent;
    alias parent this;

    // create from an id
    this (id id_)
    {
        this._id = id_;
    }

    /// Allocates, but do not init
    static DPlugCustomView alloc()
    {
        alias fun_t = extern(C) id function (id obj, SEL sel) nothrow @nogc;
        return DPlugCustomView( (cast(fun_t)objc_msgSend)(getClassID(), sel!"alloc") );
    }

    static Class getClass()
    {
        return cast(Class)( getClassID() );
    }

    static id getClassID()
    {
        return objc_getClass(customClassName.ptr);
    }

    // This class uses a unique class name for each plugin instance
    static __gshared char[16 + 36 + 1] customClassName;

    static void generateClassName() nothrow @nogc
    {
        generateNullTerminatedRandomUUID!char(customClassName, "DPlugCustomView_");
    }

private:

    CocoaWindow _window;
    NSTimer _timer = null;
    NSString _runLoopMode;
    NSTrackingArea _trackingArea;

    void initialize(CocoaWindow window, int width, int height)
    {
        // Warning: taking this address is fishy since DPlugCustomView is a struct and thus could be copied
        // we rely on the fact it won't :|
        void* thisPointer = cast(void*)(&this);
        object_setInstanceVariable(_id, "this", thisPointer);

        this._window = window;

        NSRect r = NSRect(NSPoint(0, 0), NSSize(width, height));
        initWithFrame(r);

        _timer = NSTimer.timerWithTimeInterval(1 / 60.0, this, sel!"onTimer:", null, true);
        _runLoopMode = NSString.stringWith("kCFRunLoopCommonModes"w);
        NSRunLoop.currentRunLoop().addTimer(_timer, _runLoopMode);
    }

    static __gshared Class clazz;

    static void registerSubclass()
    {
        clazz = objc_allocateClassPair(cast(Class) lazyClass!"NSView", customClassName.ptr, 0);

        class_addMethod(clazz, sel!"keyDown:", cast(IMP) &keyDown, "v@:@");
        class_addMethod(clazz, sel!"keyUp:", cast(IMP) &keyUp, "v@:@");
        class_addMethod(clazz, sel!"mouseDown:", cast(IMP) &mouseDown, "v@:@");
        class_addMethod(clazz, sel!"mouseUp:", cast(IMP) &mouseUp, "v@:@");
        class_addMethod(clazz, sel!"rightMouseDown:", cast(IMP) &rightMouseDown, "v@:@");
        class_addMethod(clazz, sel!"rightMouseUp:", cast(IMP) &rightMouseUp, "v@:@");
        class_addMethod(clazz, sel!"otherMouseDown:", cast(IMP) &otherMouseDown, "v@:@");
        class_addMethod(clazz, sel!"otherMouseUp:", cast(IMP) &otherMouseUp, "v@:@");
        class_addMethod(clazz, sel!"mouseMoved:", cast(IMP) &mouseMoved, "v@:@");
        class_addMethod(clazz, sel!"mouseDragged:", cast(IMP) &mouseMoved, "v@:@");
        class_addMethod(clazz, sel!"rightMouseDragged:", cast(IMP) &mouseMoved, "v@:@");
        class_addMethod(clazz, sel!"otherMouseDragged:", cast(IMP) &mouseMoved, "v@:@");
        class_addMethod(clazz, sel!"acceptsFirstResponder", cast(IMP) &acceptsFirstResponder, "b@:");
        class_addMethod(clazz, sel!"isOpaque", cast(IMP) &isOpaque, "b@:");
        class_addMethod(clazz, sel!"acceptsFirstMouse:", cast(IMP) &acceptsFirstMouse, "b@:@");
        class_addMethod(clazz, sel!"viewDidMoveToWindow", cast(IMP) &viewDidMoveToWindow, "v@:");
        class_addMethod(clazz, sel!"layout", cast(IMP) &layout, "v@:");
        class_addMethod(clazz, sel!"drawRect:", cast(IMP) &drawRect, "v@:" ~ encode!NSRect);
        class_addMethod(clazz, sel!"onTimer:", cast(IMP) &onTimer, "v@:@");
        class_addMethod(clazz, sel!"viewWillDraw", cast(IMP) &viewWillDraw, "v@:");

        class_addMethod(clazz, sel!"mouseEntered:", cast(IMP) &mouseEntered, "v@:@");
        class_addMethod(clazz, sel!"mouseExited:", cast(IMP) &mouseExited, "v@:@");
        class_addMethod(clazz, sel!"updateTrackingAreas", cast(IMP)&updateTrackingAreas, "v@:");

        // This ~ is to avoid a strange DMD ICE. Didn't succeed in isolating it.
        class_addMethod(clazz, sel!("scroll" ~ "Wheel:") , cast(IMP) &scrollWheel, "v@:@");

        // very important: add an instance variable for the this pointer so that the D object can be
        // retrieved from an id
        class_addIvar(clazz, "this", (void*).sizeof, (void*).sizeof == 4 ? 2 : 3, "^v");

        objc_registerClassPair(clazz);
    }

    static void unregisterSubclass()
    {
        // For some reason the class need to continue to exist, so we leak it
        //  objc_disposeClassPair(clazz);
        // TODO: remove this crap
    }

    void killTimer()
    {
        if (_timer)
        {
            _timer.invalidate();
            _timer = NSTimer(null);
        }
    }
}

DPlugCustomView getInstance(id anId) nothrow @nogc
{
    // strange thing: object_getInstanceVariable definition is odd (void**)
    // and only works for pointer-sized values says SO
    void* thisPointer = null;
    Ivar var = object_getInstanceVariable(anId, "this", &thisPointer);
    assert(var !is null);
    assert(thisPointer !is null);
    return *cast(DPlugCustomView*)thisPointer;
}

vec2i getMouseXY(NSView view, NSEvent event, int windowHeight) nothrow @nogc
{
    NSPoint mouseLocation = event.locationInWindow();
    mouseLocation = view.convertPoint(mouseLocation, NSView(null));
    int px = cast(int)(mouseLocation.x) - 2;
    int py = windowHeight - cast(int)(mouseLocation.y) - 3;
    return vec2i(px, py);
}



alias CocoaScopedCallback = ScopedForeignCallback!(true, true);

// Overridden function gets called with an id, instead of the self pointer.
// So we have to get back the D class object address.
// Big thanks to Mike Ash (@macdev)
// MAYDO: why are these methods members???
extern(C)
{
    void keyDown(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        bool handled = view._window.handleKeyEvent(NSEvent(event), false);

        // send event to superclass if event not handled
        if (!handled)
        {
            objc_super sup;
            sup.receiver = self;
            sup.clazz = cast(Class) lazyClass!"NSView";
            alias fun_t = extern(C) void function (objc_super*, SEL, id) nothrow @nogc;
            (cast(fun_t)objc_msgSendSuper)(&sup, selector, event);
        }
    }

    void keyUp(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.handleKeyEvent(NSEvent(event), true);
    }

    void mouseDown(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.handleMouseClicks(NSEvent(event), MouseButton.left, false);
    }

    void mouseUp(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.handleMouseClicks(NSEvent(event), MouseButton.left, true);
    }

    void rightMouseDown(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.handleMouseClicks(NSEvent(event), MouseButton.right, false);
    }

    void rightMouseUp(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.handleMouseClicks(NSEvent(event), MouseButton.right, true);
    }

    void otherMouseDown(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        auto nsEvent = NSEvent(event);
        if (nsEvent.buttonNumber == 2)
            view._window.handleMouseClicks(nsEvent, MouseButton.middle, false);
    }

    void otherMouseUp(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        auto nsEvent = NSEvent(event);
        if (nsEvent.buttonNumber == 2)
            view._window.handleMouseClicks(nsEvent, MouseButton.middle, true);
    }

    void mouseMoved(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.handleMouseMove(NSEvent(event));
    }

    void mouseEntered(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();
        DPlugCustomView view = getInstance(self);
        view._window.handleMouseEntered(NSEvent(event));
    }

    void mouseExited(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();
        DPlugCustomView view = getInstance(self);
        view._window._listener.onMouseExitedWindow();
    }

    void updateTrackingAreas(id self, SEL selector) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        // Call superclass's updateTrackingAreas:, equivalent to [super updateTrackingAreas];
        {
            objc_super sup;
            sup.receiver = self;
            sup.clazz = cast(Class) lazyClass!"NSView";
            alias fun_t = extern(C) void function (objc_super*, SEL) nothrow @nogc;
            (cast(fun_t)objc_msgSendSuper)(&sup, selector);
        }

        DPlugCustomView view = getInstance(self);

        // Remove an existing tracking area, if any.
        if (view._trackingArea._id !is null)
        {
            view.removeTrackingArea(view._trackingArea);
            view._trackingArea.release();
            view._trackingArea._id = null;
        }

        // This is needed to get mouseEntered and mouseExited
        int opts = (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways);

        NSRect bounds = view.bounds();
        view._trackingArea = NSTrackingArea.alloc();
        view._trackingArea.initWithRect(bounds, opts, view, null);
        view.addTrackingArea(view._trackingArea);
    }


    void scrollWheel(id self, SEL selector, id event) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();
        DPlugCustomView view = getInstance(self);
        view._window.handleMouseWheel(NSEvent(event));
    }

    bool acceptsFirstResponder(id self, SEL selector) nothrow @nogc
    {
        return YES;
    }

    bool acceptsFirstMouse(id self, SEL selector, id pEvent) nothrow @nogc
    {
        return YES;
    }

    bool isOpaque(id self, SEL selector) nothrow @nogc
    {
        return NO; // Since with the #835 issue, doesn't cover all the dirt rect but only the part intersecting bounds.
    }

    // Since 10.7, called on resize.
    void layout(id self, SEL selector) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.layout();

        // Call superclass's layout:, equivalent to [super layout];
        {
            objc_super sup;
            sup.receiver = self;
            sup.clazz = cast(Class) lazyClass!"NSView";
            alias fun_t = extern(C) void function (objc_super*, SEL) nothrow @nogc;
            (cast(fun_t)objc_msgSendSuper)(&sup, selector);
        }
    }

    // Necessary for the Big Sur drawRect: fuckup
    // See Issue #505.
    void viewWillDraw(id self, SEL selector) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.viewWillDraw();

        // Call superclass's layout:, equivalent to [super viewWillDraw];
        {
            objc_super sup;
            sup.receiver = self;
            sup.clazz = cast(Class) lazyClass!"NSView";
            alias fun_t = extern(C) void function (objc_super*, SEL) nothrow @nogc;
            (cast(fun_t)objc_msgSendSuper)(&sup, selector);
        }
    }

    void viewDidMoveToWindow(id self, SEL selector) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        NSWindow parentWindow = view.window();
        if (parentWindow)
        {
            parentWindow.makeFirstResponder(view);
            parentWindow.setAcceptsMouseMovedEvents(true);
        }
    }

    void drawRect(id self, SEL selector, NSRect rect) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.drawRect(rect);
    }

    void onTimer(id self, SEL selector, id timer) nothrow @nogc
    {
        CocoaScopedCallback scopedCallback;
        scopedCallback.enter();

        DPlugCustomView view = getInstance(self);
        view._window.onTimer();
    }
}
