//-----------------------------------------------------------------------------
// Project     : SDK Core
//
// Category    : SDK Core Interfaces
// Filename    : pluginterfaces/base/fplatform.h
//               pluginterfaces/base/falignpush.h
// Created by  : Steinberg, 01/2004
// Description : Detect platform and set define
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------

module dplug.vst3.fplatform;


deprecated enum kLittleEndian = 0;
deprecated enum kBigEndian = 1;

version(Windows)
{
    enum COM_COMPATIBLE = 1;
}
else
{
    enum COM_COMPATIBLE = 0;
}


// #pragma pack translation
// use align(vst3Alignment): inside structs
version(OSX)
{
    static if ((void*).sizeof == 8)
    {
        // 64-bit macOS
        // no need in packing here
        // MAYDO verify what it means because we shouldn't use align in the first place here
        enum vst3Alignment = 1;
    }
    else
    {
        enum vst3Alignment = 1;
    }
}
else version(Windows)
{
    static if ((void*).sizeof == 8)
    {
        // no need in packing here
        // MAYDO verify what it means because we shouldn't use align in the first place here
        enum vst3Alignment = 16;
    }
    else
    {
        enum vst3Alignment = 8;
    }
}
else
{
    enum vst3Alignment = 0;
}