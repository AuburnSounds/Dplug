module dplug.gui.win32window;

import std.process,
       std.string;

import ae.utils.graphics;

import dplug.gui.window,
       dplug.gui.windowlistener;

import std.stdio;

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
        this(HWND parentWindow, IWindowListener listener)
        {
            _wndClass.style = CS_DBLCLKS | CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
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

            _hwnd = CreateWindowW(cast(wchar*)windowClassName.ptr, null, /*WS_CHILD | */ WS_VISIBLE | WS_POPUP, CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
                                 parentWindow, null,
                                 GetModuleHandleA(null),  // TODO: is it correct?
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

            _compatibleDC = CreateCompatibleDC(_windowDC);

            _listener = listener;

            _buffer = Image!RGBA(64, 64);

            // Sets this as user data
            SetWindowLongPtrA(_hwnd, GWLP_USERDATA, cast(LONG_PTR)( cast(void*)this ));

            int mSec = 30; // refresh at 60 hz 
            SetTimer(_hwnd, TIMER_ID, mSec, null);
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
                // renew compatible bitmap
                if (_compatibleBitmap != null)
                {
                    DeleteObject(_compatibleBitmap);
                    _compatibleBitmap = null;
                }

                _compatibleBitmap = CreateCompatibleBitmap(_windowDC, newWidth, newHeight);
                SelectObject(_compatibleDC, _compatibleBitmap);
                
                // Extends buffer
                _buffer.size(newWidth, newHeight);
                
                _width = newWidth;
                _height = newHeight;
            }
        }

        void close()
        {
            if (_hwnd != null)
            {
                DeleteDC(_compatibleDC);
                DestroyWindow(_hwnd);
                _hwnd = null;
            }
            UnregisterClassA("dplug_window", GetModuleHandle(null)); // TODO: should be the HINSTANCE given by DLL main!
        }

        LRESULT windowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
        {
            if (uMsg == WM_CREATE)
            {
                /*int mSec = 30; // refresh at 60 hz 
                SetTimer(hwnd, TIMER_ID, mSec, null);

                SetFocus(hwnd);
                */
                writeln("WM_CREATE");
                return 0;
            }

        //    writeln("ho");

            switch (uMsg)
            {
                case WM_KEYDOWN:
                {
                    return 0;
                }

                case WM_PAINT:
                {
                    updateBufferSizeIfNeeded();
                    _listener.onDraw(&_buffer);
                    swapBuffers();
                    //writeln("WM_PAINT");
                    return 0;
                }

                case WM_CLOSE:
                {
					DestroyWindow(hwnd);
                    return 0;
                }                

                case WM_DESTROY:
                {
                    //KillTimer(hwnd, TIMER_ID);
                    PostQuitMessage(0);
                    return 0;
                }

                case WM_TIMER:
                {
                    writeln("WM_TIMER");
                    if (wParam == TIMER_ID)
                    {
                       // writeln("hey");
                        
                    }
                    return 0;

                case WM_SIZE:
                    _width = LOWORD(lParam);
                    _height = HIWORD(lParam);
                    return 0;

                default:
                    return DefWindowProcA(hwnd, uMsg, wParam, lParam);
                }
            }
        }

        // Implements IWindow
        void swapBuffers()
        {   
            // TODO use BITMAPV4HEADER to swap R and B

            // Copy the content of _buffer into _compatibleBitmap, that line does the conversion
            BITMAPINFO bi = BITMAPINFO.init;
            with(bi.bmiHeader)
            {
                biSize = BITMAPINFOHEADER.sizeof;
                biWidth = _width;
                biHeight = _height;
                biPlanes = 1;
                biBitCount = 32;
                biCompression = BI_RGB;
                biSizeImage = _width * _height * 4;
            }

            if (0 == SetDIBits(_compatibleDC, _compatibleBitmap, 0, _height, _buffer.pixels.ptr, &bi, DIB_RGB_COLORS))
            {
                DWORD err = GetLastError();
                throw new Exception(format("SetDIBits failed (error %s)", err));
            }   

            PAINTSTRUCT paintStruct;
            HDC hdc = BeginPaint(_hwnd, &paintStruct);
            assert(hdc == _windowDC); // since we are CS_OWNDC            

            // Blit pixels from compatible DC to DC
            BitBlt(_windowDC, 0, 0, _width, _height, _compatibleDC, 0, 0, SRCCOPY);

			EndPaint(_hwnd, &paintStruct);
			
			// invalidate to schedule a paint
			InvalidateRgn(_hwnd, null, false);
        }

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
        HDC _compatibleDC;
        HBITMAP _compatibleBitmap = null;

        WNDCLASSW _wndClass;
        IWindowListener _listener;
        Image!RGBA _buffer;
        bool _terminated = false;
        int _width = 0;
        int _height = 0;        
    }

    enum wstring windowClassName = "Dplug window\0"w;

    extern(Windows) nothrow
    {
        LRESULT windowProcCallback(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
        {
            import std.stdio;
            try
            {
//                writeln("he");
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

            override void onKeyDown(Key key)
            {
            }
            override void onKeyUp(Key up)
            {
            }
            override void onDraw(Image!RGBA* image)
            {
                //DWORD count = GetTickCount();
                for (int j = 0; j < image.h; ++j)
                    for (int i = 0; i < image.w; ++i)
                    {
                        image.pixels[i + j * image.w] = RGBA(255, 128, 0, 255);
                    }

                //image.pixels[] = RGBA(255, 128, 0, 255);
            }
        }
                

        IWindow window = new Win32Window(null, new MockListener());
        
        import core.thread;

        while (!window.terminated())
        {
            window.waitEventAndDispatch();
        }
    }
}