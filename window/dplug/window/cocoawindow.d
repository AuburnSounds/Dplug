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

    final class CocoaWindow : IWindow
    {
    private:   
        IWindowListener _listener;          
        

    public:

        this(void* parentWindow, IWindowListener listener, int width, int height)
        {
            _listener = listener;         
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
            close();
        }
        
        // Implements IWindow
        override void waitEventAndDispatch()
        {
            
        }

        override bool terminated()
        {
            return false;            
        }

        override void debugOutput(string s)
        {
            import std.stdio;
            writeln(s); // TODO: something better
        }

        override uint getTimeMs()
        {            
            return 0;
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