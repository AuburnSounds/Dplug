module dplug.gui.window;

import std.process,
       std.string;

version(Windows)
{
    import win32.w32api;
    import win32.winuser;
    import win32.winbase;
    import win32.windef;
    //import core.sys.windows.windows;

    //public import win32.core;

    class Win32Window
    {
    public:
        this(HWND parentWindow)
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
            return DefWindowProcA(hwnd, uMsg, wParam, lParam);
        }

    private:
        HWND _hwnd;
        WNDCLASSW _wndClass;
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
        auto window = new Win32Window(null);
        window.close();
    }
}