module dplug.gui.window;

import std.process;
import core.sys.windows.windows;

class Win32Window
{
public:
    this(HWND parentWindow)
    {
        _wndClass.style = CS_DBLCLKS | CS_HREDRAW | CS_VREDRAW;
        _wndClass.lpfnWndProc = &wndProc;
        _wndClass.cbClsExtra = 0;
        _wndClass.cbWndExtra = 0;
        _wndClass.hInstance = GetModuleHandleA(null); // TODO: should be the HINSTANCE given by DLL main!
        _wndClass.hIcon = null;
        _wndClass.hCursor = LoadCursorA(null, IDC_ARROW);
        _wndClass.hbrBackground = null;
        _wndClass.lpszMenuName = null;
        _wndClass.lpszClassName = "dplugClass";

        if (!RegisterClassA(&_wndClass))
            throw new Exception("Couldn't register Win32 class");

        _hwnd = CreateWindowA("dplugClass", "dplug", WS_CHILD | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
                             parentWindow, null,
                             GetModuleHandleA(null),  // TODO: is it correct?
                             cast(void*)this);

        if (_hwnd ==  null)
            throw new Exception("Couldn't create a Win32 window");
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
        //UnregisterClassA("dplugClass", GetModuleHandle(NULL)); // TODO: should be the HINSTANCE given by DLL main!
    }

private:
    HWND _hwnd;
    WNDCLASSA _wndClass;
}

extern(Windows) nothrow
{
    LRESULT wndProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
    {
        return DefWindowProcA(hwnd, uMsg, wParam, lParam);
    }
}

