/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.cocoawindow;

import core.stdc.stdlib;
import ae.utils.graphics;
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
        DPlugCustomView _view;

        bool _terminated = false;

        int _lastMouseX, _lastMouseY;
        bool _firstMouseMove = true;

        int _width;
        int _height;

        ubyte* _buffer;



    public:

        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            _listener = listener;         

            DerelictCocoa.load();
            NSApplicationLoad(); // to use Cocoa in Carbon applications

            NSView parentView = new NSView(cast(id)parentWindow);
            DPlugCustomView.registerSubclass();

            _view = DPlugCustomView.alloc();
            _view.initialize(this, width, height);

            parentView.addSubview(_view);

            _width = width;
            _height = height;
        }

        ~this()
        {
            close();
        }

        void close()
        {
            if (_view is null)
            {
                _view.removeFromSuperview();
                _view.release();
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
            scope(exit) message.release();
            NSString format = NSString.stringWith("%@"); // TODO cache this
            scope(exit) format.release();
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
                case NSLeftMouseDown: 
                    handleMouseClicks(event, MouseButton.left, false);
                    break;

                case NSLeftMouseUp: 
                    handleMouseClicks(event, MouseButton.left, true);
                    break;

                case NSRightMouseDown: 
                    handleMouseClicks(event, MouseButton.right, false);
                    break;

                case NSRightMouseUp: 
                    handleMouseClicks(event, MouseButton.right, true);
                    break;   

                case NSOtherMouseDown: 
                    {
                        int buttonNumber = event.buttonNumber;
                        if (buttonNumber == 2)
                            handleMouseClicks(event, MouseButton.middle, false);
                    }
                    break;

                case NSOtherMouseUp:
                    {
                        int buttonNumber = event.buttonNumber;
                        if (buttonNumber == 2)
                            handleMouseClicks(event, MouseButton.middle, true);
                    }
                    break;

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
        }+/

 /+       void getMouseLocation(NSEvent event, out int mouseX, out int mouseY)
        {
            NSPoint location = _window.mouseLocationOutsideOfEventStream();
            mouseX = cast(int)(0.5f + location.x);
            mouseY = cast(int)(0.5f + location.y);
            mouseY = _height - mouseY;
        }

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

        void handleMouseWheel(NSEvent event)
        {
            int deltaX = cast(int)(0.5 + 10 * event.deltaX);
            int deltaY = cast(int)(0.5 + 10 * event.deltaY);
            int mouseX, mouseY;
            getMouseLocation(event, mouseX, mouseY);            
            _listener.onMouseWheel(mouseX, mouseY, deltaX, deltaY, getMouseState(event));
        }

        void handleMouseClicks(NSEvent event, MouseButton mb, bool released)
        {
            int mouseX, mouseY;
            getMouseLocation(event, mouseX, mouseY);            
            
            if (released)
                _listener.onMouseRelease(mouseX, mouseY, mb, getMouseState(event));
            else
            {
                int clickCount = event.clickCount();
                bool isDoubleClick = clickCount >= 2;
                _listener.onMouseClick(mouseX, mouseY, mb, isDoubleClick, getMouseState(event));
            }
        }

        void handleMouseMove(NSEvent event)
        {
            import std.stdio;
            int mouseX, mouseY;
            getMouseLocation(event, mouseX, mouseY);

            if (_firstMouseMove)
            {
                _firstMouseMove = false;
                _lastMouseX = mouseX;
                _lastMouseY = mouseY;
            }

            _listener.onMouseMove(mouseX, mouseY, mouseX - _lastMouseX, mouseY - _lastMouseY, getMouseState(event));

            _lastMouseX = mouseX;
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
            scope(exit) nsContext.release();

            CIContext ciContext = nsContext.getCIContext();
            scope(exit) ciContext.release();

            updateSizeIfNeeded(_width, _height); // TODO support resize

            // draw buffers
            ImageRef!RGBA wfb;
            wfb.w = _width;
            wfb.h = _height;
            wfb.pitch = byteStride(_width);
            wfb.pixels = cast(RGBA*)_buffer;
            _listener.onDraw(wfb, false);

            size_t sizeInBytes = byteStride(_width) * _height * 4;
            NSData imageData = NSData.dataWithBytesNoCopy(_buffer, sizeInBytes, false);
            scope(exit) imageData.release();

            CIImage image = CIImage.imageWithBitmapData(imageData, byteStride(_width), 
                                                        CGSize(_width, _height), 23, null);//kCIFormatARGB8, null);
            scope(exit) image.release();

            ciContext.drawImage(image, rect, rect);
        }

        /// Returns: true if window size changed.
        bool updateSizeIfNeeded(int newWidth, int newHeight)
        {
            // only do something if the client size has changed
            if (newWidth != _width || newHeight != _height)
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

    class DPlugCustomView : NSView
    {
        this(id id_)
        {
            super(id_);
        }

        mixin NSObjectTemplate!(DPlugCustomView, "DPlugCustomView");

    private:

        CocoaWindow _window;
        NSTimer _timer;

        static bool classRegistered = false;

        void initialize(CocoaWindow window, int width, int height)        
        {
            this._window = window;

            NSRect r = NSRect(NSPoint(0, 0), NSSize(width, height));
            initWithFrame(r);

            _timer = NSTimer.timerWithTimeInterval(1 / 60.0, this, sel!"onTimer:", null, true);
            if (_timer is null)
                window.debugOutput("_timer is null");

            if (NSRunLoopCommonModes is null)
                window.debugOutput("NSRunLoopCommonModes is null");

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
            class_addMethod(clazz, sel!"acceptsFirstResponder", cast(IMP) &acceptsFirstResponder, "b@:");
            class_addMethod(clazz, sel!"isOpaque", cast(IMP) &isOpaque, "b@:");
            class_addMethod(clazz, sel!"acceptsFirstMouse", cast(IMP) &isOpaque, "b@:@");
            class_addMethod(clazz, sel!"viewDidMoveToWindow", cast(IMP) &isOpaque, "v@:");
            class_addMethod(clazz, sel!"drawRect", cast(IMP) &drawRect, "v@:" ~ encode!NSRect);
            class_addMethod(clazz, sel!"onTimer", cast(IMP) &drawRect, "v@:@");

            objc_registerClassPair(clazz);

            classRegistered = true;
        }

        extern(C) bool acceptsFirstResponder()
        {
            return YES;
        }

        extern(C) bool isOpaque()
        {
            return _window is null ? NO : YES;
        }

        extern(C) bool isOpaque(id pEvent)
        {
            return YES;
        }

        extern(C) void viewDidMoveToWindow()
        {
            NSWindow parentWindow = window();
            parentWindow.makeFirstResponder(this);
            parentWindow.setAcceptsMouseMovedEvents(true);
        }

        extern(C) void drawRect(NSRect rect)
        {
            if (_window !is null)
            {
                _window.drawRect(rect);
            }
        }

        extern(C) void onTimer(id timer)
        {            
            if (_window !is null)
            {
                // TODO call listener.onAnimate

                _window._listener.recomputeDirtyAreas();
                box2i dirtyRect = _window._listener.getDirtyRectangle();
                NSRect r = NSMakeRect(dirtyRect.min.x, dirtyRect.min.y, dirtyRect.width, dirtyRect.height);
                this.setNeedsDisplayInRect(r);
            }
        }

        extern(C) void keyDown(id event)
        {
            _window.handleKeyEvent(new NSEvent(event), false);
        }

        extern(C) void keyUp(id event)
        {
            _window.handleKeyEvent(new NSEvent(event), true);
        }
    }
}
