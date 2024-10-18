/*
MIT License

Copyright (c) 2021 Alexandre BIQUE
Copyright (c) 2024 Guillaume PIOLAT

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
module dplug.clap.entry;

nothrow @nogc:

import dplug.core.runtime;

// version.h

import dplug.clap;

enum uint CLAP_VERSION_MAJOR = 1;
enum uint CLAP_VERSION_MINOR = 2;
enum uint CLAP_VERSION_REVISION = 2;
/*
clap_version_t CLAP_VERSION_INIT(uint major, uint minor, uint rev) 
{
    return clap_version(major, minor, rev);
}*/

bool CLAP_VERSION_LT(uint maj, uint min, uint rev)
{
    if (CLAP_VERSION_MAJOR < maj) return true;
    if ((maj == CLAP_VERSION_MAJOR) && (CLAP_VERSION_MINOR < min)) return true;
    if ((maj == CLAP_VERSION_MAJOR) && (min == CLAP_VERSION_MINOR) 
        && (CLAP_VERSION_REVISION < rev))
        return true;
    return false;
}

bool CLAP_VERSION_EQ(uint maj, uint min, uint rev)
{
    return maj == CLAP_VERSION_MAJOR
        && min == CLAP_VERSION_MINOR
        && rev == CLAP_VERSION_REVISION;
}

bool CLAP_VERSION_GE(uint maj, uint min, uint rev)
{
    return ! CLAP_VERSION_LT(maj, min, rev);
}




bool clap_version_is_compatible(const(clap_version_t) v) 
{
   // versions 0.x.y were used during development stage and aren't compatible
   return v.major >= 1;
}



// entry.h



/* Entry point */
//CLAP_EXPORT extern const clap_plugin_entry_t clap_entry;


const(void)* clap_factory_templated(ClientCLass)(const(char)* factory_id) 
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();

    import dplug.core;
    debugLogf("Hey from factory");
    return null; // TODO
}