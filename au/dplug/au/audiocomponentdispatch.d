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
* Dispatcher for the Audio Component API.
* Copyright: Copyright Auburn Sounds 2016.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.au.audiocomponentdispatch;

import core.stdc.stdio;
import core.stdc.stdlib: malloc, free;
import derelict.carbon;

import dplug.core.runtime;
import dplug.core.nogc;
import dplug.au.client;

nothrow:
@nogc:

//debug = logDispatcher;
// Factory function entry point for Audio Component
void* audioUnitComponentFactory(alias ClientClass)(void* inDesc)
{
    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();
    acquireAUFunctions();

    const(AudioComponentDescription)* desc = cast(const(AudioComponentDescription)*)inDesc;
    AudioComponentPlugInInterface* pinter = cast(AudioComponentPlugInInterface*) malloc(PlugInInstance.sizeof);

    pinter.Open = &audioComponentOpen!ClientClass;
    pinter.Close = &audioComponentClose;
    pinter.Lookup = &audioComponentLookup;
    pinter.reserved = null;
    return pinter;
}

private:

struct PlugInInstance
{
    AudioComponentPlugInInterface iface;
    AUClient instance;
}

extern(C)
{
    OSStatus audioComponentOpen(ClientClass)(void *pSelf, AudioUnit compInstance)
    {
        PlugInInstance* acpi = cast(PlugInInstance *) pSelf;
        assert(acpi);
        ClientClass client = mallocNew!ClientClass();
        AUClient auClient = mallocNew!AUClient(client, null);
        acpi.instance = auClient;
        return noErr;
    }

    OSStatus audioComponentClose(void* pSelf)
    {
        PlugInInstance* acpi = cast(PlugInInstance *) pSelf;
        assert(acpi);
        destroyFree(acpi.instance);
        acpi.instance = null;
        return noErr;
    }

    AudioComponentMethod audioComponentLookup(SInt16 selector)
    {
        switch(selector)
        {
            case kAudioUnitInitializeSelect: // 1
                return cast(AudioComponentMethod)&AUMethodInitialize;
            case kAudioUnitUninitializeSelect: // 2
                return cast(AudioComponentMethod)&AUMethodUninitialize;
            case kAudioUnitGetPropertyInfoSelect: // 3
                return cast(AudioComponentMethod)&AUMethodGetPropertyInfo;
            case kAudioUnitGetPropertySelect: // 4
                return cast(AudioComponentMethod)&AUMethodGetProperty;
            case kAudioUnitSetPropertySelect: // 5
                return cast(AudioComponentMethod)&AUMethodSetProperty;
            case kAudioUnitAddPropertyListenerSelect: // 10
                return cast(AudioComponentMethod)&AUMethodAddPropertyListener;
            case kAudioUnitRemovePropertyListenerSelect: // 11
                return cast(AudioComponentMethod)&AUMethodRemovePropertyListener;
            case kAudioUnitRemovePropertyListenerWithUserDataSelect: // 18
                return cast(AudioComponentMethod)&AUMethodRemovePropertyListenerWithUserData;
            case kAudioUnitAddRenderNotifySelect: // 15
                return cast(AudioComponentMethod)&AUMethodAddRenderNotify;
            case kAudioUnitRemoveRenderNotifySelect: //
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
            case kAudioUnitComplexRenderSelect: // 19
                return null; // unsupported
            case kAudioUnitProcessSelect: // 20
                return null;
            case kAudioUnitProcessMultipleSelect: // 21
                return null;
            default:
                //printf("unsupported audioComponentLookup selector %d\n", selector);
                return null;
        }
    }

    AUClient getPlug(void *pSelf)
    {
        return (cast(PlugInInstance*) pSelf).instance;
    }

    // <Dispatch methods>

    OSStatus AUMethodInitialize(void* pSelf)
    {
        debug(logDispatcher) printf("AUMethodInitialize\n");
        return getPlug(pSelf).DoInitialize();
    }

    OSStatus AUMethodUninitialize(void* pSelf)
    {
        debug(logDispatcher) printf("AUMethodUninitialize\n");
        return getPlug(pSelf).DoUninitialize();
    }

    OSStatus AUMethodGetPropertyInfo(void* pSelf,
                                     AudioUnitPropertyID prop,
                                     AudioUnitScope scope_,
                                     AudioUnitElement elem,
                                     UInt32* pOutDataSize,
                                     Boolean* pOutWritable)
    {
        debug(logDispatcher) printf("AUMethodGetPropertyInfo\n");
        return getPlug(pSelf).DoGetPropertyInfo(prop, scope_, elem, pOutDataSize, pOutWritable);
    }

    OSStatus AUMethodGetProperty(void* pSelf, AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, void* pOutData, UInt32* pIODataSize)
    {
        debug(logDispatcher) printf("AUMethodGetProperty\n");
        return getPlug(pSelf).DoGetProperty(inID, inScope, inElement, pOutData, pIODataSize);
    }

    OSStatus AUMethodSetProperty(void* pSelf, AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, const void* pInData, UInt32* pInDataSize)
    {
        debug(logDispatcher) printf("AUMethodSetProperty\n");
        return getPlug(pSelf).DoSetProperty(inID, inScope, inElement, pInData, pInDataSize);
    }

    OSStatus AUMethodAddPropertyListener(void* pSelf, AudioUnitPropertyID prop, AudioUnitPropertyListenerProc proc, void* pUserData)
    {
        debug(logDispatcher) printf("AUMethodAddPropertyListener\n");
        return getPlug(pSelf).DoAddPropertyListener(prop, proc, pUserData);
    }

    OSStatus AUMethodRemovePropertyListener(void* pSelf, AudioUnitPropertyID prop, AudioUnitPropertyListenerProc proc)
    {
        debug(logDispatcher) printf("AUMethodRemovePropertyListener\n");
        return getPlug(pSelf).DoRemovePropertyListener(prop, proc);
    }

    OSStatus AUMethodRemovePropertyListenerWithUserData(void* pSelf, AudioUnitPropertyID prop, AudioUnitPropertyListenerProc proc, void* pUserData)
    {
        debug(logDispatcher) printf("AUMethodRemovePropertyListenerWithUserData\n");
        return getPlug(pSelf).DoRemovePropertyListenerWithUserData(prop, proc, pUserData);
    }

    OSStatus AUMethodAddRenderNotify(void* pSelf, AURenderCallback proc, void* pUserData)
    {
        debug(logDispatcher) printf("AUMethodAddRenderNotify\n");
        return getPlug(pSelf).DoAddRenderNotify(proc, pUserData);
    }

    OSStatus AUMethodRemoveRenderNotify(void* pSelf, AURenderCallback proc, void* pUserData)
    {
        debug(logDispatcher) printf("AUMethodRemoveRenderNotify\n");
        return getPlug(pSelf).DoRemoveRenderNotify(proc, pUserData);
    }

    // Note: used even without Audio Component API
    public OSStatus AUMethodGetParameter(void* pSelf,
                                         AudioUnitParameterID param,
                                         AudioUnitScope scope_,
                                         AudioUnitElement elem,
                                         AudioUnitParameterValue *value)
    {
        debug(logDispatcher) printf("AUMethodGetParameter\n");
        return getPlug(pSelf).DoGetParameter(param, scope_, elem, value);
    }

    // Note: used even without Audio Component API
    public OSStatus AUMethodSetParameter(void* pSelf, AudioUnitParameterID param, AudioUnitScope scope_, AudioUnitElement elem, AudioUnitParameterValue value, UInt32 bufferOffset)
    {
        debug(logDispatcher) printf("AUMethodSetParameter\n");
        return getPlug(pSelf).DoSetParameter(param, scope_, elem, value, bufferOffset);
    }

    OSStatus AUMethodScheduleParameters(void* pSelf, const AudioUnitParameterEvent *pEvent, UInt32 nEvents)
    {
        debug(logDispatcher) printf("AUMethodScheduleParameters\n");
        return getPlug(pSelf).DoScheduleParameters(pEvent, nEvents);
    }

    OSStatus AUMethodRender(void* pSelf, AudioUnitRenderActionFlags* pIOActionFlags, const AudioTimeStamp* pInTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList* pIOData)
    {
        debug(logDispatcher) printf("AUMethodRender\n");
        return getPlug(pSelf).DoRender(pIOActionFlags, pInTimeStamp, inOutputBusNumber, inNumberFrames, pIOData);
    }

    static OSStatus AUMethodReset(void* pSelf, AudioUnitScope scope_, AudioUnitElement elem)
    {
        debug(logDispatcher) printf("AUMethodReset\n");
        return getPlug(pSelf).DoReset(scope_, elem);
    }

    static OSStatus AUMethodMIDIEvent(void* pSelf, UInt32 inStatus, UInt32 inData1, UInt32 inData2, UInt32 inOffsetSampleFrame)
    {
        debug(logDispatcher) printf("AUMethodMIDIEvent\n");
        return getPlug(pSelf).DoMIDIEvent(inStatus, inData1, inData2, inOffsetSampleFrame);
    }

    static OSStatus AUMethodSysEx(void* pSelf, const UInt8* pInData, UInt32 inLength)
    {
        debug(logDispatcher) printf("AUMethodSysEx\n");
        return getPlug(pSelf).DoSysEx(pInData, inLength);
    }

    // </Dispatch methods>

}


