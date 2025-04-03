/**
 * Entry points.
 *
 * Copyright: Guillaume Piolat 2015-2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module dplug.client.dllmain;

/// The one entry point mixin you need
/// Just paste `mixin(pluginEntryPoints!MyPluginClient);` into your main file for a plug-in.
string pluginEntryPoints(ClientClass)()
{
    return
        `
        mixin(DLLEntryPoint!());

        version(VST2)
        {
            import dplug.vst2;
            mixin(VST2EntryPoint!` ~ ClientClass.stringof ~ `);
        }

        version(AU)
        {
            import dplug.au;
            mixin(AUEntryPoint!` ~ ClientClass.stringof ~ `);
        }

        version(VST3)
        {
            import dplug.vst3;
            mixin(VST3EntryPoint!` ~ ClientClass.stringof ~ `);
        }

        version(AAX)
        {
            import dplug.aax;
            mixin(AAXEntryPoint!` ~ ClientClass.stringof ~ `);
        }

        version(LV2)
        {
            import dplug.lv2;
            mixin(LV2EntryPoint!` ~ ClientClass.stringof ~ `);
        }

        version(CLAP)
        {
            import dplug.clap;
            mixin(CLAPEntryPoint!` ~ ClientClass.stringof ~ `);
        }

        version(FLP)
        {
            import dplug.flp;
            mixin(FLPEntryPoint!` ~ ClientClass.stringof ~ `);
        }`;
}

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

version(OSX)
{
    // HACK important to do nothing in this callback, linker will keep this one hopefully
    // This erase a callback in druntime, that crash and creates the horrible #912
    // True fix is #913, getting out of druntime
    extern(C) void _d_dso_registry(void* data)
    {
    }
}


