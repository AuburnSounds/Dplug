/**
* Carbon window implementation.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.carbonwindow;

import core.stdc.stdio;
import core.stdc.stdlib;

import std.string;
import std.math;

import derelict.carbon;

import gfm.math.vector;
import gfm.math.box;
import dplug.graphics.image;
import dplug.graphics.view;

import dplug.core.runtime;
import dplug.core.nogc;
import dplug.window.window;


final class CarbonWindow : IWindow
{
nothrow:
@nogc:
private:
    IWindowListener _listener;
    bool _terminated = false;
    bool _isComposited;
    ControlRef _view = null;
    WindowRef _window;
    EventHandlerRef _controlHandler = null;
    EventHandlerRef _windowHandler = null;
    EventLoopTimerRef _timer = null;

    CGColorSpaceRef _colorSpace = null;
    CGDataProviderRef _dataProvider = null;

    // Rendered frame buffer
    ImageRef!RGBA _wfb;

    int _width = 0;
    int _height = 0;
    int _askedWidth;
    int _askedHeight;
    uint _timeAtCreationInMs;
    uint _lastMeasturedTimeInMs;
    long _ticksPerSecond;

    bool _dirtyAreasAreNotYetComputed = true; // TODO: could have a race on this if timer thread != draw thread
    bool _firstMouseMove = true;

    int _lastMouseX;
    int _lastMouseY;

public:
    this(WindowUsage usage, void* parentWindow, void* parentControl, IWindowListener listener, int width, int height)
    {
        // Carbon doesn't support the host window case.
        assert(usage == WindowUsage.plugin);

        _ticksPerSecond = machTicksPerSecond();
        _listener = listener;

        acquireCarbonFunctions();
        acquireCoreFoundationFunctions();
        acquireCoreServicesFunctions();
        acquireCoreGraphicsFunctions();

        _askedWidth = width;
        _askedHeight = height;

        _window = cast(WindowRef)(parentWindow);
        WindowAttributes winAttrs = 0;
        GetWindowAttributes(_window, &winAttrs);
        _isComposited = (winAttrs & kWindowCompositingAttribute) != 0;

        UInt32 features =  kControlSupportsFocus | kControlHandlesTracking | kControlSupportsEmbedding;
        if (_isComposited)
            features |= kHIViewFeatureIsOpaque | kHIViewFeatureDoesNotUseSpecialParts;

        Rect r;
        r.left = 0;
        r.top = 0;
        r.right = cast(short)width;
        r.bottom = cast(short)height;

        CreateUserPaneControl(_window, &r, features, &_view);

        static immutable EventTypeSpec[] controlEvents =
        [
            EventTypeSpec(kEventClassControl, kEventControlDraw)
        ];

        InstallControlEventHandler(_view, &eventCallback, controlEvents.length, controlEvents.ptr, cast(void*)this, &_controlHandler);

        static immutable EventTypeSpec[] windowEvents =
        [
            EventTypeSpec(kEventClassMouse, kEventMouseUp),
            EventTypeSpec(kEventClassMouse, kEventMouseDown),
            EventTypeSpec(kEventClassMouse, kEventMouseMoved),
            EventTypeSpec(kEventClassMouse, kEventMouseDragged),
            EventTypeSpec(kEventClassMouse, kEventMouseWheelMoved),
            EventTypeSpec(kEventClassKeyboard, kEventRawKeyDown),
            EventTypeSpec(kEventClassKeyboard, kEventRawKeyUp)
        ];

        InstallWindowEventHandler(_window, &eventCallback, windowEvents.length, windowEvents.ptr, cast(void*)this, &_windowHandler);

        OSStatus s = InstallEventLoopTimer(GetMainEventLoop(), 0.0, kEventDurationSecond / 60.0,
                                            &timerCallback, cast(void*)this, &_timer);

        // AU pass something, but VST does not.
        ControlRef parentControlRef = cast(void*)parentControl;

        OSStatus status;
        if (_isComposited)
        {
            if (!parentControlRef)
            {
                HIViewRef hvRoot = HIViewGetRoot(_window);
                status = HIViewFindByID(hvRoot, kHIViewWindowContentID, &parentControlRef);
            }

            status = HIViewAddSubview(parentControlRef, _view);
        }
        else
        {
            // MAYDO
            /*if (!parentControlRef)
            {
                if (GetRootControl(_window, &parentControlRef) != noErr)
                {
                    CreateRootControl(_window, &parentControlRef);
                }
            }
            status = EmbedControl(_view, parentControlRef);
            */
            assert(false);
        }

        if (status == noErr)
            SizeControl(_view, r.right, r.bottom);  // offset?

        static immutable string colorSpaceName = "kCGColorSpaceSRGB";
        CFStringRef str = CFStringCreateWithCString(null, colorSpaceName.ptr, kCFStringEncodingUTF8);
        _colorSpace = CGColorSpaceCreateWithName(str);

        // TODO: release str which is leaking right now

        _lastMeasturedTimeInMs = _timeAtCreationInMs = getTimeMs();
    }

    void clearDataProvider()
    {
        if (_dataProvider != null)
        {
            CGDataProviderRelease(_dataProvider);
            _dataProvider = null;
        }
    }

    ~this()
    {
       _terminated = true;

        clearDataProvider();

        CGColorSpaceRelease(_colorSpace);

        RemoveEventLoopTimer(_timer);
        RemoveEventHandler(_controlHandler);
        RemoveEventHandler(_windowHandler);

        releaseCarbonFunctions();
        releaseCoreFoundationFunctions();
        releaseCoreServicesFunctions();
        releaseCoreGraphicsFunctions();
    }


    // IWindow implmentation
    override void waitEventAndDispatch()
    {
        assert(false); // Unimplemented, FUTURE
    }

    // If exit was requested
    override bool terminated()
    {
        return _terminated;
    }

    override uint getTimeMs()
    {
        import core.time: convClockFreq;
        long ticks = cast(long)mach_absolute_time();
        long msecs = convClockFreq(ticks, _ticksPerSecond, 1_000);
        return cast(uint)msecs;
    }

    override void* systemHandle()
    {
        return _view;
    }

private:

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
                CGRect rect = CGRectMake(dirtyRect.min.x, dirtyRect.min.y, dirtyRect.width, dirtyRect.height);

                // invalidate everything that is set dirty
                HIViewSetNeedsDisplayInRect(_view, &rect , true);
        }
    }

    vec2i getMouseXY(EventRef pEvent)
    {
        // Get mouse position
        HIPoint mousePos;
        GetEventParameter(pEvent, kEventParamWindowMouseLocation, typeHIPoint, null, HIPoint.sizeof, null, &mousePos);
        HIPointConvert(&mousePos, kHICoordSpaceWindow, _window, kHICoordSpaceView, _view);
        return vec2i(cast(int) round(mousePos.x - 2),
                        cast(int) round(mousePos.y - 3) );
    }

    MouseState getMouseState(EventRef pEvent)
    {
        UInt32 mods;
        GetEventParameter(pEvent, kEventParamKeyModifiers, typeUInt32, null, UInt32.sizeof, null, &mods);

        MouseState state;
        if (mods & btnState)
            state.leftButtonDown = true;
        if (mods & controlKey)
            state.ctrlPressed = true;
        if (mods & shiftKey)
            state.shiftPressed = true;
        if (mods & optionKey)
            state.altPressed = true;

        return state;
    }

    bool handleEvent(EventRef pEvent)
    {
        UInt32 eventClass = GetEventClass(pEvent);
        UInt32 eventKind = GetEventKind(pEvent);

        switch(eventClass)
        {
            case kEventClassControl:
            {
                switch(eventKind)
                {
                    case kEventControlDraw:
                    {
                        // FUTURE: why is the bounds rect too large? It creates havoc in AU even without resizing.
                        /*HIRect bounds;
                        HIViewGetBounds(_view, &bounds);
                        int newWidth = cast(int)(0.5f + bounds.size.width);
                        int newHeight = cast(int)(0.5f + bounds.size.height);
                        */
                        int newWidth = _askedWidth; // In reaper, excess space is provided, leading in a crash
                        int newHeight = _askedHeight; // fix size until we have resizeable UI
                        updateSizeIfNeeded(newWidth, newHeight);


                        if (_dirtyAreasAreNotYetComputed)
                        {
                            _dirtyAreasAreNotYetComputed = false;
                            _listener.recomputeDirtyAreas();
                        }

                        // Redraw dirty UI
                        _listener.onDraw(WindowPixelFormat.RGBA8);

                        if (_isComposited)
                        {
                            CGContextRef contextRef;

                            // Get the CGContext
                            GetEventParameter(pEvent, kEventParamCGContextRef, typeCGContextRef,
                                                null, CGContextRef.sizeof, null, &contextRef);

                            // Flip things vertically
                            CGContextTranslateCTM(contextRef, 0, _height);
                            CGContextScaleCTM(contextRef, 1.0f, -1.0f);

                            CGRect wholeRect = CGRect(CGPoint(0, 0), CGSize(_width, _height));

                            // See: http://stackoverflow.com/questions/2261177/cgimage-from-byte-array
                            // Recreating this image looks necessary
                            CGImageRef image = CGImageCreate(_width, _height, 8, 32, byteStride(_width), _colorSpace,
                                                                kCGBitmapByteOrderDefault, _dataProvider, null, false,
                                                                kCGRenderingIntentDefault);

                            CGContextDrawImage(contextRef, wholeRect, image);

                            CGImageRelease(image);
                        }
                        else
                        {
                            // MAYDO
                        }
                        return true;
                    }

                    default:
                        return false;
                }
            }

            case kEventClassKeyboard:
            {
                switch(eventKind)
                {
                    case kEventRawKeyDown:
                    case kEventRawKeyUp:
                    {
                        UInt32 k;
                        GetEventParameter(pEvent, kEventParamKeyCode, typeUInt32, null, UInt32.sizeof, null, &k);

                        char ch;
                        GetEventParameter(pEvent, kEventParamKeyMacCharCodes, typeChar, null, char.sizeof, null, &ch);

                        Key key;

                        switch(k)
                        {
                            case 125: key = Key.downArrow; break;
                            case 126: key = Key.upArrow; break;
                            case 123: key = Key.leftArrow; break;
                            case 124: key = Key.rightArrow; break;
                            case 0x35: key = Key.escape; break;
                            case 0x24: key = Key.enter; break;
                            case 0x52: key = Key.digit0; break;
                            case 0x53: key = Key.digit1; break;
                            case 0x54: key = Key.digit2; break;
                            case 0x55: key = Key.digit3; break;
                            case 0x56: key = Key.digit4; break;
                            case 0x57: key = Key.digit5; break;
                            case 0x58: key = Key.digit6; break;
                            case 0x59: key = Key.digit7; break;
                            case 0x5B: key = Key.digit8; break;
                            case 0x5C: key = Key.digit9; break;
                            case 51:   key = Key.backspace; break;

                            default:
                            {
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

                        bool handled = false;

                        if (eventKind == kEventRawKeyDown)
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

                    default:
                        return false;
                }
            }

            case kEventClassMouse:
            {
                switch(eventKind)
                {
                    case kEventMouseUp:
                    case kEventMouseDown:
                    {
                        vec2i mousePos = getMouseXY(pEvent);

                        // Get which button was pressed
                        MouseButton mb;
                        EventMouseButton button;
                        GetEventParameter(pEvent, kEventParamMouseButton, typeMouseButton, null, EventMouseButton.sizeof, null, &button);
                        switch(button)
                        {
                            case kEventMouseButtonPrimary:
                                mb = MouseButton.left;
                                break;
                            case kEventMouseButtonSecondary:
                                mb = MouseButton.right;
                                break;
                            case kEventMouseButtonTertiary:
                                mb = MouseButton.middle;
                                break;
                            default:
                                return false;
                        }

                        if (eventKind == kEventMouseDown)
                        {
                            UInt32 clickCount = 0;
                            GetEventParameter(pEvent, kEventParamClickCount, typeUInt32, null, UInt32.sizeof, null, &clickCount);
                            bool isDoubleClick = clickCount > 1;
                            _listener.onMouseClick(mousePos.x, mousePos.y, mb, isDoubleClick, getMouseState(pEvent));
                        }
                        else
                        {
                            _listener.onMouseRelease(mousePos.x, mousePos.y, mb, getMouseState(pEvent));
                        }
                        return false;
                    }

                    case kEventMouseMoved:
                    case kEventMouseDragged:
                    {
                        vec2i mousePos = getMouseXY(pEvent);

                        if (_firstMouseMove)
                        {
                            _firstMouseMove = false;
                            _lastMouseX = mousePos.x;
                            _lastMouseY = mousePos.y;
                        }

                        _listener.onMouseMove(mousePos.x, mousePos.y,
                                                mousePos.x - _lastMouseX, mousePos.y - _lastMouseY,
                                                getMouseState(pEvent));

                        _lastMouseX = mousePos.x;
                        _lastMouseY = mousePos.y;
                        return true;
                    }

                    case kEventMouseWheelMoved:
                    {
                        EventMouseWheelAxis axis;
                        GetEventParameter(pEvent, kEventParamMouseWheelAxis, typeMouseWheelAxis, null, EventMouseWheelAxis.sizeof, null, &axis);

                        if (axis == kEventMouseWheelAxisY)
                        {
                            int d;
                            GetEventParameter(pEvent, kEventParamMouseWheelDelta, typeSInt32, null, SInt32.sizeof, null, &d);
                            vec2i mousePos = getMouseXY(pEvent);
                            _listener.onMouseWheel(mousePos.x, mousePos.y, 0, d, getMouseState(pEvent));
                            return true;
                        }

                        return false;
                    }

                    default:
                        return false;
                }
            }

            default:
                return false;
        }
    }

    enum scanLineAlignment = 4; // could be anything

    // given a width, how long in bytes should scanlines be
    int byteStride(int width)
    {
        int widthInBytes = width * 4;
        return (widthInBytes + (scanLineAlignment - 1)) & ~(scanLineAlignment-1);
    }

    /// Returns: true if window size changed.
    bool updateSizeIfNeeded(int newWidth, int newHeight)
    {
        // only do something if the client size has changed
        if ( (newWidth != _width) || (newHeight != _height) )
        {
            // Extends buffer
            clearDataProvider();

            _width = newWidth;
            _height = newHeight;
            _wfb = _listener.onResized(_width, _height);

            // Create a new data provider
            _dataProvider = CGDataProviderCreateWithData(null, _wfb.pixels, cast(int)(_wfb.pitch) * _wfb.h, null);
            return true;
        }
        else
            return false;
    }
}

alias CarbonScopedCallback = ScopedForeignCallback!(true, true);

extern(C) OSStatus eventCallback(EventHandlerCallRef pHandlerCall, EventRef pEvent, void* user) nothrow @nogc
{
    CarbonScopedCallback scopedCallback;
    scopedCallback.enter();
    CarbonWindow window = cast(CarbonWindow)user;
    bool handled = window.handleEvent(pEvent);
    return handled ? noErr : eventNotHandledErr;
}

extern(C) void timerCallback(EventLoopTimerRef pTimer, void* user) nothrow @nogc
{
    CarbonScopedCallback scopedCallback;
    scopedCallback.enter();
    CarbonWindow window = cast(CarbonWindow)user;
    window.onTimer();
}


version(OSX)
{
    extern(C) nothrow @nogc
    {
        struct mach_timebase_info_data_t
        {
            uint numer;
            uint denom;
        }
        alias mach_timebase_info_data_t* mach_timebase_info_t;
        alias kern_return_t = int;
        kern_return_t mach_timebase_info(mach_timebase_info_t);
        ulong mach_absolute_time();
    }

    long machTicksPerSecond() nothrow @nogc
    {
        // Be optimistic that ticksPerSecond (1e9*denom/numer) is integral. So far
        // so good on Darwin based platforms OS X, iOS.
        import core.internal.abort : abort;
        mach_timebase_info_data_t info;
        if(mach_timebase_info(&info) != 0)
            assert(false);

        long scaledDenom = 1_000_000_000L * info.denom;
        if(scaledDenom % info.numer != 0)
            assert(false);
        return scaledDenom / info.numer;
    }
}
else
{
    ulong mach_absolute_time() nothrow @nogc
    {
        return 0;
    }

    long machTicksPerSecond() nothrow @nogc
    {
        return 0;
    }
}