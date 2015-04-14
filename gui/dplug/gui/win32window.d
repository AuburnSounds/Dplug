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

            _listener = listener;

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
            }
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
                    WindowFrameBuffer wfb = WindowFrameBuffer(_buffer, _width, _height, byteStride(_width));

                    bool needRedraw;
                    _listener.onDraw(wfb, needRedraw);

                    if (needRedraw)
                        swapBuffers();
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
            PAINTSTRUCT paintStruct;
            HDC hdc = BeginPaint(_hwnd, &paintStruct);
            assert(hdc == _windowDC); // since we are CS_OWNDC         

            BITMAPV4HEADER bmi = BITMAPV4HEADER.init; // fill with zeroes
            with (bmi)
            {
                bV4Size          = BITMAPV4HEADER.sizeof;
                bV4Width         = _width;
                bV4Height        = -_height;
                bV4Planes        = 1;
                bV4V4Compression = 3; /* BI_BITFIELDS; */
                bV4XPelsPerMeter = 72;
                bV4YPelsPerMeter = 72;
                bV4BitCount      = 32;    
                bV4SizeImage     = byteStride(_width) * _height;
                bV4RedMask       = 255<<0;
                bV4GreenMask     = 255<<8;
                bV4BlueMask      = 255<<16;
                bV4AlphaMask     = 255<<24;
                SetDIBitsToDevice(_windowDC, 0, 0, _width, _height, 0, 0, 0, _height, _buffer, cast(BITMAPINFO *)&bmi, DIB_RGB_COLORS);
            }

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

        WNDCLASSW _wndClass;
        IWindowListener _listener;
        
        // The framebuffer. This should point into commited virtual memory for faster (maybe) upload to device                
        ubyte* _buffer = null; 

        bool _terminated = false;
        int _width = 0;
        int _height = 0;        
    }
    
    // given a width, how long in bytes should scanlines be
    int byteStride(int width)
    {        
        enum alignment = 32;
        int widthInBytes = width * 4;
        return (widthInBytes + (alignment - 1)) & ~(alignment-1);
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
        int first = 0;
        class MockListener : IWindowListener
        {
            override void onKeyDown(Key key)
            {
            }
            override void onKeyUp(Key up)
            {
            }

            override void onDraw(WindowFrameBuffer wfb, out bool needRedraw)
            {
                if (first++ == 0)

                for (int j = 0; j < wfb.height; ++j)
                    for (int i = 0; i < wfb.width; ++i)
                    {
                        int offset = i * 4 + j * wfb.byteStride;
                        wfb.pixels[offset] = i & 255;
                        wfb.pixels[offset+1] = j & 255;
                        wfb.pixels[offset+2] = 0;
                        wfb.pixels[offset+ 3] = 255;
                    }
                needRedraw = true;
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