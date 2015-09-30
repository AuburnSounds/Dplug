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

    import derelict.carbon;

    import ae.utils.graphics;

    import gfm.core;
    import gfm.math;

    import dplug.window.window;



    final class CarbonWindow : IWindow
    {
    private:
        IWindowListener _listener;
        bool _terminated = false;
        bool _initialized = true;
        bool _isComposited;
        ControlRef _view = null;
        EventHandlerRef _controlHandler = null;
        EventHandlerRef _windowHandler = null;
        EventLoopTimerRef _timer = null;

        ubyte* _buffer = null;

        int _width = 0;
        int _height = 0;
        uint _timeAtCreationInMs;
        uint _lastMeasturedTimeInMs;

        bool _dirtyAreasAreNotYetComputed = true;

    public:
        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            _listener = listener;
            DerelictCarbon.load();
            DerelictCoreGraphics.load();

            WindowRef pWindow = cast(WindowRef)(parentWindow);
            WindowAttributes winAttrs = 0;
            GetWindowAttributes(pWindow, &winAttrs);
            _isComposited = (winAttrs & kWindowCompositingAttribute) != 0;

            UInt32 features =  kControlSupportsFocus | kControlHandlesTracking | kControlSupportsEmbedding;
            if (_isComposited)
                features |= kHIViewFeatureIsOpaque | kHIViewFeatureDoesNotUseSpecialParts;

            Rect r;
            r.left = 0;
            r.top = 0;
            r.right = cast(short)width;
            r.bottom = cast(short)height;

            CreateUserPaneControl(pWindow, &r, features, &_view);

            static immutable EventTypeSpec[] controlEvents =
            [
                EventTypeSpec(kEventClassControl, kEventControlDraw)
            ];

            InstallControlEventHandler(_view, &eventCallback, controlEvents.length, controlEvents.ptr, cast(void*)this, &_controlHandler);

            static immutable EventTypeSpec[] windowEvents =
            [
                EventTypeSpec(kEventClassMouse, kEventMouseDown),
                EventTypeSpec(kEventClassMouse, kEventMouseUp),
                EventTypeSpec(kEventClassMouse, kEventMouseMoved),
                EventTypeSpec(kEventClassMouse, kEventMouseDragged),
                EventTypeSpec(kEventClassMouse, kEventMouseWheelMoved),
                EventTypeSpec(kEventClassKeyboard, kEventRawKeyDown),
                EventTypeSpec(kEventClassWindow, kEventWindowDeactivated)
            ];

            InstallWindowEventHandler(pWindow, &eventCallback, windowEvents.length, windowEvents.ptr, cast(void*)this, &_windowHandler);

            OSStatus s = InstallEventLoopTimer(GetMainEventLoop(), 0.0, kEventDurationSecond / 60.0,
                                               &timerCallback, cast(void*)this, &_timer);

            ControlRef parentControl = null; // only used for AU in Iplug

            OSStatus status;
            if (_isComposited)
            {
                if (!parentControl)
                {
                    HIViewRef hvRoot = HIViewGetRoot(pWindow);
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

            _lastMeasturedTimeInMs = _timeAtCreationInMs = getTimeMs();
        }

        ~this()
        {
            if (_initialized)
            {
                debug ensureNotInGC("CarbonWindow");
                _terminated = true;
                _initialized = false;

                if (_buffer != null)
                {
                    free(_buffer);
                    _buffer = null;
                }

                RemoveEventLoopTimer(_timer);
                RemoveEventHandler(_controlHandler);
                RemoveEventHandler(_windowHandler);

                DerelictCoreGraphics.unload();
                DerelictCarbon.unload();
            }
        }


        // IWindow implmentation
        override void waitEventAndDispatch()
        {
            // TODO
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
            return 0;
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

                            // TODO: get actual size
                            updateSizeIfNeeded(620, 330);


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

                            CGRect rect = CGRect(CGPoint(0, 0), CGSize(_width, _height));

                            // See: http://stackoverflow.com/questions/2261177/cgimage-from-byte-array

                            size_t sizeNeeded = byteStride(_width) * _height;
                            CGDataProviderRef provider = CGDataProviderCreateWithData(null, _buffer, sizeNeeded, null);
                            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB(); // TODO: replace with sRGB

                            CGImageRef image = CGImageCreate(_width, _height, 8, 32, byteStride(_width), space,
                                                             kCGBitmapByteOrderDefault, provider, null, false,
                                                             kCGRenderingIntentDefault);

                            CGContextDrawImage(contextRef, rect, image);

                            CGColorSpaceRelease(space);
                            CGDataProviderRelease(provider);
                            CGImageRelease(image);
                            return true;
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
                if (_buffer != null)
                {
                    free(_buffer);
                    _buffer = null;
                }

                size_t sizeNeeded = byteStride(newWidth) * newHeight;
                 _buffer = cast(ubyte*) malloc(sizeNeeded);
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