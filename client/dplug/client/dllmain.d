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
module dplug.client.dllmain;


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
        const char[] DLLEntryPoint = ``;
/*
        extern (C) {
            pragma(LDC_global_crt_ctor, 0)
            void initRuntime()
            {
                import core.runtime;
                Runtime.initialize();
            }

            pragma(LDC_global_crt_dtor, 0)
            void deinitRuntime()
            {
                import core.runtime;
                Runtime.terminate();
            }
        }`;*/
    }


    // Workaround Issue #15060
    // https://issues.dlang.org/show_bug.cgi?id=15060
    // Found by Martin Nowak and bitwise
    // Trade-off a crash for a leak :|

    extern(C) int sysctlbyname(const char *, void *, size_t *, void *, size_t);

    bool needWorkaround15060() nothrow
    {
//        return true;

        import std.regex;
        import std.string;
        import std.conv;

        try
        {
            char[128] str;
            size_t size = 128;
            sysctlbyname("kern.osrelease", str.ptr, &size, null, 0);
            string versionString = fromStringz(str.ptr).idup;

            auto re = regex(`(\d+)\.(\d+)\.(\d+)`);

            if (auto captures = matchFirst(versionString, re))
            {
                // >= OS X 10.7
                // The workaround is needed in 10.10 and 10.9 but harmful in 10.6.8
                // TODO find the real crossing-point
                int kernVersion = to!int(captures[1]);
                return kernVersion >= 11;
            }
            else
                return false;
        }
        catch(Exception e)
        {
            return false;
        }
    }

    alias dyld_image_states = int;
    enum : dyld_image_states
    {
        dyld_image_state_initialized = 50,
    }

    __gshared bool didInitRuntime = false;

    extern(C) nothrow
    {
        alias dyld_image_state_change_handler = const(char)* function(dyld_image_states state, uint infoCount, void* dyld_image_info);
    }

    extern(C) const(char)* ignoreImageLoad(dyld_image_states state, uint infoCount, void* dyld_image_info) nothrow
    {
        return null;
    }

    extern(C) void dyld_register_image_state_change_handler(dyld_image_states state, bool batch, dyld_image_state_change_handler handler);


    void runtimeInitWorkaround15060()
    {
        import core.runtime;

        if(!didInitRuntime)
        {
            Runtime.initialize();

            if (needWorkaround15060)
                dyld_register_image_state_change_handler(dyld_image_state_initialized, false, &ignoreImageLoad);

            didInitRuntime = true;
        }
    }
}
else
    static assert(false, "OS unsupported");
