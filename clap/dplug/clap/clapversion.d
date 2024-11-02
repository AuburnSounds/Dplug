/*
MIT License

Copyright (c) 2021 Alexandre BIQUE
Copyright (c) 2024 Guillaume PIOLAT

Permission is hereby granted,  free of charge, to any person obtaining
a copy of  this  software  and  associated  documentation  files  (the
"Software"),  to deal in the Software  without restriction,  including
without limitation the rights to use, copy,  modify,  merge,  publish,
distribute,  sublicense,  and/or sell  copies of the Software,  and to
permit persons to whom the Software is furnished to do so,  subject to
the following conditions:

The  above  copyright  notice  and  this  permission  notice  shall be
included  in  all  copies or  substantial  portions of  the  Software.

THE SOFTWARE  IS  PROVIDED "AS IS",  WITHOUT  WARRANTY  OF  ANY  KIND,
EXPRESS OR IMPLIED,  INCLUDING  BUT NOT  LIMITED TO THE  WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT  SHALL THE AUTHORS  OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM,  DAMAGES OR OTHER LIABILITY,  WHETHER IN AN ACTION OF CONTRACT,
TORT  OR OTHERWISE,  ARISING FROM,  OUT OF OR  IN CONNECTION  WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
module dplug.clap.clapversion;

nothrow @nogc:
version(CLAP):

// version.h
enum uint CLAP_VERSION_MAJOR = 1;
enum uint CLAP_VERSION_MINOR = 2;
enum uint CLAP_VERSION_REVISION = 2;

bool CLAP_VERSION_LT(uint maj, uint min, uint rev)
{
    if (CLAP_VERSION_MAJOR < maj) return true;
    if ((maj == CLAP_VERSION_MAJOR) && (CLAP_VERSION_MINOR < min)) 
        return true;
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

bool clap_version_is_compatible(T)(T v) 
{
    // versions 0.x.y were used during development stage and aren't 
    // compatible
    return v.major >= 1;
}

struct clap_version_t 
{
    // This is the major ABI and API design
    // Version 0.X.Y correspond to the development stage, API and ABI 
    // are not stable
    // Version 1.X.Y correspond to the release stage, API and ABI are 
    // stable
    uint major;
    uint minor;
    uint revision;
}

enum CLAP_VERSION = clap_version_t(1, 2, 2);
