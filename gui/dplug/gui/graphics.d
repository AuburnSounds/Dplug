module dplug.gui.graphics;

import ae.utils.graphics;
import dplug.plugin.client;
import dplug.plugin.graphics;

import dplug.gui.window;
import dplug.gui.toolkit.context;
import dplug.gui.toolkit.element;

// A GUIGraphics is the interface between a plugin client and a IWindow.
// It is also an UIElement and the root element of the plugin UI hierarchy.
// You have to derive it to have a GUI.
// It dispatch window events to the GUI hierarchy.
class GUIGraphics : UIElement, IGraphics
{
    this(int initialWidth, int initialHeight)
    {
        _uiContext = new UIContext();
        super(_uiContext);

        _windowListener = new WindowListener();

        _window = null;
        _askedWidth = initialWidth;
        _askedHeight = initialHeight;        
    }

    // Graphics implementation

    override void openUI(void* parentInfo)
    {
        // We create this window each time.
        _window = createWindow(parentInfo, _windowListener, _askedWidth, _askedHeight);
        reflow(box2i(0, 0, _askedWidth, _askedHeight));        
    }

    override void closeUI()
    {
        // Destroy window.
        _window.terminate();
    }

    override int getGUIWidth()
    {
        return _askedWidth;
    }

    override int getGUIHeight()
    {
        return _askedHeight;
    }


    // This nested class is only here to avoid name conflicts between 
    // UIElement and IWindowListener methods :|
    class WindowListener : IWindowListener
    {
        override bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick)
        {
            return this.outer.mouseClick(x, y, mb, isDoubleClick);
        }

        override bool onMouseRelease(int x, int y, MouseButton mb)
        {
            this.outer.mouseRelease(x, y, mb);
            return true;
        }

        override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY)
        {
            return this.outer.mouseWheel(x, y, wheelDeltaX, wheelDeltaY);
        }

        override void onMouseMove(int x, int y, int dx, int dy)
        {
            this.outer.mouseMove(x, y, dx, dy);
        }

        override bool onKeyDown(Key key)
        {
            // Sends the event to the last clicked element first
            if (_uiContext.focused !is null)
                if (_uiContext.focused.onKeyDown(key))
                    return true;

            // else to all Elements
            return keyDown(key);
        }

        override bool onKeyUp(Key key)
        {
            // Sends the event to the last clicked element first
            if (_uiContext.focused !is null)
                if (_uiContext.focused.onKeyUp(key))
                    return true;
            // else to all Elements
            return keyUp(key);
        }

        // an image you have to draw to, or return that nothing has changed
        box2i onDraw(ImageRef!RGBA wfb)
        {
            // Get sorted draw list
            UIElement[] elemsToDraw = getDrawList();

            foreach(elem; elemsToDraw)
                elem.render(wfb);

            // TODO: extract the dirty areas from draw-list
            return box2i(0, 0, wfb.w, wfb.h);
        }

        void onMouseCaptureCancelled()
        {
            // Stop an eventual drag operation
            _uiContext.stopDragging();
        }
    }


protected:
    UIContext _uiContext;

    WindowListener _windowListener;

    // An interface to the underlying window
    IWindow _window;

    int _askedWidth = 0;
    int _askedHeight = 0;
}
