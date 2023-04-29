/**
Loading and unloading shared libraries.

Copyright: Derelict Contributors 2005-2015.
Copyright: Guillaume Piolat 2015-2016.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.core.sharedlib;

import dplug.core.nogc;
import dplug.core.vec;

//version = debugSharedLibs;

version(debugSharedLibs)
{
    import core.stdc.stdio;
}

/// Shared library ressource
struct SharedLib
{
nothrow:
@nogc:

    void load(string name)
    {
        version(debugSharedLibs)
        {
            auto lib = CString(name);
            printf("loading dynlib '%s'\n", lib.storage);
        }

        if(isLoaded)
            return;
        _name = name;
        _hlib = LoadSharedLib(name);
        if(_hlib is null)
            assert(false, "Couldn't open the shared library.");
    }

    @disable this(this);

    bool hasSymbol(string symbolName)
    {
        assert(isLoaded());
        void* sym = GetSymbol(_hlib, symbolName);
        return sym != null;
    }

    void* loadSymbol(string symbolName)
    {
        assert(isLoaded());

        version(debugSharedLibs)
        {
            auto sb = CString(symbolName);
            printf("  loading symbol '%s'\n", sb.storage);
        }

        void* sym = GetSymbol(_hlib, symbolName);
        if(!sym)
            assert(false, "Couldn't get symbol.");
        return sym;
    }

    void unload()
    {
        if(isLoaded())
        {
            UnloadSharedLib(_hlib);
            _hlib = null;

            version(debugSharedLibs)
            {
                auto lib = CString(_name);
                printf("unloaded dynlib '%s'\n", lib.storage);
            }
        }
    }

    /// Returns true if the shared library is currently loaded, false otherwise.
    bool isLoaded()
    {
        return (_hlib !is null);
    }

private:
    string _name;
    SharedLibHandle _hlib;
}

/// Loader. In debug mode, this fills functions pointers with null.
abstract class SharedLibLoader
{
nothrow:
@nogc:

    this(string libName)
    {
        _libName = libName;
        version(debugSharedLibs)
        {
            _funcPointers = makeAlignedBuffer!(void**)();
        }
    }

    /// Binds a function pointer to a symbol in this loader's shared library.
    final void bindFunc(void** ptr, string funcName)
    {
        void* func = _lib.loadSymbol(funcName);
        version(debugSharedLibs)
        {
            _funcPointers.pushBack(ptr);
        }
        *ptr = func;
    }

    final void load()
    {
        _lib.load(_libName);
        loadSymbols();
    }

    // Unload the library, and sets all functions pointer to null.
    final void unload()
    {
        _lib.unload();

        version(debugSharedLibs)
        {
            // Sets all registered functions pointers to null
            // so that they can't be reused
            foreach(ptr; _funcPointers[])
                *ptr = null;

            _funcPointers.clearContents();
        }
    }

protected:

    /// Implemented by subclasses to load all symbols with `bindFunc`.
    abstract void loadSymbols();

private:
    string _libName;
    SharedLib _lib;
    version(debugSharedLibs)
        Vec!(void**) _funcPointers;
}


private:

alias void* SharedLibHandle;

version(Posix)
{
    import core.sys.posix.dlfcn;

    private {

        SharedLibHandle LoadSharedLib(string libName) nothrow @nogc
        {
            return dlopen(CString(libName), RTLD_NOW);
        }

        void UnloadSharedLib(SharedLibHandle hlib) nothrow @nogc
        {
            dlclose(hlib);
        }

        void* GetSymbol(SharedLibHandle hlib, string symbolName) nothrow @nogc
        {
            return dlsym(hlib, CString(symbolName));
        }
    }
}
else version(Windows)
{
    import core.sys.windows.winbase;

    private {
        nothrow @nogc
        SharedLibHandle LoadSharedLib(string libName)
        {
            return LoadLibraryA(CString(libName));
        }

        nothrow @nogc
        void UnloadSharedLib(SharedLibHandle hlib)
        {
            FreeLibrary(hlib);
        }

        nothrow @nogc
        void* GetSymbol(SharedLibHandle hlib, string symbolName)
        {
            return GetProcAddress(hlib, CString(symbolName));
        }
    }
} else {
    static assert(0, "Derelict does not support this platform.");
}
