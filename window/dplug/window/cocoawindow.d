/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.cocoawindow;

import core.stdc.stdlib;
import std.string;
import std.stdio;
import std.uuid;

import ae.utils.graphics;

import gfm.core;
import gfm.math;

import dplug.core.unchecked_sync;
import dplug.core.fpcontrol;
import dplug.window.window;
import dplug.client.dllmain;

version(OSX)
{
    import derelict.cocoa;

    final class CocoaWindow : IWindow
    {
    private:
        IWindowListener _listener;

        NSColorSpace _nsColorSpace;
        CGColorSpaceRef _cgColorSpaceRef;
        NSData _imageData;
        NSString _logFormatStr;

        DPlugCustomView _view = null;

        bool _terminated = false;

        int _lastMouseX, _lastMouseY;
        bool _firstMouseMove = true;

        int _width;
        int _height;

        int _askedWidth;
        int _askedHeight;

        ubyte* _buffer = null;

        uint _timeAtCreationInMs;
        uint _lastMeasturedTimeInMs;
        bool _dirtyAreasAreNotYetComputed;

    public:

        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            _listener = listener;

            DerelictCocoa.load();
            NSApplicationLoad(); // to use Cocoa in Carbon applications
            bool parentViewExists = parentWindow !is null;

            _width = 0;
            _height = 0;

            _askedWidth = width;
            _askedHeight = height;

            _nsColorSpace = NSColorSpace.sRGBColorSpace();
            // hopefully not null else the colors will be brighter
            _cgColorSpaceRef = _nsColorSpace.CGColorSpace();

            _logFormatStr = NSString.stringWith("%@");

            _timeAtCreationInMs = getTimeMs();
            _lastMeasturedTimeInMs = _timeAtCreationInMs;

            _dirtyAreasAreNotYetComputed = true;

            string uuid = randomUUID().toString();
            DPlugCustomView.customClassName = "DPlugCustomView_" ~ uuid;
            DPlugCustomView.registerSubclass();

            _view = DPlugCustomView.alloc();
            _view.initialize(this, width, height);

            // In VST, add the view the parent view.
            // In AU (parentWindow == null), a reference to the view is returned instead and the host does it.
            if (parentWindow !is null)
            {
                NSView parentView = NSView(cast(id)parentWindow);
                parentView.addSubview(_view);
            }
        }

        ~this()
        {
            if (_view)
            {
                debug ensureNotInGC("CocoaWindow");
                _terminated = true;

                {
                    _view.killTimer();
                }

                _view.removeFromSuperview();
                _view.release();
                _view = DPlugCustomView(null);

                DPlugCustomView.unregisterSubclass();

                if (_buffer != null)
                {
                    free(_buffer);
                    _buffer = null;
                }
            }
        }

        // Implements IWindow
        override void waitEventAndDispatch()
        {
            assert(false); // not implemented in Cocoa, since we don't have a NSWindow
        }

        override bool terminated()
        {
            return _terminated;
        }

        override void debugOutput(string s)
        {
            import core.stdc.stdio;
            fprintf(stderr, toStringz(s));
        }

        override uint getTimeMs()
        {
            return cast(uint)(NSDate.timeIntervalSinceReferenceDate() * 1000.0);
        }

        override void* systemHandle()
        {
            return _view._id;
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
            int deltaX = cast(int)(0.5 + 10 * event.deltaX);
            int deltaY = cast(int)(0.5 + 10 * event.deltaY);
            vec2i mousePos = getMouseXY(_view, event, _height);
            _listener.onMouseWheel(mousePos.x, mousePos.y, deltaX, deltaY, getMouseState(event));
        }

        void handleKeyEvent(NSEvent event, bool released)
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
                default: key = Key.unsupported;
            }

            if (released)
                _listener.onKeyDown(key);
            else
                _listener.onKeyUp(key);
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

            _lastMouseX = mousePos.x;
            _lastMouseY = mousePos.y;
        }

        void handleMouseClicks(NSEvent event, MouseButton mb, bool released)
        {
            vec2i mousePos = getMouseXY(_view, event, _height);

            if (released)
                _listener.onMouseRelease(mousePos.x, mousePos.y, mb, getMouseState(event));
            else
            {
                int clickCount = event.clickCount();
                bool isDoubleClick = clickCount >= 2;
                _listener.onMouseClick(mousePos.x, mousePos.y, mb, isDoubleClick, getMouseState(event));
            }
        }

        enum scanLineAlignment = 4; // could be anything

        // given a width, how long in bytes should scanlines be
        int byteStride(int width)
        {
            int widthInBytes = width * 4;
            return (widthInBytes + (scanLineAlignment - 1)) & ~(scanLineAlignment-1);
        }

        void drawRect(NSRect rect)
        {
            NSGraphicsContext nsContext = NSGraphicsContext.currentContext();

            CIContext ciContext = nsContext.getCIContext();

            // Updates internal buffers in case of startup/resize
            // TODO: why is the bounds rect too large? It creates havoc in AU even without resizing.
            {
                /*
                NSRect boundsRect = _view.bounds();
                int width = cast(int)(boundsRect.size.width);   // truncating down the dimensions of bounds
                int height = cast(int)(boundsRect.size.height);
                */
                updateSizeIfNeeded(_askedWidth, _askedHeight);
            }

            // The first drawRect callback occurs before the timer triggers.
            // But because recomputeDirtyAreas() wasn't called before there is nothing to draw.
            // Hence, do it.
            if (_dirtyAreasAreNotYetComputed)
            {
                _dirtyAreasAreNotYetComputed = false;
                _listener.recomputeDirtyAreas();
            }

            // draw buffers
            ImageRef!RGBA wfb;
            wfb.w = _width;
            wfb.h = _height;
            wfb.pitch = byteStride(_width);
            wfb.pixels = cast(RGBA*)_buffer;
            _listener.onDraw(wfb, WindowPixelFormat.ARGB8);

            size_t sizeNeeded = byteStride(_width) * _height;
            _imageData = NSData.dataWithBytesNoCopy(_buffer, sizeNeeded, false);

            CIImage image = CIImage.imageWithBitmapData(_imageData,
                                                        byteStride(_width),
                                                        CGSize(_width, _height),
                                                        kCIFormatARGB8,
                                                        _cgColorSpaceRef);

            ciContext.drawImage(image, rect, rect);
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
    }

    struct DPlugCustomView
    {
        // This class uses a unique class name for each plugin instance
        static __gshared string customClassName = null;

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
            alias fun_t = extern(C) id function (id obj, SEL sel);
            return DPlugCustomView( (cast(fun_t)objc_msgSend)(getClassID(), sel!"alloc") );
        }

        static Class getClass()
        {
            return cast(Class)( getClassID() );
        }

        static id getClassID()
        {
            assert(customClassName !is null);
            return objc_getClass(customClassName);
        }

    private:

        CocoaWindow _window;
        NSTimer _timer = null;

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
            NSRunLoop.currentRunLoop().addTimer(_timer, NSRunLoopCommonModes);
        }

        static __gshared Class clazz;

        static void registerSubclass()
        {
            clazz = objc_allocateClassPair(cast(Class) lazyClass!"NSView", toStringz(customClassName), 0);

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
            class_addMethod(clazz, sel!"drawRect:", cast(IMP) &drawRect, "v@:" ~ encode!NSRect);
            class_addMethod(clazz, sel!"onTimer:", cast(IMP) &onTimer, "v@:@");

            class_addMethod(clazz, sel!"mouseEntered:", cast(IMP) &mouseEntered, "v@:@");
            class_addMethod(clazz, sel!"mouseExited:", cast(IMP) &mouseExited, "v@:@");

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

    DPlugCustomView getInstance(id anId)
    {
        // strange thing: object_getInstanceVariable definition is odd (void**)
        // and only works for pointer-sized values says SO
        void* thisPointer = null;
        Ivar var = object_getInstanceVariable(anId, "this", &thisPointer);
        assert(var !is null);
        assert(thisPointer !is null);
        return *cast(DPlugCustomView*)thisPointer;
    }

    vec2i getMouseXY(NSView view, NSEvent event, int windowHeight)
    {
        NSPoint mouseLocation = event.locationInWindow();
        mouseLocation = view.convertPoint(mouseLocation, NSView(null));
        int px = cast(int)(mouseLocation.x) - 2;
        int py = windowHeight - cast(int)(mouseLocation.y) - 3;
        return vec2i(px, py);
    }

    // Overridden function gets called with an id, instead of the self pointer.
    // So we have to get back the D class object address.
    // Big thanks to Mike Ash (@macdev)
    // TODO: why are these methods members???
    extern(C)
    {
        void keyDown(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.handleKeyEvent(NSEvent(event), false);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void keyUp(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.handleKeyEvent(NSEvent(event), true);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void mouseDown(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.handleMouseClicks(NSEvent(event), MouseButton.left, false);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void mouseUp(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.handleMouseClicks(NSEvent(event), MouseButton.left, true);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void rightMouseDown(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.handleMouseClicks(NSEvent(event), MouseButton.right, false);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void rightMouseUp(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.handleMouseClicks(NSEvent(event), MouseButton.right, true);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void otherMouseDown(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                auto nsEvent = NSEvent(event);
                if (nsEvent.buttonNumber == 2)
                    view._window.handleMouseClicks(nsEvent, MouseButton.middle, false);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void otherMouseUp(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                auto nsEvent = NSEvent(event);
                if (nsEvent.buttonNumber == 2)
                    view._window.handleMouseClicks(nsEvent, MouseButton.middle, true);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void mouseMoved(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.handleMouseMove(NSEvent(event));
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void mouseEntered(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                NSCursor.arrowCursor().push();
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void mouseExited(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                NSCursor.pop();
            }
            catch(Throwable)
            {
                assert(false);
            }
        }


        void scrollWheel(id self, SEL selector, id event) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.handleMouseWheel(NSEvent(event));
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        bool acceptsFirstResponder(id self, SEL selector) nothrow
        {
            return YES;
        }

        bool acceptsFirstMouse(id self, SEL selector, id pEvent) nothrow
        {
            return YES;
        }

        bool isOpaque(id self, SEL selector) nothrow
        {
            return YES;
        }

        void viewDidMoveToWindow(id self, SEL selector) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                DPlugCustomView view = getInstance(self);
                NSWindow parentWindow = view.window();
                if (parentWindow)
                {
                    parentWindow.makeFirstResponder(view);
                    parentWindow.setAcceptsMouseMovedEvents(true);
                }
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void drawRect(id self, SEL selector, NSRect rect) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.drawRect(rect);
            }
            catch(Throwable)
            {
                assert(false);
            }
        }

        void onTimer(id self, SEL selector, id timer) nothrow
        {
            try
            {
                attachToRuntimeIfNeeded();
                FPControl fpctrl;
                fpctrl.initialize();
                DPlugCustomView view = getInstance(self);
                view._window.onTimer();
            }
            catch(Throwable)
            {
                assert(false);
            }
        }
    }
}
