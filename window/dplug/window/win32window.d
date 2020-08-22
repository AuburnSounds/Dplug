/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 - 2016 Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
/**
    Win32 window implementation.
*/
module dplug.window.win32window;

import std.process,
       std.string,
       std.conv;

import gfm.math.vector;
import gfm.math.box;

import dplug.core.runtime;
import dplug.core.nogc;
import dplug.core.vec;

import dplug.graphics.image;
import dplug.graphics.view;

import dplug.window.window;

nothrow:
@nogc:


version(Windows)
{
    import std.uuid;
    import dplug.core.random;

    import core.sys.windows.windef;
    import core.sys.windows.winuser;
    import core.sys.windows.winbase;
    import core.sys.windows.wingdi;


    HINSTANCE getModuleHandle() nothrow @nogc
    {
        return GetModuleHandleA(null);
    }

    final class Win32Window : IWindow
    {
    public:
    nothrow:
    @nogc:

        this(HWND parentWindow, IWindowListener listener, int width, int height)
        {
            _wndClass.style = CS_DBLCLKS | CS_OWNDC;

            _wndClass.lpfnWndProc = &windowProcCallback;

            _wndClass.cbClsExtra = 0;
            _wndClass.cbWndExtra = 0;
            _wndClass.hInstance = getModuleHandle();
            _wndClass.hIcon = null;
            _wndClass.hCursor = LoadCursor(null, IDC_ARROW);
            _wndClass.hbrBackground = null;
            _wndClass.lpszMenuName = null;

            // Generates an unique class name
            generateClassName();
            _wndClass.lpszClassName = _className.ptr;

            if (!RegisterClassW(&_wndClass))
            {
                assert(false, "Couldn't register Win32 class");
            }

            DWORD flags = WS_VISIBLE;
            if (parentWindow != null)
                flags |= WS_CHILD;
            else
                parentWindow = GetDesktopWindow();

            _hwnd = CreateWindowW(_className.ptr, null, flags, CW_USEDEFAULT, CW_USEDEFAULT, width, height,
                                 parentWindow, null,
                                 getModuleHandle(),
                                 cast(void*)this);

            if (_hwnd is null)
            {
                assert(false, "Couldn't create a Win32 window");
            }

            // Create update region
            _updateRegion = CreateRectRgn(0, 0, 0, 0);
            _clipRegion = CreateRectRgn(0, 0, 0, 0);
            _updateRgbBuf = makeVec!ubyte();
            _updateRects = makeVec!box2i();

            _listener = listener;
            // Sets this as user data
            SetWindowLongPtrA(_hwnd, GWLP_USERDATA, cast(LONG_PTR)( cast(void*)this ));

            if (_listener !is null) // we are interested in custom behaviour
            {

                int mSec = 15; // refresh at 60 hz if possible
                SetTimer(_hwnd, TIMER_ID, mSec, null);
            }

            SetFocus(_hwnd);

            // Get performance counter frequency
            LARGE_INTEGER performanceFrequency;
            BOOL res = QueryPerformanceFrequency(&performanceFrequency);
            assert(res != 0); // since XP it is always supported
            _performanceCounterDivider = performanceFrequency.QuadPart;

            // Get reference time
            _timeAtCreationInMs = getTimeMs();
            _lastMeasturedTimeInMs = _timeAtCreationInMs;

            // Do we need the FLStudio bridge work-around?
            // Detect if we are under FLStudio's bridge.
            _useFLStudioBridgeWorkaround = false;
            HMODULE hmodule = GetModuleHandle(NULL);
            if (hmodule !is NULL)
            {
                char[256] path;
                int len = GetModuleFileNameA(hmodule, path.ptr, 256);
                if (len >= 12)
                {
                    _useFLStudioBridgeWorkaround = path[len - 12 .. len] == "ilbridge.exe";
                }
            }
        }

        ~this()
        {
            if (_hwnd != null)
            {
                DestroyWindow(_hwnd);
                _hwnd = null;

                // Unregister the window class, which was unique
                UnregisterClassW(_wndClass.lpszClassName, getModuleHandle());
            }

            if (_updateRegion != null)
            {
                DeleteObject(_updateRegion);
                _updateRegion = null;
            }

            if (_clipRegion != null)
            {
                DeleteObject(_clipRegion);
                _clipRegion = null;
            }
        }

        /// Returns: true if window size changed.
        bool updateSizeIfNeeded()
        {
            RECT winsize;
            BOOL res = GetClientRect(_hwnd, &winsize);
            if (res == 0)
            {
                assert(false, "GetClientRect failed");
            }

            int newWidth = winsize.right - winsize.left;
            int newHeight = winsize.bottom - winsize.top;

            // only do something if the client size has changed
            if (newWidth != _width || newHeight != _height)
            {
                _width = newWidth;
                _height = newHeight;

                _wfb = _listener.onResized(_width, _height);
                return true;
            }
            else
                return false;
        }

        LRESULT windowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
        {
            // because DispatchMessage is called by host, we don't know which thread comes here
            ScopedForeignCallback!(true, true) scopedCallback;
            scopedCallback.enter();

            if (_listener is null)
                return DefWindowProc(hwnd, uMsg, wParam, lParam);

            switch (uMsg)
            {
                case WM_KEYDOWN:
                case WM_KEYUP:
                {
                    bool handled = false;

                    shiftPressed = GetKeyState(VK_SHIFT) < 0;

                    Key key = vkToKey(wParam, shiftPressed);
                    if (uMsg == WM_KEYDOWN)
                    {
                        if (_listener.onKeyDown(key))
                        {
                            handled = true;
                        }
                    }
                    else
                    {
                        if (_listener.onKeyUp(key))
                        {
                            handled = true;
                        }
                    }

                    if (!handled)
                    {
                        // key is passed to the parent window
                        HWND rootHWnd = GetAncestor(hwnd, GA_ROOT);
                        SendMessage(rootHWnd, uMsg, wParam, lParam);
                        return DefWindowProc(hwnd, uMsg, wParam, lParam);
                    }
                    else
                        return 0;
                }
                case WM_SETCURSOR:
                {
                    return setMouseCursor();
                }

                case WM_MOUSEMOVE:
                    {
                        // See Dplug #378, important to sign-extend for multiple monitors
                        int newMouseX = cast(int)(lParam << 16) >> 16; 
                        int newMouseY = ( cast(int)lParam ) >> 16;
                        int dx = newMouseX - _mouseX;
                        int dy = newMouseY - _mouseY;
                        _listener.onMouseMove(newMouseX, newMouseY, dx, dy, getMouseState(wParam));
                        _mouseX = newMouseX;
                        _mouseY = newMouseY;
                        setMouseCursor();
                        return 0;
                    }

                case WM_SETFOCUS:
                {
                    return 0;
                }

                case WM_KILLFOCUS:
                {
                    return 0;
                }

                case WM_MOUSEWHEEL:
                    {
                        // See Dplug #378, important to sign-extend for multiple monitors
                        int mouseX = cast(int)(lParam << 16) >> 16; 
                        int mouseY = ( cast(int)lParam ) >> 16;

                        // Mouse positions we are getting are not relative to the client area
                        RECT r;
                        GetWindowRect(hwnd, &r);
                        mouseX -= r.left;
                        mouseY -= r.top;

                        int wheelDeltaY = cast(short)((wParam & 0xffff0000) >> 16) / WHEEL_DELTA;      
                        
                        if (_listener.onMouseWheel(mouseX, mouseY, 0, wheelDeltaY, getMouseState(wParam)))
                        {
                            return 0; // handled
                        }
                        goto default;
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
                    updateSizeIfNeeded();

                    // Renders UI. 
                    // FUTURE: This could be done in a separate thread?
                    // For efficiency purpose, render in BGRA for Windows
                    // We do it here, but note that redrawing has nothing to do with WM_PAINT specifically,
                    // we just need to wait for it here.
                    _listener.onDraw(WindowPixelFormat.BGRA8);

                    // Get the update region
                    int type = GetUpdateRgn(hwnd, _updateRegion, FALSE);
                    assert (type != ERROR);

                    // Begin painting
                    PAINTSTRUCT paintStruct;
                    HDC hdc = BeginPaint(_hwnd, &paintStruct);

                    HRGN regionToUpdate = _updateRegion;

                    // FLStudio compatibility
                    // Try to get the DC's clipping region, which may be larger in the case of FLStudio's bridge.
                    if (_useFLStudioBridgeWorkaround)
                    {
                        if ( GetClipRgn(hdc, _clipRegion) == 1)
                            regionToUpdate = _clipRegion;
                    }

                    // Get needed number of bytes
                    DWORD bytes = GetRegionData(regionToUpdate, 0, null);
                    _updateRgbBuf.resize(bytes);

                    if (bytes == GetRegionData(regionToUpdate, bytes, cast(RGNDATA*)(_updateRgbBuf.ptr)))
                    {
                        // Get rectangles to update visually from the update region
                        ubyte* buf = _updateRgbBuf.ptr;
                        RGNDATAHEADER* header = cast(RGNDATAHEADER*)buf;
                        assert(header.iType == RDH_RECTANGLES);
                        _updateRects.clearContents();
                        RECT* pRect = cast(RECT*)(buf + RGNDATAHEADER.sizeof);

                        alias wfb = _wfb;
                        for (int r = 0; r < header.nCount; ++r)
                        {
                            int left = pRect[r].left;
                            int top = pRect[r].top;
                            int right = pRect[r].right;
                            int bottom = pRect[r].bottom;
                            _updateRects.pushBack(box2i(left, top, right, bottom));
                        }

                        BITMAPINFOHEADER bmi = BITMAPINFOHEADER.init; // fill with zeroes
                        with (bmi)
                        {
                            biSize          = BITMAPINFOHEADER.sizeof;
                            biWidth         = wfb.w;
                            biHeight        = -wfb.h;
                            biPlanes        = 1;
                            biCompression = BI_RGB;
                            biXPelsPerMeter = 72;
                            biYPelsPerMeter = 72;
                            biBitCount      = 32;
                            biSizeImage     = cast(int)(wfb.pitch) * wfb.h;
                        }
                        
                        foreach(box2i area; _updateRects)
                        {
                            if (area.width() <= 0 || area.height() <= 0)
                                continue; // nothing to update

                            SetDIBitsToDevice(hdc, area.min.x, area.min.y, area.width, area.height,
                                                area.min.x, -area.min.y - area.height + wfb.h, 
                                                0, wfb.h, wfb.pixels, cast(BITMAPINFO *)&bmi, DIB_RGB_COLORS);
                        }
                    }
                    else
                        assert(false);

                    EndPaint(_hwnd, &paintStruct);
                    return 0;
                }

                case WM_ERASEBKGND:
                {
                    // This fails, so cause this window's WM_PAINT to be responsible for erasing background, 
                    // hence saving a bit of performance.
                    return 1;
                }

                case WM_CLOSE:
                {
                    this.destroyNoGC();
                    return 0;
                }

                case WM_TIMER:
                {
                    if (wParam == TIMER_ID)
                    {
                        uint now = getTimeMs();
                        double dt = (now - _lastMeasturedTimeInMs) * 0.001;
                        double time = (now - _timeAtCreationInMs) * 0.001; // hopefully no plug-in will be open more than 49 days
                        _lastMeasturedTimeInMs = now;
                        _listener.onAnimate(dt, time);

                        _listener.recomputeDirtyAreas();
                        box2i dirtyRect = _listener.getDirtyRectangle();
                        if (!dirtyRect.empty())
                        {
                            RECT r = RECT(dirtyRect.min.x, dirtyRect.min.y, dirtyRect.max.x, dirtyRect.max.y);
                            InvalidateRect(_hwnd, &r, FALSE); // FUTURE: invalidate rects one by one

                            // See issue #432 and #269
                            // To avoid blocking WM_TIMER with expensive WM_PAINT, it's important NOT to enqueue manually a 
                            // WM_PAINT here. Let Windows do its job of sending WM_PAINT when needed.
                        }
                    }
                    return 0;
                }

                default:
                    return DefWindowProcA(hwnd, uMsg, wParam, lParam);
            }
        }



        // Implements IWindow
        override void waitEventAndDispatch()
        {
            MSG msg;
            int ret = GetMessageW(&msg, _hwnd, 0, 0); // no range filtering
            if (ret == -1)
                assert(false, "Error while in GetMessage");
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        override bool terminated()
        {
            return _terminated;
        }

        override uint getTimeMs()
        {
            LARGE_INTEGER perfCounter;
            BOOL err = QueryPerformanceCounter(&perfCounter);
            assert(err != 0); // always supported since XP
            double time = (perfCounter.QuadPart * 1000 + (_performanceCounterDivider >> 1)) / cast(double)_performanceCounterDivider;
            return cast(uint)(time);
        }

        override void* systemHandle()
        {
            return cast(void*)( cast(size_t)_hwnd );
        }

    private:
        enum TIMER_ID = 144;

        HWND _hwnd;

        WNDCLASSW _wndClass;

        HRGN _updateRegion;
        HRGN _clipRegion;
        bool _useFLStudioBridgeWorkaround;

        Vec!ubyte _updateRgbBuf;
        Vec!box2i _updateRects;

        long _performanceCounterDivider;
        uint _timeAtCreationInMs;
        uint _lastMeasturedTimeInMs;

        IWindowListener _listener; // contract: _listener must only be used in the message callback

        ImageRef!RGBA _wfb; // framebuffer reference

        bool _terminated = false;
        int _width = 0;
        int _height = 0;

        int _mouseX = 0;
        int _mouseY = 0;

        bool shiftPressed = false;

        // Last MouseCursor used. This is to avoid updating the cursor
        // more often than necessary
        // Default value of pointer
        MouseCursor _lastMouseCursor = MouseCursor.pointer;

        /// Propagates mouse events.
        /// Returns: true if event handled.
        bool mouseClick(int mouseX, int mouseY, MouseButton mb, bool isDoubleClick, WPARAM wParam)
        {
            SetFocus(_hwnd);   // get keyboard focus
            SetCapture(_hwnd); // start mouse capture
            bool consumed = _listener.onMouseClick(mouseX, mouseY, mb, isDoubleClick, getMouseState(wParam));
            return consumed;
        }

        /// ditto
        bool mouseRelease(int mouseX, int mouseY, MouseButton mb, WPARAM wParam)
        {
            ReleaseCapture();
            bool consumed = _listener.onMouseRelease(mouseX, mouseY, mb, getMouseState(wParam));
            return consumed;
        }

        wchar[43] _className; // Zero-terminated class name

        void generateClassName() nothrow @nogc
        {
            generateNullTerminatedRandomUUID!wchar(_className, "dplug_"w);
        }

        int setMouseCursor()
        {
            MouseCursor cursor = _listener.getMouseCursor();

            if(cursor != _lastMouseCursor)
            {
                CURSORINFO pci;
                pci.cbSize = CURSORINFO.sizeof;
                GetCursorInfo(&pci);

                // If the cursor we want to display is "hidden" and the cursor is being shown
                // then we will hide the cursor.
                // If the cursor we want to display is anything other than "hidden" and the
                // cursor is being hidden already, we will set it to show 
                // (this triggers a WM_SETCURSOR which will call this to set the cursor)
                // lastly if the above conditions are false then we will set the cursor
                if(cursor == MouseCursor.hidden && pci.flags == CURSOR_SHOWING)
                {
                    ShowCursor(false);
                }
                else if(cursor != MouseCursor.hidden && pci.flags == 0)
                {
                    ShowCursor(true);
                }
                else
                {
                    auto cursorId = mouseCursorToCursorId(cursor);
                    HCURSOR hc = LoadCursorA(NULL, cast(const(char)*)cursorId);
                    SetCursor(hc);
                }
                _lastMouseCursor = cursor;
                return 1;
            }

            return 0;
        }
    }


    extern(Windows) nothrow
    {
        LRESULT windowProcCallback(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
        {
            Win32Window window = cast(Win32Window)( cast(void*)(GetWindowLongPtrA(hwnd, GWLP_USERDATA)) );
            if (window !is null)
                return window.windowProc(hwnd, uMsg, wParam, lParam);
            else
                return DefWindowProcA(hwnd, uMsg, wParam, lParam);
        }
    }

    Key vkToKey(WPARAM vk, bool shiftPressed)pure nothrow @nogc
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
                case 0x30: return Key.digit0;
                case 0x31: return Key.digit1;
                case 0x32: return Key.digit2;
                case 0x33: return Key.digit3;
                case 0x34: return Key.digit4;
                case 0x35: return Key.digit5;
                case 0x36: return Key.digit6;
                case 0x37: return Key.digit7;
                case 0x38: return Key.digit8;
                case 0x39: return Key.digit9;
                case 0x41: return shiftPressed ?  Key.A : Key.a;
                case 0x42: return shiftPressed ?  Key.B : Key.b;
                case 0x43: return shiftPressed ?  Key.C : Key.c;
                case 0x44: return shiftPressed ?  Key.D : Key.d;
                case 0x45: return shiftPressed ?  Key.E : Key.e;
                case 0x46: return shiftPressed ?  Key.F : Key.f;
                case 0x47: return shiftPressed ?  Key.G : Key.g;
                case 0x48: return shiftPressed ?  Key.H : Key.h;
                case 0x49: return shiftPressed ?  Key.I : Key.i;
                case 0x4A: return shiftPressed ?  Key.J : Key.j;
                case 0x4B: return shiftPressed ?  Key.K : Key.k;
                case 0x4C: return shiftPressed ?  Key.L : Key.l;
                case 0x4D: return shiftPressed ?  Key.M : Key.m;
                case 0x4E: return shiftPressed ?  Key.N : Key.n;
                case 0x4F: return shiftPressed ?  Key.O : Key.o;
                case 0x50: return shiftPressed ?  Key.P : Key.p;
                case 0x51: return shiftPressed ?  Key.Q : Key.q;
                case 0x52: return shiftPressed ?  Key.R : Key.r;
                case 0x53: return shiftPressed ?  Key.S : Key.s;
                case 0x54: return shiftPressed ?  Key.T : Key.t;
                case 0x55: return shiftPressed ?  Key.U : Key.u;
                case 0x56: return shiftPressed ?  Key.V : Key.v;
                case 0x57: return shiftPressed ?  Key.W : Key.w;
                case 0x58: return shiftPressed ?  Key.X : Key.x;
                case 0x59: return shiftPressed ?  Key.Y : Key.y;
                case 0x5A: return shiftPressed ?  Key.Z : Key.z;
                case VK_BACK: return Key.backspace;
                case VK_RETURN: return Key.enter;
                case VK_ESCAPE: return Key.escape;
                default: return Key.unsupported;
            }
    }

    SHORT keyState(int vk)
    {
        version(AAX)
            return GetAsyncKeyState(VK_MENU);
        else
            return GetKeyState(VK_MENU);
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
                           keyState(VK_MENU) < 0 );
    }

    HCURSOR mouseCursorToCursorId(MouseCursor cursor)
    {
        switch(cursor)
        {

            case cursor.linkSelect:
            case cursor.drag:
                return IDC_CROSS;
            case cursor.move:
                return IDC_HAND;
            case cursor.horizontalResize:
                return IDC_SIZEWE;
            case cursor.verticalResize:
                return IDC_SIZENS;
            case cursor.pointer:
            default:
                return IDC_ARROW;
        }
        
    }
}
