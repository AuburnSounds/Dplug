//------------------------------------------------------------------------
// Project     : VST SDK
//
// Category    : Interfaces
// Filename    : pluginterfaces/vst/ivsthostapplication.h
// Created by  : Steinberg, 04/2006
// Description : VST Host Interface
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------
module dplug.vst3.ihostapplication;

import dplug.vst3.funknown;
import dplug.vst3.ftypes;

/** Basic Host Callback Interface.
\ingroup vstIHost vst300
- [host imp]
- [passed as 'context' in to IPluginBase::initialize () ]
- [released: 3.0.0]

Basic VST host application interface. */
interface IHostApplication: FUnknown
{
public:
nothrow:
@nogc:
    /** Gets host application name. */
    tresult getName (String128* name);

    /** Creates host object (e.g. Vst::IMessage). */
    tresult createInstance (TUID cid, TUID _iid, void** obj);

    __gshared immutable TUID iid = INLINE_UID(0x58E595CC, 0xDB2D4969, 0x8B6AAF8C, 0x36A664E5);
}
