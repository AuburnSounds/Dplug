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

            if (parentWindow is null)
            {
                _application.activateIgnoringOtherApps(YES);
                _application.run();
            }
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
    }
}


/+

// Receiving commands from a window
interface IWindowListener
{



    /// Recompute internally what needs be done for the next onDraw.
    /// This function MUST be called before calling `onDraw` and `getDirtyRectangle`.
    /// This method exists to allow the Window to recompute these draw lists less.
    /// And because cache invalidation was easier on user code than internally in the UI.
    void recomputeDirtyAreas();

    /// Returns: Minimal rectangle that contains dirty UIELement in UI + their graphical extent.
    ///          Empty box if nothing to update.
    /// recomputeDirtyAreas() MUST have been called before.
    box2i getDirtyRectangle();

    /// Called whenever mouse capture was canceled (ALT + TAB, SetForegroundWindow...)
    void onMouseCaptureCancelled();

    /// Must be called periodically (ideally 60 times per second but this is not mandatory).
    /// `time` must refer to the window creation time.
    void onAnimate(double dt, double time);
}
+/