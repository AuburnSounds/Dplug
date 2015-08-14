/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.cocoawindow;

import core.stdc.stdlib;
import std.string;
import std.stdio;

import ae.utils.graphics;

import gfm.core;
import gfm.math;



import dplug.window.window;

version(OSX)
{    
    import derelict.cocoa;

//    import core.sys.osx.mach.port;
//    import core.sys.osx.mach.semaphore;

    // clock declarations
    extern(C) nothrow @nogc
    {
        ulong mach_absolute_time();
        void absolutetime_to_nanoseconds(ulong abstime, ulong *result);
    }

    final class CocoaWindow : IWindow
    {
    private:   
        IWindowListener _listener;

        // Stays null in the case of a plugin, but exists for a stand-alone program
        // For testing purpose.
        NSWindow _cocoaWindow = null; 
        NSApplication _cocoaApplication;

        DPlugCustomView _view = null;

        bool _terminated = false;

        int _lastMouseX, _lastMouseY;
        bool _firstMouseMove = true;

        int _askedWidth;
        int _askedHeight; // TODO: remove in favor of asking the NSView its size

        int _currentWidth;
        int _currentHeight;

        ubyte* _buffer = null;

    public:

        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            _listener = listener;         

            DerelictCocoa.load();
            NSApplicationLoad(); // to use Cocoa in Carbon applications
            bool parentViewExists = parentWindow !is null;
            NSView parentView;
            if (!parentViewExists)
            {
                // create a NSWindow to hold our NSView
                _cocoaApplication = NSApplication.sharedApplication;
                _cocoaApplication.setActivationPolicy(NSApplicationActivationPolicyRegular);

                NSWindow window = NSWindow.alloc();
                window.initWithContentRect(NSMakeRect(100, 100, width, height), 
                                           NSBorderlessWindowMask, NSBackingStoreBuffered, NO);
                window.makeKeyAndOrderFront();

                parentView = window.contentView();

                _cocoaApplication.activateIgnoringOtherApps(YES);                
            }
            else
                parentView = new NSView(cast(id)parentWindow);

            DPlugCustomView.registerSubclass();

            _view = DPlugCustomView.alloc();
            _view.initialize(this, width, height);

            parentView.addSubview(_view);

            _askedWidth = width;
            _askedHeight = height;


            _currentWidth = 0;
            _currentHeight = 0;

            if (_cocoaApplication)
                _cocoaApplication.run();
        }

        ~this()
        {
            close();
        }

        void close()
        {
            if (_view !is null)
            {
                _view.killTimer();
                _view.removeFromSuperview();
                //_view.release();
                _view = null;
            }
        }
        
        override void terminate()
        {
            _terminated = true;
            close();
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
            NSString message = NSString.stringWith(s);
            //scope(exit) message.release();
            NSString format = NSString.stringWith("%@"); // TODO cache this
            //scope(exit) format.release();
            NSLog(format._id, message._id);
        }

        override uint getTimeMs()
        {
            return 0; // TODO
            /*
            ulong nano = void;
            absolutetime_to_nanoseconds(mach_absolute_time(), &nano);
            return cast(uint)(nano / 1_000_000);
            */
        }

    private:

 /+       void dispatchEvent(NSEvent event)
        {
            import std.stdio;
            switch(event.type())
            {

                case NSScrollWheel: 
                    handleMouseWheel(event);
                    break;

                case NSMouseMoved:
                case NSLeftMouseDragged:
                case NSRightMouseDragged:
                case NSOtherMouseDragged:
                    handleMouseMove(event);
                    break;
                
                case NSKeyDown: 
                    handleKeyEvent(event, false);
                    break;

                case NSKeyUp:
                    handleKeyEvent(event, true);
                    break;

                case NSFlagsChanged: 
                    break;

                case NSPeriodic:
                    break;
                default:            
            }
        }
+/
        MouseState getMouseState(NSEvent event)
        {
            // not working
            MouseState state;
           /* uint pressedMouseButtons = event.pressedMouseButtons();
            if (pressedMouseButtons & 1)
                state.leftButtonDown = true;
            if (pressedMouseButtons & 2)
                state.rightButtonDown = true;
            if (pressedMouseButtons & 4)
                state.middleButtonDown = true;
*/
            // TODO
            //bool ctrlPressed;
            //bool shiftPressed;
            //bool altPressed;

            return state;
        }

/+        void handleMouseWheel(NSEvent event)
        {
            int deltaX = cast(int)(0.5 + 10 * event.deltaX);
            int deltaY = cast(int)(0.5 + 10 * event.deltaY);
            int mouseX, mouseY;
            getMouseLocation(event, mouseX, mouseY);            
            _listener.onMouseWheel(mouseX, mouseY, deltaX, deltaY, getMouseState(event));
        } 

   _lastMouseY = mouseY;
        }+/

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
            vec2i mousePos = getMouseXY(_view, event, _askedHeight);

            debugOutput(format("Mouse moved to %s,%s", mousePos.x,mousePos.y));

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
            vec2i mousePos = getMouseXY(_view, event, _askedHeight);
            
            if (released)
                _listener.onMouseRelease(mousePos.x, mousePos.y, mb, getMouseState(event));
            else
            {
                debugOutput(format("Mouse clicked button %s at %s,%s", mb, mousePos.x, mousePos.y));

                // TODO double-click support that doesn't crash
                //int clickCount = event.clickCount();
                //bool isDoubleClick = clickCount >= 2;
                _listener.onMouseClick(mousePos.x, mousePos.y, mb, false, getMouseState(event));
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
            //debugOutput("drawRect");
       
            NSGraphicsContext nsContext = NSGraphicsContext.currentContext();

            CIContext ciContext = nsContext.getCIContext();

            // TODO get current with and size from NSView

            updateSizeIfNeeded(_askedWidth, _askedHeight); // TODO support resize

            // draw buffers
            ImageRef!RGBA wfb;
            wfb.w = _currentWidth;
            wfb.h = _currentHeight;
            wfb.pitch = byteStride(_currentWidth);
            wfb.pixels = cast(RGBA*)_buffer;
            _listener.onDraw(wfb, WindowPixelFormat.ARGB8);

            size_t sizeInBytes = byteStride(_currentWidth) * _currentHeight * 4;
            NSData imageData = NSData.dataWithBytesNoCopy(_buffer, sizeInBytes, false);
            //scope(exit) imageData.release();

            CIImage image = CIImage.imageWithBitmapData(imageData, byteStride(_currentWidth), 
                                                        CGSize(_currentWidth, _currentHeight), kCIFormatARGB8, null);
            //scope(exit) image.release();

            ciContext.drawImage(image, rect, rect);
        }

        /// Returns: true if window size changed.
        bool updateSizeIfNeeded(int newWidth, int newHeight)
        {
            // only do something if the client size has changed
            if (newWidth != _currentWidth || newHeight != _currentHeight)
            {
                // Extends buffer
                if (_buffer != null)
                {
                    free(_buffer);
                    _buffer = null;
                }

                size_t sizeNeeded = byteStride(newWidth) * newHeight;
                 _buffer = cast(ubyte*) malloc(sizeNeeded);                
                _currentWidth = newWidth;
                _currentHeight = newHeight;
                _listener.onResized(_currentWidth, _currentHeight);
                return true;
            }
            else
                return false;
        }
    }    

    class DPlugCustomView : NSView
    {
        this(id id_)
        {
            super(id_);
        }

        mixin NSObjectTemplate!(DPlugCustomView, "DPlugCustomView");

    private:

        CocoaWindow _window;
        NSTimer _timer = null;

        static bool classRegistered = false;

        void initialize(CocoaWindow window, int width, int height)        
        {
            void* thisPointer = cast(void*)this;
            object_setInstanceVariable(_id, "this", thisPointer);

            this._window = window;

            NSRect r = NSRect(NSPoint(0, 0), NSSize(width, height));
            initWithFrame(r);

            _timer = NSTimer.timerWithTimeInterval(1 / 60.0, this, sel!"onTimer:", null, true);
            NSRunLoop.currentRunLoop().addTimer(_timer, NSRunLoopCommonModes);                
        }

        static void registerSubclass()
        {
            if (classRegistered)
                return;

            Class clazz;
            clazz = objc_allocateClassPair(cast(Class) lazyClass!"NSView", "DPlugCustomView", 0);
            class_addMethod(clazz, sel!"keyDown:", cast(IMP) &keyDown, "v@:@");
            class_addMethod(clazz, sel!"keyUp:", cast(IMP) &keyUp, "v@:@");
            class_addMethod(clazz, sel!"mouseDown:", cast(IMP) &mouseDown, "v@:@");
            class_addMethod(clazz, sel!"mouseUp:", cast(IMP) &mouseUp, "v@:@");
            class_addMethod(clazz, sel!"rightMouseDown:", cast(IMP) &rightMouseDown, "v@:@");
            class_addMethod(clazz, sel!"rightMouseUp:", cast(IMP) &rightMouseUp, "v@:@");
            class_addMethod(clazz, sel!"otherMouseDown:", cast(IMP) &otherMouseDown, "v@:@");
            class_addMethod(clazz, sel!"otherMouseUp:", cast(IMP) &otherMouseUp, "v@:@");
            class_addMethod(clazz, sel!"mouseMoved:", cast(IMP) &mouseMoved, "v@:@");
            class_addMethod(clazz, sel!"mouseDragged:", cast(IMP) &mouseDragged, "v@:@");
            class_addMethod(clazz, sel!"rightMouseDragged:", cast(IMP) &rightMouseDragged, "v@:@");
            class_addMethod(clazz, sel!"otherMouseDragged:", cast(IMP) &otherMouseDragged, "v@:@");
            class_addMethod(clazz, sel!"acceptsFirstResponder", cast(IMP) &acceptsFirstResponder, "b@:");
            class_addMethod(clazz, sel!"isOpaque", cast(IMP) &isOpaque, "b@:");
            class_addMethod(clazz, sel!"acceptsFirstMouse:", cast(IMP) &acceptsFirstMouse, "b@:@");
            class_addMethod(clazz, sel!"viewDidMoveToWindow", cast(IMP) &viewDidMoveToWindow, "v@:");
            class_addMethod(clazz, sel!"drawRect:", cast(IMP) &drawRect, "v@:" ~ encode!NSRect);
            class_addMethod(clazz, sel!"onTimer:", cast(IMP) &onTimer, "v@:@");

            // very important: add an instance variable for the this pointer so that the D object can be
            // retrieved from an id
            class_addIvar(clazz, "this", (void*).sizeof, (void*).sizeof == 4 ? 2 : 3, "^v");
            
            objc_registerClassPair(clazz);

            classRegistered = true;
        }

        void killTimer()
        {
            if (_timer !is null)
            {
                _timer.invalidate();
                _timer = null;
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
        return cast(DPlugCustomView)thisPointer;
    }

    vec2i getMouseXY(NSView view, NSEvent event, int windowHeight)
    {   
        NSPoint pt = event.locationInWindow();
        pt = view.convertPoint(pt, null);

        int px = cast(int)(pt.x) - 2;
        int py = windowHeight - cast(int)(pt.y) - 3;
        return vec2i(px, py);
    }    

    // Overridden function gets called with an id, instead of the self pointer.
    // So we have to get back the D class object address.
    // Big thanks to Mike Ash (@macdev)
    extern(C)
    {
        void keyDown(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleKeyEvent(new NSEvent(event), false);
        }

        void keyUp(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleKeyEvent(new NSEvent(event), true);
        }

        void mouseDown(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleMouseClicks(new NSEvent(event), MouseButton.left, false);
        }

        void mouseUp(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleMouseClicks(new NSEvent(event), MouseButton.left, true);
        }

        void rightMouseDown(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleMouseClicks(new NSEvent(event), MouseButton.right, false);
        }

        void rightMouseUp(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleMouseClicks(new NSEvent(event), MouseButton.right, true);
        }       

        void otherMouseDown(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            auto nsEvent = new NSEvent(event);
            if (nsEvent.buttonNumber == 2)
                view._window.handleMouseClicks(nsEvent, MouseButton.middle, false);
        }

        void otherMouseUp(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            auto nsEvent = new NSEvent(event);
            if (nsEvent.buttonNumber == 2)
                view._window.handleMouseClicks(nsEvent, MouseButton.middle, true);
        }

        void mouseMoved(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleMouseMove(new NSEvent(event));
        }

        void mouseDragged(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleMouseMove(new NSEvent(event));
        }

        void rightMouseDragged(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleMouseMove(new NSEvent(event));
        }

        void otherMouseDragged(id self, SEL selector, id event)
        {
            DPlugCustomView view = getInstance(self);
            view._window.handleMouseMove(new NSEvent(event));
        }

        bool acceptsFirstResponder(id self, SEL selector)
        {
            return YES;
        }

        bool acceptsFirstMouse(id self, SEL selector, id pEvent)
        {
            return YES;
        }

        bool isOpaque(id self, SEL selector)
        {
            //DPlugCustomView view = getInstance(self);
            return YES;//view._window is null ? NO : YES;
        }

        void viewDidMoveToWindow(id self, SEL selector)
        {
            DPlugCustomView view = getInstance(self);
            NSWindow parentWindow = view.window();
            if (parentWindow)
            {
                parentWindow.makeFirstResponder(view);            
                parentWindow.setAcceptsMouseMovedEvents(true);
            }
        }

        void drawRect(id self, SEL selector, NSRect rect)
        {
            DPlugCustomView view = getInstance(self);
            view._window.drawRect(rect);            
        }

        void onTimer(id self, SEL selector, id timer)
        {
            DPlugCustomView view = getInstance(self);
            
            // TODO call listener.onAnimate
            assert(view._window !is null);
            assert(view._window._listener !is null);
            
            view._window._listener.recomputeDirtyAreas();
            box2i dirtyRect = view._window._listener.getDirtyRectangle();
            if (!dirtyRect.empty())
            {
                NSRect r = NSMakeRect(dirtyRect.min.x, dirtyRect.min.y, dirtyRect.width, dirtyRect.height);
                view.setNeedsDisplayInRect(r);
            }
        }
    }
}
