/**
 * Copyright: Copyright Auburn Sounds 2015-2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.dllmain;

// Dynamic libraries entry point.
// Basically only needed on Windows, on OSX we have other entry points.

version = doNotUseRuntime;

version(Windows)
{
    version(doNotUseRuntime)
    {
        template DLLEntryPoint()
        {
            const char[] DLLEntryPoint = q{
                import std.c.windows.windows;
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
            const char[] DLLEntryPoint = q{
                import std.c.windows.windows;
                import core.sys.windows.dll;

                extern (Windows) BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
                {
                    switch (ulReason)
                    {
                        case DLL_PROCESS_ATTACH:
                            dll_process_attach(hInstance, false);
                            break;

                        case DLL_PROCESS_DETACH:
                            dll_process_detach(hInstance, true);
                            break;

                        case DLL_THREAD_ATTACH:
                            dll_thread_attach(false, true);
                            break;

                        case DLL_THREAD_DETACH:
                            dll_thread_detach(false, true); 
                            break;

                        default:
                            break;
                    }
                    return true;
                }
            };
        }
    }
}
else
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = ``;
    }
}

