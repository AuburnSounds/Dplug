// See licenses/WDL_license.txt
module dplug.plugin.dllmain;


__gshared void* gModuleHandle = null;


version(Windows)
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = q{
            import std.c.windows.windows;
            import core.sys.windows.dll;

            extern (Windows)
                BOOL DllMain(HINSTANCE hInstance, ULONG ulReason, LPVOID pvReserved)
            {
                switch (ulReason)
                {
                    case DLL_PROCESS_ATTACH:
                        gModuleHandle = cast(void*)hInstance;
                        dll_process_attach(hInstance, true);
                        break;

                    case DLL_PROCESS_DETACH:
                        dll_process_detach(hInstance, true);
                        break;

                    case DLL_THREAD_ATTACH:
                        dll_thread_attach(false, true);
                        break;

                    case DLL_THREAD_DETACH:
                        dll_thread_attach(true, true);
                        break;

                    default:
                        break;
                }
                return true;
            }
        };
    }
}
else
{
     template DLLEntryPoint()
     {
     }
}
