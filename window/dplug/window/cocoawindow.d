/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.window.cocoawindow;

import dplug.window.window;


version(darwin)
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
        NSApplication _application;
        NSWindow _window;        
        bool _terminated = false;

        int _lastMouseX, _lastMouseY;
        bool _firstMouseMove = true;

    public:

        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            _listener = listener;         

            DerelictCocoa.load();

            _application = NSApplication.sharedApplication;
            if (parentWindow is null)
                _application.setActivationPolicy(NSApplicationActivationPolicyRegular);

            _window = NSWindow.alloc();
            _window.initWithContentRect(NSMakeRect(0, 0, width, height), 0/*NSBorderlessWindowMask*/, NSBackingStoreBuffered, NO);
            _window.makeKeyAndOrderFront();

            _window.setAcceptsMouseMovedEvents(true);

        /*    if (parentWindow is null)
            {
                _application.activateIgnoringOtherApps(YES);
                _application.run();
            }*/
        }

        ~this()
        {
            close();
        }

        void close()
        {            
        }
        
        override void terminate()
        {
            _terminated = true;
            close();
        }
        
        // Implements IWindow
        override void waitEventAndDispatch()
        {
            NSEvent event = _window.nextEventMatchingMask(NSAnyEventMask);
            dispatchEvent(event);
        }

        override bool terminated()
        {
            return _terminated;            
        }

        override void debugOutput(string s)
        {
            import std.stdio;
            writeln(s); // TODO: something better
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

        void dispatchEvent(NSEvent event)
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
        }

        void getMouseLocation(NSEvent event, out int mouseX, out int mouseY)
        {
            NSPoint location = _window.mouseLocationOutsideOfEventStream();
            mouseX = cast(int)(0.5f + location.x);
            mouseY = cast(int)(0.5f + location.y);
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
    }
}
