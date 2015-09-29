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

        ubyte* _buffer = null;

        int _width = 0;
        int _height = 0;

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

            InstallControlEventHandler(_view, &MainEventHandler, controlEvents.length, controlEvents.ptr, cast(void*)this, &_controlHandler);

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

            InstallWindowEventHandler(pWindow, &MainEventHandler, windowEvents.length, windowEvents.ptr, cast(void*)this, &_windowHandler);

//            double t = kEventDurationSecond / (double) pGraphicsMac->FPS();

 //           OSStatus s = InstallEventLoopTimer(GetMainEventLoop(), 0., t, TimerHandler, this, &mTimer);

            ControlRef parentControl = null; // used for AU only in Iplug

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

                            // Redraw dirty UI
                            ImageRef!RGBA wfb;
                            wfb.w = _width;
                            wfb.h = _height;
                            wfb.pitch = byteStride(_width);
                            wfb.pixels = cast(RGBA*)_buffer;
                            _listener.onDraw(wfb, WindowPixelFormat.ARGB8);

                            CGContextRef contextRef;

                            // Get the CGContext
                            GetEventParameter(pEvent, kEventParamCGContextRef, typeCGContextRef,
                                              null, CGContextRef.sizeof, null, &contextRef);


                            // TODO: use a smaller thing
                            CGRect rect = CGRect(CGPoint(0, 0), CGSize(_width, _height));

                            CGImageRef image; // TODO build that image

                            CGContextDrawImage(contextRef, rect, image);

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

    extern(C) OSStatus MainEventHandler(EventHandlerCallRef pHandlerCall, EventRef pEvent, void* user) nothrow
    {
        try
        {
            CarbonWindow window = cast(CarbonWindow)user;
            bool handled = window.handleEvent(pEvent);
            return handled ? noErr : eventNotHandledErr;
        }
        catch(Exception e)
        {
            return false;
        }
    }
}