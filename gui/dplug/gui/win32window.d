module dplug.gui.win32window;

import std.process,
       std.string;

import ae.utils.graphics;

import dplug.gui.window,
       dplug.gui.windowlistener;


version(Windows)
{
    import win32.w32api;
    import win32.winuser;
    import win32.winbase;
    import win32.windef;
    import win32.wingdi;
    //import core.sys.windows.windows;

    //public import win32.core;

    class Win32Window : IWindow
    {
    public:
        this(HWND parentWindow /*, IWindowListener listener*/)
        {
            _wndClass.style = CS_DBLCLKS | CS_HREDRAW | CS_VREDRAW;
            _wndClass.lpfnWndProc = &windowProcCallback;
            _wndClass.cbClsExtra = 0;
            _wndClass.cbWndExtra = 0;
            _wndClass.hInstance = GetModuleHandleA(null); // TODO: should be the HINSTANCE given by DLL main!
            _wndClass.hIcon = null;
            _wndClass.hCursor = LoadCursorA(null, IDC_ARROW);
            _wndClass.hbrBackground = null;
            _wndClass.lpszMenuName = null;
            _wndClass.lpszClassName = cast(wchar*)windowClassName.ptr;

            if (!RegisterClassW(&_wndClass))
                throw new Exception("Couldn't register Win32 class");

            _hwnd = CreateWindowW(cast(wchar*)windowClassName.ptr, null, /*WS_CHILD | */WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
                                 parentWindow, null,
                                 GetModuleHandleA(null),  // TODO: is it correct?
                                 cast(void*)this);

            if (_hwnd is null)
            {
                DWORD err = GetLastError();
                throw new Exception(format("Couldn't create a Win32 window (error %s)", err));
            }

            //_listener = listener;

            _buffer = Image!RGBA(640, 480);

            // Sets this as user data
            SetWindowLongPtrA(_hwnd, GWLP_USERDATA, cast(LONG_PTR)( cast(void*)this ));
        }

        ~this()
        {
            close();
        }

        void close()
        {
            if (_hwnd != null)
            {
                DestroyWindow(_hwnd);
                _hwnd = null;
            }
            UnregisterClassA("dplug_window", GetModuleHandle(null)); // TODO: should be the HINSTANCE given by DLL main!
        }

        LRESULT windowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
        {
            if (uMsg == WM_CREATE)
            {
                int mSec = 16; // refresh at 60 hz 
                SetTimer(hwnd, TIMER_ID, mSec, null);
                SetFocus(hwnd);
                return 0;
            }

            switch (uMsg)
            {
                case WM_KEYDOWN:
                {
                    return 0;
                }
                case WM_TIMER:
                {
                    if (wParam == TIMER_ID)
                    {
                        _buffer.pixels[] = RGBA(255, 128, 64, 255);
                        _listener.onDraw(&_buffer);
                        swapBuffers();
                    }
                    return 0;

                default:
                    return DefWindowProcA(hwnd, uMsg, wParam, lParam);
                }
            }
        }

        // Implements IWindow
        override void swapBuffers()
        {            
            PAINTSTRUCT paintStruct;
            HDC hdc = BeginPaint(_hwnd, &paintStruct);
			HDC hdcMem = CreateCompatibleDC(hdc);


            // TODO swap R and B
			RECT winsize;
			GetClientRect(_hwnd, &winsize);

			HBITMAP hBitmap = CreateBitmap(cast(uint)_buffer.w, cast(uint)_buffer.h, 1, 32, _buffer.pixels.ptr);
			HGDIOBJ oldBitmap = SelectObject(hdcMem, hBitmap);

			HBITMAP bitmap;
			GetObjectA(hBitmap, HBITMAP.sizeof, &bitmap);

			// auto stretch the image buffer to client screen size
			StretchBlt(hdc, 0, 0, cast(uint)_buffer.w, cast(uint)_buffer.h, hdcMem, 0, 0, winsize.right, winsize.bottom, SRCCOPY);

			SelectObject(hdcMem, oldBitmap);

			EndPaint(_hwnd, &paintStruct);
			DeleteDC(hdcMem);

			// perform the actual redraw!
			InvalidateRgn(_hwnd, null, false);
        }

        override Image!RGBA* getRGBABuffer()
        {
            return &_buffer;
        }

    private:
        enum TIMER_ID = 0xDEADBEEF;

        HWND _hwnd;
        WNDCLASSW _wndClass;
        //IWindowListener _listener;
        Image!RGBA _buffer;
    }

    enum wstring windowClassName = "Dplug window\0"w;

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

    unittest
    {
        class MockListener : IWindowListener
        {


        }
                _buffer.pixels[] = RGBA(255, 128, 64, 255);

        auto window = new Win32Window(null);
        
        import core.thread;
        Thread.sleep( dur!("msecs")( 1000 ) );

        window.close();
    }
}