//-----------------------------------------------------------------------------
// Project     : SDK Core
//
// Category    : SDK Core Interfaces
// Filename    : pluginterfaces/base/fstrdefs.h
// Created by  : Steinberg, 01/2004
// Description : Definitions for handling strings (Unicode / ASCII / Platforms)
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------

module dplug.vst3.fstrdefs;

import dplug.vst3.ftypes;

nothrow:
@nogc:

T* _tstrncpy(T) (T* dest, const(T)* source, uint32 count)
{
    T* start = dest;
    while (count && (*dest++ = *source++) != 0) // copy string
        count--;

    if (count) // pad out with zeros
    {
        while (--count)
            *dest++ = 0;
    }
    return start;
}

tchar* tstrncpy (tchar* dest, const(tchar)* source, uint32 count) 
{
    return _tstrncpy!tchar(dest, source, count);
}

char8* strncpy8 (char8* dest, const(char8)* source, uint32 count) 
{
    return _tstrncpy!char8(dest, source, count);
}

char16* strncpy16 (char16* dest, const(char16)* source, uint32 count) 
{
    return _tstrncpy!char16(dest, source, count);
}

/// Convert UTF-16 to UTF-8
void str16ToStr8 (char* dst, wchar* src, int32 n = -1)
{
    int32 i = 0;
    for (;;)
    {
        if (i == n)
        {
            dst[i] = 0;
            return;
        }

        wchar codeUnit = src[i];
        if (codeUnit >= 127)
            codeUnit = '?';

        dst[i] = cast(char)(codeUnit); // FUTURE: proper unicode conversion, this is US-ASCII only

        if (src[i] == 0)
            break;
        i++;
    }

    while (n > i)
    {
        dst[i] = 0;
        i++;
    }
}

void str8ToStr16 (char16* dst, string src, int32 n = -1)
{
    int32 i = 0;
    for (;;)
    {
        if (i == src.length)
        {
            dst[i] = 0;
            return;
        }

        if (i == n)
        {
            dst[i] = 0;
            return;
        }

        version(BigEndian)
        {
            char8* pChr = cast(char8*)&dst[i];
            pChr[0] = 0;
            pChr[1] = src[i];
        }
        else
        {
            dst[i] = cast(char16)(src[i]);
        }

        if (src[i] == 0)
            break;

        i++;
    }

    while (n > i)
    {
        dst[i] = 0;
        i++;
    }
}

void str8ToStr16 (char16* dst, const(char8)* src, int32 n = -1)
{
    int32 i = 0;
    for (;;)
    {
        if (i == n)
        {
            dst[i] = 0;
            return;
        }

        version(BigEndian)
        {
            char8* pChr = cast(char8*)&dst[i];
            pChr[0] = 0;
            pChr[1] = src[i];
        }
        else
        {
            dst[i] = cast(char16)(src[i]);
        }

        if (src[i] == 0)
            break;

        i++;
    }

    while (n > i)
    {
        dst[i] = 0;
        i++;
    }
}
