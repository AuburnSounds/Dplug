/*
     File: AUPlugInDispatch.cpp
 Abstract: AUPlugInDispatch.h
  Version: 1.1

 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.

 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.

 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.

 Copyright (C) 2014 Apple Inc. All Rights Reserved.

*/
/**
* Audio Unit plug-in client. Unused yet. Unfinished dispatcher for the Audio Component API.
* Copyright: Copyright Auburn Sounds 2016.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.au.audiocomponentdispatch;

import derelict.carbon;

// Dispatcher for the Audio Component API
// Not implemented yet

import core.stdc.stdio;


struct AudioComponentPlugInInstance
{
    AudioComponentPlugInInterface iface;
    //AUClient auclient;
}

extern(C) nothrow
{
    OSStatus audioComponentOpen(void *self, AudioComponentInstance mInstance)
    {
        /*
            OSStatus result = noErr;
    try {
        ComponentInitLocker lock;

        ComponentBase::sNewInstanceType = ComponentBase::kAudioComponentInstance;
        ComponentBase *cb = (ComponentBase *)(*ACPI->mConstruct)(&ACPI->mInstanceStorage, compInstance);
        cb->PostConstructor();  // allows base class to do additional initialization
        // once the derived class is fully constructed
        result = noErr;
    }
    COMPONENT_CATCH
    if (result)
        delete ACPI;
    return result;
    */
        import core.stdc.stdio;
        printf("audioComponentOpen %p %p\n", self, mInstance);
        return noErr;
    }

    OSStatus audioComponentClose(void *self)
    {
        /*
            OSStatus result = noErr;
    try {
        if (ACImp) {
            ACImp->PreDestructor();
            (*ACPI->mDestruct)(&ACPI->mInstanceStorage);
            free(self);
        }
    }
    COMPONENT_CATCH
    return result;
    */
        printf("audioComponentClose %p\n", self);
        return noErr;
    }

    AudioComponentMethod audioComponentLookup(SInt16 selector)
    {
        switch(selector)
        {
            case kAudioUnitInitializeSelect:
                return cast(AudioComponentMethod)&AUMethodInitialize;
            case kAudioUnitUninitializeSelect:
                return cast(AudioComponentMethod)&AUMethodUninitialize;
            case kAudioUnitGetPropertyInfoSelect:
                return cast(AudioComponentMethod)&AUMethodGetPropertyInfo;
            case kAudioUnitGetPropertySelect:
                return cast(AudioComponentMethod)&AUMethodGetProperty;
            case kAudioUnitSetPropertySelect:
                return cast(AudioComponentMethod)&AUMethodSetProperty;
            case kAudioUnitAddPropertyListenerSelect:
                return cast(AudioComponentMethod)&AUMethodAddPropertyListener;
            case kAudioUnitRemovePropertyListenerSelect:
                return cast(AudioComponentMethod)&AUMethodRemovePropertyListener;
            case kAudioUnitRemovePropertyListenerWithUserDataSelect:
                return cast(AudioComponentMethod)&AUMethodRemovePropertyListenerWithUserData;
            case kAudioUnitAddRenderNotifySelect:
                return cast(AudioComponentMethod)&AUMethodAddRenderNotify;
            case kAudioUnitRemoveRenderNotifySelect:
                return cast(AudioComponentMethod)&AUMethodRemoveRenderNotify;
            case kAudioUnitGetParameterSelect:
                return cast(AudioComponentMethod)&AUMethodGetParameter;
            case kAudioUnitSetParameterSelect:
                return cast(AudioComponentMethod)&AUMethodSetParameter;
            case kAudioUnitScheduleParametersSelect:
                return cast(AudioComponentMethod)&AUMethodScheduleParameters;
            case kAudioUnitRenderSelect:
                return cast(AudioComponentMethod)&AUMethodRender;
            case kAudioUnitResetSelect:
                return cast(AudioComponentMethod)&AUMethodReset;

            default:
                debug printf("unsupported audioComponentLookup selector %d\n", selector);
                return null;
        }
    }

    OSStatus AUMethodInitialize(void* self)
    {
        printf("FUTURE AUMethodInitialize\n");
        return noErr;
    }
    OSStatus AUMethodUninitialize(void* self)
    {
        printf("FUTURE AUMethodUninitialize\n");
        return noErr;
    }
    OSStatus AUMethodGetPropertyInfo(void* self)
    {
        printf("FUTURE AUMethodGetPropertyInfo\n");
        return noErr;
    }
    OSStatus AUMethodGetProperty(void* self)
    {
        printf("FUTURE AUMethodGetProperty\n");
        return noErr;
    }
    OSStatus AUMethodSetProperty(void* self)
    {
        printf("FUTURE AUMethodSetProperty\n");
        return noErr;
    }
    OSStatus AUMethodAddPropertyListener(void* self)
    {
        printf("FUTURE AUMethodAddPropertyListener\n");
        return noErr;
    }
    OSStatus AUMethodRemovePropertyListener(void* self)
    {
        printf("FUTURE AUMethodRemovePropertyListener\n");
        return noErr;
    }
    OSStatus AUMethodRemovePropertyListenerWithUserData(void* self)
    {
        printf("FUTURE AUMethodRemovePropertyListenerWithUserData\n");
        return noErr;
    }
    OSStatus AUMethodAddRenderNotify(void* self)
    {
        printf("FUTURE AUMethodAddRenderNotify\n");
        return noErr;
    }
    OSStatus AUMethodRemoveRenderNotify(void* self)
    {
        printf("FUTURE AUMethodRemoveRenderNotify\n");
        return noErr;
    }
    OSStatus AUMethodGetParameter(void* self)
    {
        printf("FUTURE AUMethodGetParameter\n");
        return noErr;
    }
    OSStatus AUMethodSetParameter(void* self)
    {
        printf("FUTURE AUMethodSetParameter\n");
        return noErr;
    }
    OSStatus AUMethodScheduleParameters(void* self)
    {
        printf("FUTURE AUMethodScheduleParameters\n");
        return noErr;
    }
    OSStatus AUMethodRender(void* self)
    {
        printf("FUTURE AUMethodRender\n");
        return noErr;
    }
    OSStatus AUMethodReset(void* self)
    {
        printf("FUTURE AUMethodReset\n");
        return noErr;
    }
}