module dplug.gui.window;

import std.process;
import core.sys.windows.windows;

class Win32Window
{
public:
    this(HWND parentWindow)
    {
        _wndClass.style = CS_DBLCLKS | CS_HREDRAW | CS_VREDRAW;
        _wndClass.lpfnWndProc = wndProc;
        _wndClass.cbClsExtra = 0;
        _wndClass.cbWndExtra = 0;
        _wndClass.hInstance = GetModuleHandle(NULL); // TODO: should be the HINSTANCE given by DLL main!
        _wndClass.hIcon = 0;
        _wndClass.hCursor = LoadCursor(NULL, IDC_ARROW);
        _wndClass.hbrBackground = 0;
        _wndClass.lpszMenuName = null;
        _wndClass.lpszClassName = "dplugClass";

        if (!RegisterClass(&wc))
            throw Exception("Couldn't register Win32 class");

        _hwnd = CreateWindow("dplugClass", "dplug", WS_CHILD | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
                             parentWindow, 0, mHInstance, cast(void*)this);

        if (_hwnd == NULL)
            throw Exception("Couldn't create a Win32 window");
    }

    ~this()
    {
        close();
    }

    void close()
    {
        if (_hwnd != 0)
        {
            DestroyWindow(_hwnd);
            _hwnd = 0;
        }
        UnregisterClass("dplugClass", GetModuleHandle(NULL)); // TODO: should be the HINSTANCE given by DLL main!
    }

private:
    HWND _hwnd;
    WNDCLASSA _wndClass;
}

extern(Windows)
{
    LRESULT wndProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
    {
        return DefWindowProc(hWnd, msg, wParam, lParam);
    }
}

