module dplug.gui.graphics;

import ae.utils.graphics;
import dplug.plugin.client;
import dplug.plugin.graphics;

import dplug.gui.window;
import dplug.gui.toolkit.context;
import dplug.gui.toolkit.renderer;
import dplug.gui.toolkit.element;

// This is the interface between a plugin client and a IWindow.
// GUIGraphics is a bridge between a plugin client and a IWindow
// It also dispatch window events to the _mainElement root UI element (you shall add to it to create an UI).
class GUIGraphics : Graphics, IWindowListener
{
    this(Client client, int width, int height)
    {
        super(client);

        _window = null;
        _askedWidth = width;
        _askedHeight = height;

        // The UI is independent of the Window, and is reused
        _uiContext = new UIContext(new UIRenderer, null);
        _mainElement = new UIElement(_uiContext);
        _mainElement.backgroundColor = RGBA(140, 140, 140, 255); // plugin is grey by default
    }

    // Graphics implementation

    override void openUI(void* parentInfo)
    {
        // We create this window each time.
        _window = createWindow(parentInfo, this, _askedWidth, _askedHeight);
        _mainElement.reflow(box2i(0, 0, _askedWidth, _askedHeight));        
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

    // IWindowListener

    override bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick)
    {
        return _mainElement.mouseClick(x, y, mb, isDoubleClick);
    }

    override bool onMouseRelease(int x, int y, MouseButton mb)
    {
        _mainElement.mouseRelease(x, y, mb);
        return true;
    }

    override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY)
    {
        return _mainElement.mouseWheel(x, y, wheelDeltaX, wheelDeltaY);
    }

    override void onMouseMove(int x, int y, int dx, int dy)
    {
        _mainElement.mouseMove(x, y, dx, dy);
    }

    override bool onKeyDown(Key key)
    {
        // Sends the event to the last clicked element first
        if (_uiContext.focused !is null)
            if (_uiContext.focused.onKeyDown(key))
                return true;

        // else to all Elements
        return _mainElement.keyDown(key);
    }

    override bool onKeyUp(Key key)
    {
        // Sends the event to the last clicked element first
        if (_uiContext.focused !is null)
            if (_uiContext.focused.onKeyUp(key))
                return true;
        // else to all Elements
        return _mainElement.keyUp(key);
    }

    // an image you have to draw to, or return that nothing has changed
    void onDraw(ImageRef!RGBA wfb, out bool needRedraw)
    {
        _uiContext.renderer.setFrameBuffer(wfb);
        _mainElement.render();
        needRedraw = true;
    }

    void onMouseCaptureCancelled()
    {
        // Stop an eventual drag operation
        _uiContext.stopDragging();
    }

protected:
    Client _client;
    UIContext _uiContext;

    // The main element is the root element of the UIElement 
    // hierarchy and spans the whole window
    UIElement _mainElement;

    // An interface to the underlying window
    IWindow _window;

    int _askedWidth = 0;
    int _askedHeight = 0;
}
