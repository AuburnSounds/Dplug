module dplug.gui.win32window;

import core.thread;

import std.process,
       std.string;

import gfm.math;

import ae.utils.graphics;

import dplug.gui.types;
import dplug.gui.window;
version(Windows)
{
    import std.uuid;

    import win32.w32api;
    import win32.winuser;
    import win32.winbase;
    import win32.windef;
    import win32.wingdi;


    import dplug.plugin.dllmain: gModuleHandle;

    HINSTANCE getModuleHandle()
    {
        if (gModuleHandle !is null)
            return cast(HINSTANCE) gModuleHandle;
        else
            return GetModuleHandleA(null);
    }

    class Win32Window : IWindow
    {
    public:

        this(HWND parentWindow, IWindowListener listener, int width, int height)
        {
            _wndClass.style = CS_DBLCLKS | CS_OWNDC;
            _wndClass.lpfnWndProc = &windowProcCallback;
            _wndClass.cbClsExtra = 0;
            _wndClass.cbWndExtra = 0;
            _wndClass.hInstance = getModuleHandle();
            _wndClass.hIcon = null;
            _wndClass.hCursor = LoadCursorA(null, IDC_ARROW);
            _wndClass.hbrBackground = null;
            _wndClass.lpszMenuName = null;

            // Generate an actually unique class name
            string uuid = randomUUID().toString();
            _className = "dplug_" ~ to!wstring(uuid) ~ "\0"; // add a terminator since toStringz for wstring doesn't seem to exist
            _wndClass.lpszClassName = _className.ptr;

            if (!RegisterClassW(&_wndClass))
            {
                DWORD err = GetLastError();
                throw new Exception(format("Couldn't register Win32 class (error %s)", err));
            }

            DWORD flags = WS_VISIBLE;
            if (parentWindow != null)
                flags |= WS_CHILD;

            _hwnd = CreateWindowW(_className.ptr, null, flags, CW_USEDEFAULT, CW_USEDEFAULT, width, height,
                                 parentWindow, null,
                                 getModuleHandle(),
                                 cast(void*)this);

            if (_hwnd is null)
            {
                DWORD err = GetLastError();
                throw new Exception(format("Couldn't create a Win32 window (error %s)", err));
            }

            _windowDC = GetDC(_hwnd);

            bool forcePixelFormat24bpp = false;

            if (forcePixelFormat24bpp)
            {
                // Finds a suitable pixel format for RGBA layout
                PIXELFORMATDESCRIPTOR pfd = PIXELFORMATDESCRIPTOR.init; // fill with zeroes since PIXELFORMATDESCRIPTOR is only integers
                pfd.nSize = pfd.sizeof;
                pfd.nVersion = 1;
                pfd.dwFlags = PFD_SUPPORT_GDI | PFD_DRAW_TO_WINDOW;
                pfd.iPixelType = PFD_TYPE_RGBA;
                pfd.cColorBits = 24;
                pfd.cAlphaBits = 8;
                pfd.cAccumBits = 0;
                pfd.cDepthBits = 0;
                pfd.cStencilBits = 0;
                pfd.cAuxBuffers = 0;
                pfd.iLayerType = 0; /* PFD_MAIN_PLANE */

                int indexOfBestPFD = ChoosePixelFormat(_windowDC, &pfd);
                if (indexOfBestPFD == 0)
                {
                    DWORD err = GetLastError();
                    throw new Exception(format("Couldn't find a suitable pixel format (error %s)", err));
                }

                if(TRUE != SetPixelFormat(_windowDC, indexOfBestPFD, &pfd))
                {
                    DWORD err = GetLastError();
                    throw new Exception(format("SetPixelFormat failed (error %s)", err));
                }
            }

            _listener = listener;

            // Sets this as user data
            SetWindowLongPtrA(_hwnd, GWLP_USERDATA, cast(LONG_PTR)( cast(void*)this ));

            int mSec = 15; // refresh at 60 hz if possible
            SetTimer(_hwnd, TIMER_ID, mSec, null);
            SetFocus(_hwnd);
        }

        ~this()
        {
            close();
        }

        void updateBufferSizeIfNeeded()
        {
            RECT winsize;
			BOOL res = GetClientRect(_hwnd, &winsize);
            if (res == 0)
            {
                DWORD err = GetLastError();
                throw new Exception(format("GetClientRect failed (error %s)", err));
            }

            int newWidth = winsize.right - winsize.left;
            int newHeight = winsize.bottom - winsize.top;

            // only do something if the client size has changed
            if (newWidth != _width || newHeight != _height)
            {
                // Extends buffer
                if (_buffer != null)
                {
                    VirtualFree(_buffer, 0, MEM_RELEASE);
                    _buffer = null;
                }

                size_t sizeNeeded = byteStride(newWidth) * newHeight;
                _buffer = cast(ubyte*) VirtualAlloc(null, sizeNeeded, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
                _width = newWidth;
                _height = newHeight;

                _listener.onResized(_width, _height);
            }
        }

        void close()
        {
            if (_hwnd != null)
            {
               DestroyWindow(_hwnd);
                _hwnd = null;

                // Unregister the window class, which was unique
                UnregisterClassW(_wndClass.lpszClassName, getModuleHandle());
            }
        }

        override void terminate()
        {
            close();
        }

        LRESULT windowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
        {
            // because DispatchMesage is called by host
            thread_attachThis();

            switch (uMsg)
            {
                case WM_KEYDOWN:
                case WM_KEYUP:
                {
                    Key key = vkToKey(wParam);
                    if (uMsg == WM_KEYDOWN)
                        _listener.onKeyDown(key);
                    else
                        _listener.onKeyUp(key);

                    if (key == Key.unsupported)
                    {
                        // key is passed to the parent window
                        HWND rootHWnd = GetAncestor(hwnd, GA_ROOT);
                        SendMessage(rootHWnd, uMsg, wParam, lParam);
                        return DefWindowProc(hwnd, uMsg, wParam, lParam);
                    }
                    else
                        return 0;
                }

                case WM_MOUSEMOVE:
                    {
                        int newMouseX = ( cast(int)lParam ) & 0xffff;
                        int newMouseY = ( cast(int)lParam ) >> 16;
                        int dx = newMouseX - _mouseX;
                        int dy = newMouseY - _mouseY;
                        _listener.onMouseMove(newMouseX, newMouseY, dx, dy, getMouseState(wParam));
                        _mouseX = newMouseX;
                        _mouseY = newMouseY;
                        return 0;
                    }

                case WM_RBUTTONDOWN:
                case WM_RBUTTONDBLCLK:
                {
                    if (mouseClick(_mouseX, _mouseY, MouseButton.right, uMsg == WM_RBUTTONDBLCLK, wParam))
                        return 0; // handled
                    goto default;
                }

                case WM_LBUTTONDOWN:
                case WM_LBUTTONDBLCLK:
                {
                    if (mouseClick(_mouseX, _mouseY, MouseButton.left, uMsg == WM_LBUTTONDBLCLK, wParam))
                        return 0; // handled
                    goto default;
                }

                case WM_MBUTTONDOWN:
                case WM_MBUTTONDBLCLK:
                {
                    if (mouseClick(_mouseX, _mouseY, MouseButton.middle, uMsg == WM_MBUTTONDBLCLK, wParam))
                        return 0; // handled
                    goto default;
                }

                // X1/X2 buttons
                case WM_XBUTTONDOWN:
                case WM_XBUTTONDBLCLK:
                {
                    auto mb = (wParam >> 16) == 1 ? MouseButton.x1 : MouseButton.x2;
                    if (mouseClick(_mouseX, _mouseY, mb, uMsg == WM_XBUTTONDBLCLK, wParam))
                        return 0;
                    goto default;
                }

                case WM_RBUTTONUP:
                    if (mouseRelease(_mouseX, _mouseY, MouseButton.right, wParam))
                        return 0;
                    goto default;

                case WM_LBUTTONUP:
                    if (mouseRelease(_mouseX, _mouseY, MouseButton.left, wParam))
                        return 0;
                    goto default;
                case WM_MBUTTONUP:
                    if (mouseRelease(_mouseX, _mouseY, MouseButton.middle, wParam))
                        return 0;
                    goto default;

                case WM_XBUTTONUP:
                {
                    auto mb = (wParam >> 16) == 1 ? MouseButton.x1 : MouseButton.x2;
                    if (mouseRelease(_mouseX, _mouseY, mb, wParam))
                        return 0;
                    goto default;
                }

                case WM_CAPTURECHANGED:
                    _listener.onMouseCaptureCancelled();
                    goto default;

                case WM_PAINT:
                {
                    RECT r;
                    if (GetUpdateRect(hwnd, &r, FALSE))
                    {
                        updateBufferSizeIfNeeded();

                        ImageRef!RGBA wfb;
                        wfb.w = _width;
                        wfb.h = _height;
                        wfb.pitch = byteStride(_width);
                        wfb.pixels = cast(RGBA*)_buffer;

                        _listener.onDraw(wfb);

                        box2i areaToRedraw = box2i(r.left, r.top, r.right, r.bottom);
                        box2i[] areasToRedraw = (&areaToRedraw)[0..1];
                        swapBuffers(wfb, areasToRedraw);
                    }
                    return 0;
                }

                case WM_CLOSE:
                {
                    close();
                    return 0;
                }

                case WM_TIMER:
                {
                    if (wParam == TIMER_ID)
                    {
                        box2i dirtyRect = _listener.getDirtyRectangle();
                        if (!dirtyRect.empty())
                        {
                            dirtyRect = _listener.extendsDirtyRect(dirtyRect, _width, _height);

                            RECT r;
                            r.left = dirtyRect.min.x;
                            r.top = dirtyRect.min.y;
                            r.right = dirtyRect.max.x;
                            r.bottom = dirtyRect.max.y;
                            InvalidateRect(hwnd, &r, FALSE); // TODO: be more precise with invalidated regions?
                            UpdateWindow(hwnd);
                        }
                    }
                    return 0;

                case WM_SIZE:
                    _width = LOWORD(lParam);
                    _height = HIWORD(lParam);
                    return DefWindowProcA(hwnd, uMsg, wParam, lParam);

                default:
                    return DefWindowProcA(hwnd, uMsg, wParam, lParam);
                }
            }
        }

        void swapBuffers(ImageRef!RGBA wfb, box2i[] areasToRedraw)
        {
            // Swap red and blue to have BGRA layout
            foreach(box2i area; areasToRedraw)
                swapRB(wfb, area);

            PAINTSTRUCT paintStruct;
            HDC hdc = BeginPaint(_hwnd, &paintStruct);
            assert(hdc == _windowDC); // since we are CS_OWNDC

            foreach(box2i area; areasToRedraw)
            {
                if (area.width() <= 0 || area.height() <= 0)
                    continue; // nothing to update
                
                BITMAPINFOHEADER bmi = BITMAPINFOHEADER.init; // fill with zeroes
                with (bmi)
                {
                    biSize          = BITMAPINFOHEADER.sizeof;
                    biWidth         = _width;
                    biHeight        = -_height;
                    biPlanes        = 1;
                    biCompression = BI_RGB;
                    biXPelsPerMeter = 72;
                    biYPelsPerMeter = 72;
                    biBitCount      = 32;
                    biSizeImage     = byteStride(_width) * _height;
                    SetDIBitsToDevice(_windowDC, area.min.x, area.min.y, area.width, area.height, 
                                      area.min.x, -area.min.y - area.height + _height, 0, _height, _buffer, cast(BITMAPINFO *)&bmi, DIB_RGB_COLORS);
                }
            }

            EndPaint(_hwnd, &paintStruct);

            // Swap red and blue to have RGBA layout again
            foreach(box2i area; areasToRedraw)
                swapRB(wfb, area);
        }

        // Implements IWindow
        override void waitEventAndDispatch()
        {
            MSG msg;
            int ret = GetMessageW(&msg, _hwnd, 0, 0); // no range filtering
            if (ret == -1)
                throw new Exception("Error while in GetMessage");
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        override bool terminated()
        {
            return _terminated;
        }

    private:
        enum TIMER_ID = 144;

        HWND _hwnd;
        HDC _windowDC;

        WNDCLASSW _wndClass;
        wstring _className;

        IWindowListener _listener;

        // The framebuffer. This should point into commited virtual memory for faster (maybe) upload to device
        ubyte* _buffer = null;

        bool _terminated = false;
        int _width = 0;
        int _height = 0;

        int _mouseX = 0;
        int _mouseY = 0;

        /// Propagates mouse events.
        /// Returns: true if event handled.
        bool mouseClick(int mouseX, int mouseY, MouseButton mb, bool isDoubleClick, WPARAM wParam)
        {
            SetFocus(_hwnd);   // get keyboard focus
            SetCapture(_hwnd); // start mouse capture
            return _listener.onMouseClick(mouseX, mouseY, mb, isDoubleClick, getMouseState(wParam));
        }

        /// ditto
        bool mouseRelease(int mouseX, int mouseY, MouseButton mb, WPARAM wParam)
        {
            ReleaseCapture();
            return _listener.onMouseRelease(mouseX, mouseY, mb, getMouseState(wParam));
        }

        static void swapRB(ImageRef!RGBA surface, box2i areaToRedraw)
        {
            for (int y = areaToRedraw.min.y; y < areaToRedraw.max.y; ++y)
            {
                RGBA[] scan = surface.scanline(y);
                for (int x = areaToRedraw.min.x; x < areaToRedraw.max.x; ++x)
                {
                    ubyte temp = scan[x].r;
                     scan[x].r = scan[x].b;
                     scan[x].b = temp;
                }
            }
        }
    }

    // given a width, how long in bytes should scanlines be
    int byteStride(int width)
    {
        enum alignment = 4;
        int widthInBytes = width * 4;
        return (widthInBytes + (alignment - 1)) & ~(alignment-1);
    }

    extern(Windows) nothrow
    {
        LRESULT windowProcCallback(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
        {
            import std.stdio;
            try
            {
                Win32Window window = cast(Win32Window)( cast(void*)(GetWindowLongPtrA(hwnd, GWLP_USERDATA)) );

                if (window !is null)
                {
                    return window.windowProc(hwnd, uMsg, wParam, lParam);
                }
                else
                {
                    return DefWindowProcA(hwnd, uMsg, wParam, lParam);
                }
            }
            catch(Throwable t)
            {
                assert(false);
            }
        }
    }

    Key vkToKey(WPARAM vk) pure nothrow @nogc
    {
        switch (vk)
        {
            case VK_SPACE: return Key.space;

            case VK_UP: return Key.upArrow;
            case VK_DOWN: return Key.downArrow;
            case VK_LEFT: return Key.leftArrow;
            case VK_RIGHT: return Key.rightArrow;

            case VK_NUMPAD0: return Key.digit0;
            case VK_NUMPAD1: return Key.digit1;
            case VK_NUMPAD2: return Key.digit2;
            case VK_NUMPAD3: return Key.digit3;
            case VK_NUMPAD4: return Key.digit4;
            case VK_NUMPAD5: return Key.digit5;
            case VK_NUMPAD6: return Key.digit6;
            case VK_NUMPAD7: return Key.digit7;
            case VK_NUMPAD8: return Key.digit8;
            case VK_NUMPAD9: return Key.digit9;
            case VK_RETURN: return Key.enter;
            default: return Key.unsupported;
        }
    }

    static MouseState getMouseState(WPARAM wParam)
    {
        return MouseState( (wParam & MK_LBUTTON) != 0,
                           (wParam & MK_RBUTTON) != 0,
                           (wParam & MK_MBUTTON) != 0,
                           (wParam & MK_XBUTTON1) != 0,
                           (wParam & MK_XBUTTON2) != 0,
                           (wParam & MK_CONTROL) != 0,
                           (wParam & MK_SHIFT) != 0,
                           GetKeyState(VK_MENU) < 0 );
    }
}
