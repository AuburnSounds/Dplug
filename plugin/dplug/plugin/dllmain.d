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
else version(linux)
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = `
            import core.runtime;
            shared static this()
            {
                Runtime.initialize();
            }

            shared static ~this()
            {
                Runtime.terminate();
            }
        `;
    }
}
else version(OSX)
{
    template DLLEntryPoint()
    {
        const char[] DLLEntryPoint = `
            import core.runtime;
            shared static this()
            {
                Runtime.initialize();
            }

            shared static ~this()
            {
                Runtime.terminate();
            }
        `;
    }
}
else
    static assert(false, "OS unsupported");
