//------------------------------------------------------------------------
// Project     : Steinberg Module Architecture SDK
//
// Category    : Basic Host Service Interfaces
// Filename    : pluginterfaces/base/iupdatehandler.h
// Created by  : Steinberg, 01/2004
// Description : Update handling
//
//-----------------------------------------------------------------------------
// This file is part of a Steinberg SDK. It is subject to the license terms
// in the LICENSE file found in the top-level directory of this distribution
// and at www.steinberg.net/sdklicenses. 
// No part of the SDK, including this file, may be copied, modified, propagated,
// or distributed except according to the terms contained in the LICENSE file.
//-----------------------------------------------------------------------------
module dplug.vst3.iupdatehandler;

import dplug.vst3.ftypes;

interface IUpdateHandler : FUnknown
{
public:
nothrow:
@nogc:
    /** Install update notification for given object. It is essential to
        remove all dependencies again using 'removeDependent'! Dependencies
        are not removed automatically when the 'object' is released! 
    \param object : interface to object that sends change notifications 
    \param dependent : interface through which the update is passed */
    tresult addDependent (FUnknown object, IDependent dependent);
    
    /** Remove a previously installed dependency.*/
    tresult removeDependent (FUnknown object, IDependent dependent);

    /** Inform all dependents, that object has changed. 
    \param object is the object that has changed
    \param message is a value of enum IDependent::ChangeMessage, usually  IDependent::kChanged - can be
                     a private message as well (only known to sender and dependent)*/
    tresult triggerUpdates (FUnknown object, int32 message);

    /** Same as triggerUpdates, but delivered in idle (usefull to collect updates).*/
    tresult deferUpdates (FUnknown object, int32 message);

    immutable __gshared TUID iid = INLINE_UID(0xF5246D56, 0x86544d60, 0xB026AFB5, 0x7B697B37);
}


interface IDependent: FUnknown
{
public:
nothrow:
@nogc:
    /** Inform the dependent, that the passed FUnknown has changed. */
    void update (FUnknown changedUnknown, int32 message);

    alias ChangeMessage = int;
    enum : ChangeMessage 
    {
        kWillChange,
        kChanged,
        kDestroyed,
        kWillDestroy,

        kStdChangeMessageLast = kWillDestroy
    }
   
    __gshared immutable TUID iid = INLINE_UID(0xF52B7AAE, 0xDE72416d, 0x8AF18ACE, 0x9DD7BD5E);
}


