/**
 * Windows DLL entry points.
 *
 * Copyright: Copyright Auburn Sounds 2015-2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.dllmain;

// Dynamic libraries entry point.
// Basically only needed on Windows, on POSIX the other entry points are sufficient.

version(Windows)
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = q{
            import core.sys.windows.windef;
            import core.sys.windows.dll;
            extern (Windows) BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
            {
                return true;
            }
        };
    }
}
else
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = ``;
    }
}

