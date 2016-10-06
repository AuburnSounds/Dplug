/*

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

*/
module derelict.util.sharedlib;

import std.string;

import derelict.util.exception,
       derelict.util.nogc,
       derelict.util.system;

alias void* SharedLibHandle;

static if(Derelict_OS_Posix) {
    import core.sys.posix.dlfcn;

    enum LDFlags
    {
        rtldLocal = RTLD_LOCAL,
        rtldLazy = RTLD_LAZY,
        rtldNow = RTLD_NOW,
        rtldGlobal = RTLD_GLOBAL,
    }

    void derelictLDFlags(LDFlags flags) { ldFlags = flags; }

    private {
        LDFlags ldFlags = LDFlags.rtldNow;

        SharedLibHandle LoadSharedLib(string libName) nothrow @nogc
        {
            return dlopen(CString(libName), ldFlags);
        }

        void UnloadSharedLib(SharedLibHandle hlib) nothrow @nogc
        {
            dlclose(hlib);
        }

        void* GetSymbol(SharedLibHandle hlib, string symbolName) nothrow @nogc
        {
            return dlsym(hlib, CString(symbolName));
        }

        string GetErrorStr()
        {
            import std.conv : to;

            auto err = dlerror();
            if(err is null)
                return "Uknown Error";

            return to!string(err);
        }
    }
} else static if(Derelict_OS_Windows) {
    import core.sys.windows.windows;

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

        nothrow @nogc
        string GetErrorStr()
        {
            import std.windows.syserror;
            DWORD err = GetLastError();
            return assumeNothrowNoGC(
                    (DWORD err)
                    {
                        return sysErrorString(err);
                    }
                )(err);
        }
    }
} else {
    static assert(0, "Derelict does not support this platform.");
}

/++
 Low-level wrapper of the even lower-level operating-specific shared library
 loading interface.

 While this interface can be used directly in applications, it is recommended
 to use the interface specified by derelict.util.loader.SharedLibLoader
 to implement bindings. SharedLib is designed to be the base of a higher-level
 loader, but can be used in a program if only a handful of functions need to
 be loaded from a given shared library.
+/
struct SharedLib
{
    /++
     Finds and loads a shared library, using names to find the library
     on the file system.

     If multiple library names are specified in names, a SharedLibLoadException
     will only be thrown if all of the libraries fail to load. It will be the head
     of an exceptin chain containing one instance of the exception for each library
     that failed.


     Params:
        names = An array containing one or more shared library names,
                with one name per index.
     Throws:    SharedLibLoadException if the shared library or one of its
                dependencies cannot be found on the file system.
                SymbolLoadException if an expected symbol is missing from the
                library.
    +/
    version(doNotUseRuntime)
    {
        nothrow @nogc
        void load(string[] names)
        {
            if(isLoaded)
                return;

            foreach(n; names) {
                _hlib = LoadSharedLib(n);
                if(_hlib !is null) {
                    _name = n;
                    break;
                }
            }

            if(!isLoaded) {
                assert(false);
            }
        }
    }
    else
    {
        void load(string[] names)
        {
            if(isLoaded)
                return;

            string[] failedLibs;
            string[] reasons;

            foreach(n; names) {
                _hlib = LoadSharedLib(n);
                if(_hlib !is null) {
                    _name = n;
                    break;
                }

                failedLibs ~= n;
                reasons ~= GetErrorStr();
            }

            if(!isLoaded) {
                SharedLibLoadException.throwNew(failedLibs, reasons);
            }
        }
    }

    /++
     Loads the symbol specified by symbolName from a shared library.

     Params:
        symbolName =        The name of the symbol to load.
        doThrow =   If true, a SymbolLoadException will be thrown if the symbol
                    is missing. If false, no exception will be thrown and the
                    ptr parameter will be set to null.
     Throws:        SymbolLoadException if doThrow is true and a the symbol
                    specified by funcName is missing from the shared library.
    +/
    version(doNotUseRuntime)
    {
        // Unfortunately we can't let @nogc be inferred because this function is not a template.
        nothrow @nogc
        void* loadSymbol(string symbolName, bool doThrow = true)
        {
            void* sym = GetSymbol(_hlib, symbolName);
            if(doThrow && !sym) {
                auto result = ShouldThrow.Yes;
                if(_onMissingSym !is null)
                    result = _onMissingSym(symbolName);
                if(result == ShouldThrow.Yes)
                    assert(false);
            }

            return sym;
        }
    }
    else
    {
        void* loadSymbol(string symbolName, bool doThrow = true)
        {
            void* sym = GetSymbol(_hlib, symbolName);
            if(doThrow && !sym) {
                auto result = ShouldThrow.Yes;
                if(_onMissingSym !is null)
                    result = _onMissingSym(symbolName);
                if(result == ShouldThrow.Yes)
                    throw new SymbolLoadException(_name, symbolName);
            }

            return sym;
        }
    }

    /++
     Unloads the shared library from memory, invalidating all function pointers
     which were assigned a symbol by one of the load methods.
    +/
    nothrow @nogc
    void unload()
    {
        if(isLoaded) {
            UnloadSharedLib(_hlib);
            _hlib = null;
        }
    }


    /// Returns the name of the shared library.
    @property @nogc nothrow
    string name() { return _name; }

    /// Returns true if the shared library is currently loaded, false otherwise.
    @property @nogc nothrow
    bool isLoaded() { return (_hlib !is null); }

    /++
     Sets the callback that will be called when an expected symbol is
     missing from the shared library.

     Params:
        callback =      A delegate that returns a value of type
                        derelict.util.exception.ShouldThrow and accepts
                        a string as the sole parameter.
    +/
    @property @nogc nothrow
    void missingSymbolCallback(MissingSymbolCallbackDg callback)
    {
        _onMissingSym = callback;
    }

    /++
     Sets the callback that will be called when an expected symbol is
     missing from the shared library.

     Params:
        callback =      A pointer to a function that returns a value of type
                        derelict.util.exception.ShouldThrow and accepts
                        a string as the sole parameter.
    +/
    @property @nogc nothrow
    void missingSymbolCallback(MissingSymbolCallbackFunc callback)
    {
        import std.functional : toDelegate;
        _onMissingSym = toDelegate(callback);
    }

    /++
     Returns the currently active missing symbol callback.

     This exists primarily as a means to save the current callback before
     setting a new one. It's useful, for example, if the new callback needs
     to delegate to the old one.
    +/
    @property @nogc nothrow
    MissingSymbolCallback missingSymbolCallback() { return _onMissingSym; }

private:
    string _name;
    SharedLibHandle _hlib;
    private MissingSymbolCallbackDg _onMissingSym;
}
