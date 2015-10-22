/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 and later Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
module dplug.window.win32window;

import core.thread;

import std.process,
       std.string;

import gfm.math;

import ae.utils.graphics;

import dplug.core.fpcontrol;
import dplug.window.window;


version(Windows)
{
    import std.uuid;

    import win32.w32api;
    import win32.winuser;
    import win32.winbase;
    import win32.windef;
    import win32.wingdi;


    HINSTANCE getModuleHandle()
    {
        return GetModuleHandleA(null);
    }

    final class Win32Window : IWindow
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

            // Generates an unique class name
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

            _listener = listener;

            // Sets this as user data
            SetWindowLongPtrA(_hwnd, GWLP_USERDATA, cast(LONG_PTR)( cast(void*)this ));

            int mSec = 15; // refresh at 60 hz if possible
            SetTimer(_hwnd, TIMER_ID, mSec, null);
            SetFocus(_hwnd);

            // Get performance counter frequency
            LARGE_INTEGER performanceFrequency;
            BOOL res = QueryPerformanceFrequency(&performanceFrequency);
            assert(res != 0); // since XP it is always supported
            _performanceCounterDivider = performanceFrequency.QuadPart;

            // Get reference time
            _timeAtCreationInMs = getTimeMs();
            _lastMeasturedTimeInMs = _timeAtCreationInMs;
        }

        ~this()
        {
            if (_hwnd != null)
            {
               DestroyWindow(_hwnd);
                _hwnd = null;

                // Unregister the window class, which was unique
                UnregisterClassW(_wndClass.lpszClassName, getModuleHandle());

                if (_buffer != null)
                {
                    VirtualFree(_buffer, 0, MEM_RELEASE);
                    _buffer = null;
                }
            }
        }

        /// Returns: true if window size changed.
        bool updateSizeIfNeeded()
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
                return true;
            }
            else
                return false;
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
                    {
                        if (_listener.onKeyDown(key))
                            sendRepaintIfUIDirty(); // do not wait for the timer
                    }
                    else
                    {
                        if (_listener.onKeyUp(key))
                            sendRepaintIfUIDirty(); // do not wait for the timer
                    }

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
                        sendRepaintIfUIDirty();
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
                        bool sizeChanged = updateSizeIfNeeded();

                        // TODO: check resize work

                        ImageRef!RGBA wfb;
                        wfb.w = _width;
                        wfb.h = _height;
                        wfb.pitch = byteStride(_width);
                        wfb.pixels = cast(RGBA*)_buffer;

                        // For efficiency purpose, render in BGRA for Windows
                        _listener.onDraw(wfb, WindowPixelFormat.BGRA8);

                        box2i areaToRedraw = box2i(r.left, r.top, r.right, r.bottom);

                        box2i[] areasToRedraw = (&areaToRedraw)[0..1];
                        swapBuffers(wfb, areasToRedraw);
                    }
                    return 0;
                }

                case WM_CLOSE:
                {
                    this.destroy();
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
                        sendRepaintIfUIDirty();
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
            PAINTSTRUCT paintStruct;
            HDC hdc = BeginPaint(_hwnd, &paintStruct);

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
                    SetDIBitsToDevice(hdc, area.min.x, area.min.y, area.width, area.height,
                                      area.min.x, -area.min.y - area.height + _height, 0, _height, _buffer, cast(BITMAPINFO *)&bmi, DIB_RGB_COLORS);
                }
            }

            EndPaint(_hwnd, &paintStruct);
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

        override void debugOutput(string s)
        {
            OutputDebugStringA(toStringz(s ~ "\n"));
        }

        override uint getTimeMs()
        {
            LARGE_INTEGER perfCounter;
            BOOL err = QueryPerformanceCounter(&perfCounter);
            assert(err != 0); // always supported since XP
            double time = (perfCounter.QuadPart * 1000 + (_performanceCounterDivider >> 1)) / cast(double)_performanceCounterDivider;
            return cast(uint)(time);
        }

    private:
        enum TIMER_ID = 144;

        HWND _hwnd;

        WNDCLASSW _wndClass;
        wstring _className;

        long _performanceCounterDivider;
        uint _timeAtCreationInMs;
        uint _lastMeasturedTimeInMs;

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
            bool consumed = _listener.onMouseClick(mouseX, mouseY, mb, isDoubleClick, getMouseState(wParam));
            if (consumed)
                sendRepaintIfUIDirty(); // do not wait for the timer
            return consumed;
        }

        /// ditto
        bool mouseRelease(int mouseX, int mouseY, MouseButton mb, WPARAM wParam)
        {
            ReleaseCapture();
            bool consumed = _listener.onMouseRelease(mouseX, mouseY, mb, getMouseState(wParam));
            if (consumed)
                sendRepaintIfUIDirty(); // do not wait for the timer
            return consumed;
        }

        /// Provokes a WM_PAINT if some UI element is dirty.
        /// TODO: this function should be as fast as possible
        void sendRepaintIfUIDirty()
        {
            _listener.recomputeDirtyAreas();
            box2i dirtyRect = _listener.getDirtyRectangle();
            if (!dirtyRect.empty())
            {
                RECT r = RECT(dirtyRect.min.x, dirtyRect.min.y, dirtyRect.max.x, dirtyRect.max.y);
                // TODO: maybe use RedrawWindow instead
                InvalidateRect(_hwnd, &r, FALSE); // TODO: invalidate rects one by one
                UpdateWindow(_hwnd);

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
            FPControl fpctrl;
            fpctrl.initialize();
            
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
            case VK_ESCAPE: return Key.escape;
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
