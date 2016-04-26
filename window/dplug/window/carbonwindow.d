/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.carbonwindow;

version(OSX)
{
    import core.stdc.stdio;
    import std.string;
    import std.math;

    import derelict.carbon;

    import ae.utils.graphics;

    import gfm.core;
    import gfm.math;

    import dplug.core.fpcontrol;
    import dplug.window.window;



    final class CarbonWindow : IWindow
    {
    private:
        IWindowListener _listener;
        bool _terminated = false;
        bool _initialized = true;
        bool _isComposited;
        ControlRef _view = null;
        WindowRef _window;
        EventHandlerRef _controlHandler = null;
        EventHandlerRef _windowHandler = null;
        EventLoopTimerRef _timer = null;

        CGColorSpaceRef _colorSpace = null;
        CGDataProviderRef _dataProvider = null;

        ubyte* _buffer = null;

        int _width = 0;
        int _height = 0;
        uint _timeAtCreationInMs;
        uint _lastMeasturedTimeInMs;

        bool _dirtyAreasAreNotYetComputed = true; // TODO: could have a race on this if timer thread != draw thread
        bool _firstMouseMove = true;

        int _lastMouseX;
        int _lastMouseY;

    public:
        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            _listener = listener;
            DerelictCarbon.load();
            DerelictCoreFoundation.load();
            DerelictCoreServices.load();
            DerelictCoreGraphics.load();

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

            ControlRef parentControl = null; // only used for AU in Iplug

            OSStatus status;
            if (_isComposited)
            {
                if (!parentControl)
                {
                    HIViewRef hvRoot = HIViewGetRoot(_window);
                    status = HIViewFindByID(hvRoot, kHIViewWindowContentID, &parentControl);
                }

                status = HIViewAddSubview(parentControl, _view);
            }
            else
            {
                // QuickDraw not supported
                assert(false);
            }

            if (status == noErr)
                SizeControl(_view, r.right, r.bottom);  // offset?

            static immutable string colorSpaceName = "kCGColorSpaceSRGB";
            CFStringRef str = CFStringCreateWithCString(null, colorSpaceName.ptr, kCFStringEncodingUTF8);
            _colorSpace = CGColorSpaceCreateWithName(str);

            // TODO: release str

            _lastMeasturedTimeInMs = _timeAtCreationInMs = getTimeMs();
        }

        void clearBuffers()
        {
            if (_buffer != null)
            {
                free(_buffer);
                _buffer = null;

                CGDataProviderRelease(_dataProvider);
            }
        }

        ~this()
        {
            if (_initialized)
            {
                debug ensureNotInGC("CarbonWindow");
                _terminated = true;
                _initialized = false;

                clearBuffers();

                CGColorSpaceRelease(_colorSpace);

                RemoveEventLoopTimer(_timer);
                RemoveEventHandler(_controlHandler);
                RemoveEventHandler(_windowHandler);

                DerelictCoreServices.unload();
                DerelictCoreFoundation.unload();
                DerelictCoreGraphics.unload();
                DerelictCarbon.unload();
            }
        }


        // IWindow implmentation
        override void waitEventAndDispatch()
        {
            assert(false); // Unimplemented, TODO
        }

        // If exit was requested
        override bool terminated()
        {
            return _terminated;
        }

        override void debugOutput(string s)
        {
            fprintf(stderr, toStringz(s));
        }

        override uint getTimeMs()
        {
            import core.time;
            long msecs = convClockFreq(MonoTime.currTime.ticks, MonoTime.ticksPerSecond, 1_000);
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
                            assert(_isComposited);

                            HIRect bounds;
                            HIViewGetBounds(_view, &bounds);
                            int newWidth = cast(int)(0.5f + bounds.size.width);
                            int newHeight = cast(int)(0.5f + bounds.size.height);
                            updateSizeIfNeeded(newWidth, newHeight);


                            if (_dirtyAreasAreNotYetComputed)
                            {
                                _dirtyAreasAreNotYetComputed = false;
                                _listener.recomputeDirtyAreas();
                            }

                            // Redraw dirty UI
                            ImageRef!RGBA wfb;
                            wfb.w = _width;
                            wfb.h = _height;
                            wfb.pitch = byteStride(_width);
                            wfb.pixels = cast(RGBA*)_buffer;
                            _listener.onDraw(wfb, WindowPixelFormat.RGBA8);

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

                            Key key;

                            bool handled = true;

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
                                default:
                                    handled = false;
                            }

                            if (handled)
                            {
                                if (eventKind == kEventRawKeyDown)
                                    _listener.onKeyDown(key);
                                else
                                    _listener.onKeyUp(key);
                            }
                            return handled;

                        default:
                            return false;
                        }
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
                clearBuffers();

                size_t sizeNeeded = byteStride(newWidth) * newHeight;
                 _buffer = cast(ubyte*) malloc(sizeNeeded);

                // Create a new data provider
                _dataProvider = CGDataProviderCreateWithData(null, _buffer, sizeNeeded, null);

                _width = newWidth;
                _height = newHeight;
                _listener.onResized(_width, _height);
                return true;
            }
            else
                return false;
        }
    }

    extern(C) OSStatus eventCallback(EventHandlerCallRef pHandlerCall, EventRef pEvent, void* user) nothrow
    {
        FPControl fpctrl;
        fpctrl.initialize();
        try
        {
            CarbonWindow window = cast(CarbonWindow)user;
            bool handled = window.handleEvent(pEvent);
            return handled ? noErr : eventNotHandledErr;
        }
        catch(Exception e)
        {
            // TODO: do something clever
            return false;
        }
    }

    extern(C) void timerCallback(EventLoopTimerRef pTimer, void* user) nothrow
    {
        FPControl fpctrl;
        fpctrl.initialize();
        try
        {
            CarbonWindow window = cast(CarbonWindow)user;
            window.onTimer();
        }
        catch(Exception e)
        {
            // TODO: do something clever
        }
    }
}