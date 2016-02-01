/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 and later Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
module dplug.vst.client;

import std.string;

import core.memory;

import core.stdc.stdlib,
       core.stdc.string,
       core.thread,
       core.stdc.stdio;

import gfm.core;

import dplug.core.alignedbuffer,
       dplug.core.funcs,
       dplug.core.fpcontrol;

import dplug.client.client,
       dplug.client.daw,
       dplug.client.preset,
       dplug.client.midi;

import dplug.vst.aeffectx;

template VSTEntryPoint(alias ClientClass)
{
    const char[] VSTEntryPoint =
        "extern(C) nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) "
        "{"
        "    return VSTEntryPoint(hostCallback);"
        "}"
        // has been found useful to have "main" for linux VST
        "extern(C) nothrow AEffect* main_macho(HostCallbackFunction hostCallback) "
        "{"
        "    return VSTEntryPoint(hostCallback);"
        "}"
        "nothrow AEffect* VSTEntryPoint(HostCallbackFunction hostCallback) "
        "{"
        "   if (hostCallback is null)"
        "       return null;"
        "   try"
        "   {"
        "       import gfm.core;"
        "       import core.runtime;"
        "       import core.thread;"
        "       version(OSX) {" // Must occur here for OSX, but not for Windows
        "           import dplug.client.dllmain;"
        "           runtimeInitWorkaround15060();"
        "       }"
        "       thread_attachThis();" // Attach VSTPluginMain thread to runtime
        "       auto client = new " ~ ClientClass.stringof ~ "();"

                // malloc'd else the GC would not register roots for some reason!
        "       VSTClient plugin = mallocEmplace!VSTClient(client, hostCallback);"
        "       return &plugin._effect;"
        "   }"
        "   catch (Throwable e)"
        "   {"
        "       moreInfoForDebug(e);"
        "       unrecoverableError();" // should not throw in a callback
        "       return null;"
        "   }"
        "}";
}

/// VST client wrapper
class VSTClient
{
public:

    AEffect _effect;

    this(Client client, HostCallbackFunction hostCallback)
    {
        int queueSize = 256;
        _messageQueue = new LockedQueue!Message(queueSize);

        _client = client;

        _effect = _effect.init;

        _effect.magic = kEffectMagic;

        int flags = effFlagsCanReplacing | effFlagsCanDoubleReplacing | effFlagsProgramChunks;

        if ( client.hasGUI() )
            flags |= effFlagsHasEditor;

        _effect.flags = flags;
        _maxParams = cast(int)(client.params().length);
        _maxInputs = _effect.numInputs = _client.maxInputs();
        _maxOutputs = _effect.numOutputs = _client.maxOutputs();
        assert(_maxParams >= 0 && _maxInputs >= 0 && _maxOutputs >= 0);
        _effect.numParams = cast(int)(client.params().length);
        _effect.numPrograms = cast(int)(client.presetBank().numPresets());
        _effect.version_ = client.getPluginVersion();
        _effect.uniqueID = client.getPluginID();
        _effect.processReplacing = &processReplacingCallback;
        _effect.dispatcher = &dispatcherCallback;
        _effect.setParameter = &setParameterCallback;
        _effect.getParameter = &getParameterCallback;
        _effect.user = cast(void*)(this);
        _effect.initialDelay = _client.latencySamples();
        _effect.object = cast(void*)(this);
        _effect.processDoubleReplacing = &processDoubleReplacingCallback;

        //deprecated
        _effect.DEPRECATED_ioRatio = 1.0;
        _effect.DEPRECATED_process = &processCallback;

        // dummmy values
        _sampleRate = 44100.0f;
        _maxFrames = 128;

        _maxFramesInProcess = _client.maxFramesInProcess();

        _samplesAlreadyProcessed = 0;

        // because effSetSpeakerArrangement might never come
        _usedInputs = _maxInputs;
        _usedOutputs = _maxOutputs;

        // GUI thread can allocate
        _inputScratchBuffer.length = _maxInputs;
        _outputScratchBuffer.length = _maxOutputs;

        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffer[i] = new AlignedBuffer!float();

        for (int i = 0; i < _maxOutputs; ++i)
            _outputScratchBuffer[i] = new AlignedBuffer!float();

        _zeroesBuffer = new AlignedBuffer!float();

        _inputPointers.length = _maxInputs;
        _outputPointers.length = _maxOutputs;

        _messageQueue.pushBack(makeResetStateMessage(Message.Type.resetState));

        // Create host callback wrapper
        _host = new VSTHostFromClientPOV(hostCallback, &_effect);
        client.setHostCommand(_host);

        if ( client.isSynth() )
        {
            flags |= effFlagsIsSynth;
            _host.wantEvents();
        }
        _initialized = true;
    }

    ~this()
    {
        if (_initialized)
        {
            debug ensureNotInGC("dplug.vst.Client");
            _client.destroy();

            for (int i = 0; i < _maxInputs; ++i)
                _inputScratchBuffer[i].destroy();

            for (int i = 0; i < _maxOutputs; ++i)
                _outputScratchBuffer[i].destroy();
            _zeroesBuffer.destroy();
            _initialized = false;

        }
    }

private:

    VSTHostFromClientPOV _host;
    Client _client;
    bool _initialized; // destructor flag

    float _sampleRate; // samplerate from opcode thread POV
    int _maxFrames; // max frames from opcode thread POV
    int _maxFramesInProcess; // max frames supported by the plugin, buffers will be splitted to follow this.
    int _maxInputs;
    int _maxOutputs;
    int _maxParams;
    int _usedInputs;  // used inputs from opcode thread POV
    int _usedOutputs; // used outputs from opcode thread POV

    long _samplesAlreadyProcessed; // For hosts that don't provide time info, fake it by counting samples.

    ERect _editRect;  // structure holding the UI size

    AlignedBuffer!float[] _inputScratchBuffer;  // input buffer, one per possible input
    AlignedBuffer!float[] _outputScratchBuffer; // input buffer, one per output
    AlignedBuffer!float   _zeroesBuffer;        // used for disconnected inputs
    float*[] _inputPointers;  // where processAudio will take its audio input, one per possible input
    float*[] _outputPointers; // where processAudio will output audio, one per possible output

    // stores the last asked preset/bank chunk
    ubyte[] _lastPresetChunk = null;
    ubyte[] _lastBankChunk = null;

    // Inter-locked message queue from opcode thread to audio thread
    LockedQueue!Message _messageQueue;

    final bool isValidParamIndex(int i) pure const nothrow @nogc
    {
        return i >= 0 && i < _maxParams;
    }

    final bool isValidInputIndex(int index) pure const nothrow @nogc
    {
        return index >= 0 && index < _maxInputs;
    }

    final bool isValidOutputIndex(int index) pure const nothrow @nogc
    {
        return index >= 0 && index < _maxOutputs;
    }

    Message makeResetStateMessage(Message.Type type)
    {
        Message msg;
        msg.type = type;
        msg.maxFrames = _maxFrames;
        msg.samplerate = _sampleRate;
        msg.usedInputs = _usedInputs;
        msg.usedOutputs = _usedOutputs;
        return msg;
    }

    /// VST opcode dispatcher
    final VstIntPtr dispatcher(int opcode, int index, ptrdiff_t value, void *ptr, float opt)
    {
        // Important message from Cockos:
        // "Assume everything can (and WILL) run at the same time as your
        // process/processReplacing, except:
        //   - effOpen/effClose
        //   - effSetChunk -- while effGetChunk can run at the same time as audio
        //     (user saves project, or for automatic undo state tracking), effSetChunk
        //     is guaranteed to not run while audio is processing.
        // So nearly everything else should be threadsafe."
        switch(opcode)
        {
            case effOpen: // opcode 0
                return 0;

            case effClose: // opcode 1
                this.destroy(); // free all resources except this and the runtime
                return 0;

            case effSetProgram: // opcode 2
            {
                int presetIndex = cast(int)value;
                PresetBank bank = _client.presetBank();
                if (bank.isValidPresetIndex(presetIndex))
                    bank.loadPresetFromHost(presetIndex);
                return 0;
            }

            case effGetProgram: // opcode 3
                return _client.presetBank.currentPresetIndex();

            case effSetProgramName: // opcode 4
            {
                char* p = cast(char*)ptr;
                int len = cast(int)strlen(p);
                PresetBank bank = _client.presetBank();
                Preset current = bank.currentPreset();
                if (current !is null)
                {
                    current.name = p[0..len].idup;
                }
                return 0;
            }

            case effGetProgramName: // opcode 5,
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    PresetBank bank = _client.presetBank();
                    Preset current = bank.currentPreset();
                    if (current !is null)
                    {
                        stringNCopy(p, 24, current.name());
                    }
                }
                return 0;
            }

            case effGetParamLabel: // opcode 6
            {
                char* p = cast(char*)ptr;
                if (!isValidParamIndex(index))
                    *p = '\0';
                else
                {
                    stringNCopy(p, 8, _client.param(index).label());
                }
                return 0;
            }

            case effGetParamDisplay: // opcode 7
            {
                char* p = cast(char*)ptr;
                if (!isValidParamIndex(index))
                    *p = '\0';
                else
                {
                    _client.param(index).toDisplayN(p, 8);
                }
                return 0;
            }

            case effGetParamName: // opcode 8
            {
                char* p = cast(char*)ptr;
                if (!isValidParamIndex(index))
                    *p = '\0';
                else
                {
                    stringNCopy(p, 32, _client.param(index).name());
                }
                return 0;
            }

            case DEPRECATED_effGetVu: // opcode 9
            {
                return 0;
            }

            case effSetSampleRate: // opcode 10
            {
                _sampleRate = opt;
                _messageQueue.pushBack(makeResetStateMessage(Message.Type.resetState));
                return 0;
            }

            case effSetBlockSize: // opcode 11
            {
                if (value < 0)
                    return 1;

                _maxFrames = cast(int)value;
                _messageQueue.pushBack(makeResetStateMessage(Message.Type.resetState));
                return 0;
            }

            case effMainsChanged: // opcode 12
                {
                    if (value == 0)
                    {
                      // Audio processing was switched off.
                      // The plugin must call flush its state because otherwise pending data
                      // would sound again when the effect is switched on next time.
                      _messageQueue.pushBack(makeResetStateMessage(Message.Type.resetState));
                    }
                    else
                    {
                        // Audio processing was switched on.
                    }
                    return 0;
                }

            case effEditGetRect: // opcode 13
                {
                    if ( _client.hasGUI() && ptr)
                    {
                        int width, height;
                        if (_client.getGUISize(&width, &height))
                        {
                            _editRect.top = 0;
                            _editRect.left = 0;
                            _editRect.right = cast(short)(width);
                            _editRect.bottom = cast(short)(height);
                            *cast(ERect**)(ptr) = &_editRect;
                            return 1;
                        }
                        else
                        {
                            ptr = null;
                            return 0;
                        }
                    }
                    ptr = null;
                    return 0;
                }

            case effEditOpen: // opcode 14
                {
                    if ( _client.hasGUI() )
                    {
                        _client.openGUI(ptr);
                        return 1;
                    }
                    else
                        return 0;
                }

            case effEditClose: // opcode 15
                {
                    if ( _client.hasGUI() )
                    {
                        _client.closeGUI();
                        return 1;
                    }
                    else
                        return 0;
                }

            case DEPRECATED_effEditDraw: // opcode 16
            case DEPRECATED_effEditMouse: // opcode 17
            case DEPRECATED_effEditKey: // opcode 18
                return 0;

            case effEditIdle: // opcode 19
                return 0; // why would it be useful to do anything?

            case DEPRECATED_effEditTop: // opcode 20, edit window has topped
                return 0;

            case DEPRECATED_effEditSleep:  // opcode 21, edit window goes to background
                return 0;

            case DEPRECATED_effIdentify: // opcode 22
                return CCONST('N', 'v', 'E', 'f');

            case effGetChunk: // opcode 23
            {
                ubyte** ppData = cast(ubyte**) ptr;
                bool wantBank = (index == 0);
                if (ppData)
                {
                    auto presetBank = _client.presetBank();
                    if (wantBank)
                    {
                        _lastBankChunk = presetBank.getBankChunk();
                        *ppData = _lastBankChunk.ptr;
                        return cast(int)_lastBankChunk.length;
                    }
                    else
                    {
                        _lastPresetChunk = presetBank.getPresetChunk(presetBank.currentPresetIndex());
                        *ppData = _lastPresetChunk.ptr;
                        return cast(int)_lastPresetChunk.length;
                    }
                }
                return 0;
            }

            case effSetChunk: // opcode 24
            {
                if (!ptr)
                    return 0;

                bool isBank = (index == 0);
                ubyte[] chunk = (cast(ubyte*)ptr)[0..value];
                auto presetBank = _client.presetBank();
                try
                {
                    if (isBank)
                        presetBank.loadBankChunk(chunk);
                    else
                    {
                        presetBank.loadPresetChunk(presetBank.currentPresetIndex(), chunk);
                        presetBank.loadPresetFromHost(presetBank.currentPresetIndex());
                    }
                    return 1; // success
                }
                catch(Exception e)
                {
                    // Chunk didn't parse
                    return 0;
                }
            }

            case effProcessEvents: // opcode 25, "host usually call ProcessEvents just before calling ProcessReplacing"
                VstEvents* pEvents = cast(VstEvents*) ptr;
                if (pEvents != null/* && pEvents.events != 0*/)
                {
                    for (int i = 0; i < pEvents.numEvents; ++i)
                    {
                        VstEvent* pEvent = pEvents.events[i];
                        if (pEvent)
                        {
                            if (pEvent.type == kVstMidiType)
                            {
                                VstMidiEvent* pME = cast(VstMidiEvent*) pEvent;

                                // enqueue midi message to be processed by the audio thread (why not)
                                MidiMessage midi;
                                midi.deltaFrames = pME.deltaFrames;
                                midi.detune = pME.detune;
                                foreach(k; 0..4)
                                    midi.data[k] = cast(ubyte)(pME.midiData[k]);
                                _messageQueue.pushBack(makeMIDIMessage(midi));
                            }
                            else
                            {
                                // TODO handle sysex
                            }
                        }
                    }
                    return 1;
                }
                return 0;

            case effCanBeAutomated: // opcode 26
            {
                if (!isValidParamIndex(index))
                    return 0;
                return 1; // can always be automated
            }

            case effString2Parameter: // opcode 27
            {
                if (!isValidParamIndex(index))
                    return 0;

                if (ptr == null)
                    return 0;

                double parsed = atof(cast(char*)ptr);

                _client.setParameterFromHost(index, parsed);
                return 1;
            }

            case DEPRECATED_effGetNumProgramCategories: // opcode 28
                return 1; // no real program categories

            case effGetProgramNameIndexed: // opcode 29
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    PresetBank bank = _client.presetBank();
                    if (!bank.isValidPresetIndex(index))
                        return 0;
                    string name = bank[index].name();
                    stringNCopy(p, 24, name);
                    return (name.length > 0) ? 1 : 0;
                }
                else
                    return 0;
            }

            case DEPRECATED_effCopyProgram: // opcode 30
            case DEPRECATED_effConnectInput: // opcode 31
            case DEPRECATED_effConnectOutput: // opcode 32
                return 0;

            case effGetInputProperties: // opcode 33
            {
                if (ptr == null)
                    return 0;

                if (!isValidInputIndex(index))
                    return 0;

                VstPinProperties* pp = cast(VstPinProperties*) ptr;
                pp.flags = kVstPinIsActive;

                if ( (index % 2) == 0 && index < _maxInputs)
                    pp.flags |= kVstPinIsStereo;

                sprintf(pp.label.ptr, "Input %d", index);
                return 1;
            }

            case effGetOutputProperties: // opcode 34
            {
                if (ptr == null)
                    return 0;

                if (!isValidOutputIndex(index))
                    return 0;

                VstPinProperties* pp = cast(VstPinProperties*) ptr;
                pp.flags = kVstPinIsActive;

                if ( (index % 2) == 0 && index < _maxOutputs)
                    pp.flags |= kVstPinIsStereo;

                sprintf(pp.label.ptr, "Output %d", index);
                return 1;
            }

            case effGetPlugCategory: // opcode 35
                if ( _client.isSynth() )
                    return kPlugCategSynth;
                else
                    return kPlugCategEffect;

            case DEPRECATED_effGetCurrentPosition: // opcode 36
            case DEPRECATED_effGetDestinationBuffer: // opcode 37
                return 0;

            case effOfflineNotify: // opcode 38
            case effOfflinePrepare: // opcode 39
            case effOfflineRun: // opcode 40
                return 0;

            case effProcessVarIo: // opcode 41
                return 0;

            case effSetSpeakerArrangement:
            {
                VstSpeakerArrangement* pInputArr = cast(VstSpeakerArrangement*) value;
                VstSpeakerArrangement* pOutputArr = cast(VstSpeakerArrangement*) ptr;
                if (pInputArr !is null && pOutputArr !is null )
                {
                    _usedInputs = pInputArr.numChannels;
                    _usedOutputs = pOutputArr.numChannels;

                    // limit to possible I/O
                    if (_usedInputs > _maxInputs)
                        _usedInputs = _maxInputs;
                    if (_usedOutputs > _maxOutputs)
                        _usedOutputs = _maxOutputs;

                    _messageQueue.pushBack(makeResetStateMessage(Message.Type.changedIO));

                    return 0;
                }
                return 1;
            }

            case effGetEffectName:
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    stringNCopy(p, 32, _client.effectName());
                    return 1;
                }
                return 0;
            }

            case effGetVendorString:
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    stringNCopy(p, 64, _client.vendorName());
                    return 1;
                }
                return 0;
            }

            case effGetProductString:
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    stringNCopy(p, 64, _client.productName());
                    return 1;
                }
                return 0;
            }

            case effCanDo:
            {
                char* str = cast(char*)ptr;
                if (str is null)
                    return 0;

                if (strcmp(str, "receiveVstTimeInfo") == 0)
                    return 1;

                if (_client.isSynth() )
                {
                    if (strcmp(str, "sendVstEvents") == 0)
                        return 1;
                    if (strcmp(str, "sendVstMidiEvents") == 0)
                        return 1;
                    if (strcmp(str, "receiveVstEvents") == 0)
                        return 1;
                    if (strcmp(str, "receiveVstMidiEvents") == 0)
                        return 1;
                }

                // Needed to have a Cocoa view in effEditOpen for 32-bit plugins in Reaper
                //if (strcmp(str, "hasCockosViewAsConfig") == 0)
                //        return 1;

                return 0;
            }

            case effGetVstVersion:
                return 2400; // version 2.4

        default:
            return 0; // unknown opcode
        }
    }

    //
    // Processing buffers and callbacks
    //

    // Resize copy buffers according to maximum block size.
    void resizeScratchBuffers(int nFrames) nothrow @nogc
    {
        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffer[i].resize(nFrames);

        for (int i = 0; i < _maxOutputs; ++i)
            _outputScratchBuffer[i].resize(nFrames);

        _zeroesBuffer.resize(nFrames);
        _zeroesBuffer.fill(0);
    }


    void processMessages() /* nothrow @nogc */
    {
        bool tryPopMessage(out Message msg)
        {
            // Tiny change here that the other thread is currently paused by GC, that would make us wait.
            // What would cause the GC to run? A third thread allocating. That makes it a bit unlikely in my opinion.
            return _messageQueue.tryPopFront(msg);
        }

        // Race condition here.
        // Being a tryPop, there is a tiny chance that we miss a message from the queue.
        // Thankfully it isn't that bad:
        // - we are going to read it next buffer
        // - not clearing the state for a buffer duration does no harm
        // - plugin is initialized first with the maximum amount of input and outputs
        //   so missing such a message isn't that bad: the audio callback will have some outputs that are untouched
        // (a third thread might start a collect while the UI thread takes the queue lock) which is another unlikely race condition.
        // Perhaps it's the one to favor, I don't know.

        Message msg;
        while(tryPopMessage(msg)) // <- here, we have a problem: https://github.com/p0nce/dplug/issues/45
        {
            final switch(msg.type) with (Message.Type)
            {
                case changedIO:
                {
                    bool success;
                    success = _client.setNumUsedInputs(msg.usedInputs);
                    assert(success);
                    success = _client.setNumUsedOutputs(msg.usedOutputs);
                    assert(success);

                    goto case resetState; // chaning the number of channels probably need to reset state too
                }

                case resetState:
                    resizeScratchBuffers(msg.maxFrames);

                    // The client need not be aware of the actual size of the buffers,
                    // if it works on sliced buffers.
                    int maxFrameFromClientPOV = msg.maxFrames;
                    if (_maxFramesInProcess != 0 && _maxFramesInProcess < maxFrameFromClientPOV)
                        maxFrameFromClientPOV = _maxFramesInProcess;

                    _client.reset(msg.samplerate, maxFrameFromClientPOV, msg.usedInputs, msg.usedOutputs);
                    break;

                case midi:
                    _client.processMidiMsg(msg.midiMessage);
            }
        }
    }

    void preprocess(int sampleFrames) nothrow @nogc
    {
        // bypass @nogc because semaphore and mutexes functions are not @nogc
        alias bypassNogc = void delegate() @nogc nothrow;
        bypassNogc proc = cast(bypassNogc)&processMessages;
        proc();

        if (sampleFrames > _maxFrames)
            unrecoverableError(); // simply crash the audio thread if buffer is above the maximum size
    }


    // Send audio to plugin's processAudio, and optionally slice the buffers too.
    void sendAudioToClient(float*[] inputs, float*[]outputs, int frames, TimeInfo timeInfo) nothrow @nogc
    {
        if (_maxFramesInProcess == 0)
            _client.processAudio(inputs, outputs, frames, timeInfo);
        else
        {
            // Slice audio in smaller parts
            while (frames > 0)
            {
                // Note: the last slice will be smaller than the others
                int sliceLength = std.algorithm.min(_maxFramesInProcess, frames);

                _client.processAudio(inputs, outputs, sliceLength, timeInfo);

                // offset all buffer pointers
                for (int i = 0; i < cast(int)inputs.length; ++i)
                    inputs[i] = inputs[i] + sliceLength;

                for (int i = 0; i < cast(int)outputs.length; ++i)
                    outputs[i] = outputs[i] + sliceLength;

                frames -= sliceLength;

                // timeInfo must be updated
                timeInfo.timeInSamples += sliceLength;
            }
            assert(frames == 0);
        }
    }

    void process(float **inputs, float **outputs, int sampleFrames) nothrow @nogc
    {
        preprocess(sampleFrames);

        // Not sure if the hosts would support an overwriting of these pointers, so copy them
        for (int i = 0; i < _usedInputs; ++i)
            _inputPointers[i] = inputs[i];

        for (int i = 0; i < _maxOutputs; ++i)
            _outputPointers[i] = _outputScratchBuffer[i].ptr;

        sendAudioToClient(_inputPointers[0.._usedInputs], _outputPointers[0.._usedOutputs], sampleFrames, _host.getVSTTimeInfo(_samplesAlreadyProcessed));  

        _samplesAlreadyProcessed += sampleFrames;

        // accumulate
        for (int i = 0; i < _usedOutputs; ++i)
        {
            float* source = _outputScratchBuffer[i].ptr;
            float* dest = outputs[i];
            for (int f = 0; f < sampleFrames; ++f)
                dest[f] += source[f];
        }
    }

    void processReplacing(float **inputs, float **outputs, int sampleFrames) nothrow @nogc
    {
        preprocess(sampleFrames);

        // Some hosts (Orion) send identical input and ouput pointers. 
        // We copy them to a scratch buffer to keep the constaness guarantee of input buffers.
        for (int i = 0; i < _usedInputs; ++i)
        {
            _inputPointers[i] = inputs[i];
            float* source = inputs[i];
            float* dest = _inputScratchBuffer[i].ptr;
            dest[0..sampleFrames] = source[0..sampleFrames];
            _inputPointers[i] = dest;
        }

        // Unused input channels point to an array of zeroes
        for (int i = 0; i < _usedOutputs; ++i)
            _outputPointers[i] = outputs[i];

        sendAudioToClient(_inputPointers[0.._usedInputs], _outputPointers[0.._usedOutputs], sampleFrames, _host.getVSTTimeInfo(_samplesAlreadyProcessed));   

        _samplesAlreadyProcessed += sampleFrames;
    }

    void processDoubleReplacing(double **inputs, double **outputs, int sampleFrames) nothrow @nogc
    {
        preprocess(sampleFrames);

        // existing inputs gets converted to double
        // non-connected input is zero
        for (int i = 0; i < _usedInputs; ++i)
        {
            double* source = inputs[i];
            float* dest = _inputScratchBuffer[i].ptr;
            for (int f = 0; f < sampleFrames; ++f)
                dest[f] = source[f];

            _inputPointers[i] = dest;
        }

        // Unused input channels point to an array of zeroes
        for (int i = _usedInputs; i < _maxInputs; ++i)
            _inputPointers[i] = _zeroesBuffer.ptr;

        for (int i = 0; i < _maxOutputs; ++i)
        {
            _outputPointers[i] = _outputScratchBuffer[i].ptr;
        }

        sendAudioToClient(_inputPointers[0.._usedInputs], _outputPointers[0.._usedOutputs], sampleFrames, _host.getVSTTimeInfo(_samplesAlreadyProcessed));

        _samplesAlreadyProcessed += sampleFrames;

        for (int i = 0; i < _usedOutputs; ++i)
        {
            float* source = _outputScratchBuffer[i].ptr;
            double* dest = outputs[i];
            for (int f = 0; f < sampleFrames; ++f)
                dest[f] = cast(double)source[f];
        }
    }
}

void moreInfoForDebug(Throwable e) nothrow @nogc
{
    debug
    {
        string msg = e.msg;
        string file = e.file;
        size_t line = e.line;
        debugBreak();
    }
}

void unrecoverableError() nothrow @nogc
{
    debug
    {
        // break in debug mode
        debugBreak();

        assert(false); // then crash
    }
    else
    {
        // forget about the error since it doesn't seem a good idea
        // to crash in audio production
    }
}

//
// VST callbacks
//
extern(C) private nothrow
{
    VstIntPtr dispatcherCallback(AEffect *effect, int opcode, int index, ptrdiff_t value, void *ptr, float opt) nothrow
    {
        // Register this thread to the D runtime if unknown.
        bool terminated = false;
        VstIntPtr result = 0;

        try
        {
            thread_attachThis();

            FPControl fpctrl;
            fpctrl.initialize();

            auto plugin = cast(VSTClient)(effect.user);
            result = plugin.dispatcher(opcode, index, value, ptr, opt);
            if (opcode == effClose)
            {
                destroyFree(plugin);
                terminated = true;
            }
        }
        catch (Throwable e)
        {
            moreInfoForDebug(e);
            unrecoverableError(); // should not throw in a callback
        }

        /*if (terminated)
        {
            assumeNothrow( ()
                {
                    import core.runtime;
                    Runtime.terminate();
                })();
        }*/
        return result;
    }

    // VST callback for DEPRECATED_process
    void processCallback(AEffect *effect, float **inputs, float **outputs, int sampleFrames) nothrow @nogc
    {

        // GC pauses might happen in some circumstances.
        // If the thread calling this callback is a registered thread (has also called the opcode dispatcher),
        // then this thread could be paused by an other thread collecting.
        // We assume that in that case, avoiding pauses in the audio thread wasn't a primary concern of the host.

        try
        {
            FPControl fpctrl;
            fpctrl.initialize();

            auto plugin = cast(VSTClient)effect.user;
            plugin.process(inputs, outputs, sampleFrames);
        }
        catch (Throwable e)
        {
            moreInfoForDebug(e);
            unrecoverableError(); // should not throw in a callback
        }
    }

    // VST callback for processReplacing
    void processReplacingCallback(AEffect *effect, float **inputs, float **outputs, int sampleFrames) nothrow @nogc
    {

        // GC pauses might happen in some circumstances.
        // If the thread calling this callback is a registered thread (has also called the opcode dispatcher),
        // then this thread could be paused by an other thread collecting.
        // We assume that in that case, avoiding pauses in the audio thread wasn't a primary concern of the host.

        try
        {
            FPControl fpctrl;
            fpctrl.initialize();

            auto plugin = cast(VSTClient)effect.user;
            plugin.processReplacing(inputs, outputs, sampleFrames);
        }
        catch (Throwable e)
        {
            moreInfoForDebug(e);
            unrecoverableError(); // should not throw in a callback
        }
    }

    // VST callback for processDoubleReplacing
    void processDoubleReplacingCallback(AEffect *effect, double **inputs, double **outputs, int sampleFrames) nothrow @nogc
    {

        // GC pauses might happen in some circumstances.
        // If the thread calling this callback is a registered thread (has also called the opcode dispatcher),
        // then this thread could be paused by an other thread collecting.
        // We assume that in that case, avoiding pauses in the audio thread wasn't a primary concern of the host.

        try
        {
            FPControl fpctrl;
            fpctrl.initialize();

            auto plugin = cast(VSTClient)effect.user;
            plugin.processDoubleReplacing(inputs, outputs, sampleFrames);
        }
        catch (Throwable e)
        {
            moreInfoForDebug(e);
            unrecoverableError(); // should not throw in a callback
        }
    }

    // VST callback for setParameter
    void setParameterCallback(AEffect *effect, int index, float parameter) nothrow @nogc
    {

        // GC pauses might happen in some circumstances.
        // If the thread calling this callback is a registered thread (has also called the opcode dispatcher),
        // then this thread could be paused by an other thread collecting.
        // We assume that in that case, avoiding pauses in the audio thread wasn't a primary concern of the host.

        try
        {
            FPControl fpctrl;
            fpctrl.initialize();

            auto plugin = cast(VSTClient)effect.user;
            Client client = plugin._client;

            if (!plugin.isValidParamIndex(index))
                return;

            client.setParameterFromHost(index, parameter);
        }
        catch (Throwable e)
        {
            moreInfoForDebug(e);
            unrecoverableError(); // should not throw in a callback
        }
    }

    // VST callback for getParameter
    float getParameterCallback(AEffect *effect, int index) nothrow @nogc
    {
        // GC pauses might happen in some circumstances.
        // If the thread calling this callback is a registered thread (has also called the opcode dispatcher),
        // then this thread could be paused by an other thread collecting.
        // We assume that in that case, avoiding pauses in the audio thread wasn't a primary concern of the host.

        try
        {
            FPControl fpctrl;
            fpctrl.initialize();

            auto plugin = cast(VSTClient)(effect.user);
            Client client = plugin._client;

            if (!plugin.isValidParamIndex(index))
                return 0.0f;

            float value;
            value = client.param(index).getForHost();
            return value;
        }
        catch (Throwable e)
        {
            moreInfoForDebug(e);
            unrecoverableError(); // should not throw in a callback

            // Still here? Return zero.
            return 0.0f;
        }
    }
}

// Copy source into dest.
// dest must contain room for maxChars characters
// A zero-byte character is then appended.
private void stringNCopy(char* dest, size_t maxChars, string source)
{
    if (maxChars == 0)
        return;

    size_t max = maxChars < source.length ? maxChars - 1 : source.length;
    for (int i = 0; i < max; ++i)
        dest[i] = source[i];
    dest[max] = '\0';
}




/// Access to VST host from the VST client perspective.
/// The IHostCommand subset is accessible from the plugin client with no knowledge of the format
class VSTHostFromClientPOV : IHostCommand
{
public:

    this(HostCallbackFunction hostCallback, AEffect* effect)
    {
        _hostCallback = hostCallback;
        _effect = effect;
    }

    /**
     * Deprecated: This call is deprecated, but was added to support older hosts (like MaxMSP).
     * Plugins (VSTi2.0 thru VSTi2.3) call this to tell the host that the plugin is an instrument.
     */
    void wantEvents() nothrow
    {
        callback(DEPRECATED_audioMasterWantMidi, 0, 1, null, 0);
    }

    /// Request plugin window resize.
    override bool requestResize(int width, int height) nothrow
    {
        return (callback(audioMasterSizeWindow, width, height, null, 0.0f) != 0);
    }

    override void beginParamEdit(int paramIndex)
    {
        callback(audioMasterBeginEdit, paramIndex, 0, null, 0.0f);
    }

    override void paramAutomate(int paramIndex, float value)
    {
        callback(audioMasterAutomate, paramIndex, 0, null, value);
    }

    override void endParamEdit(int paramIndex)
    {
        callback(audioMasterEndEdit, paramIndex, 0, null, 0.0f);
    }

    override DAW getDAW()
    {
        return identifyDAW(productString());
    }

    const(char)* vendorString() nothrow
    {
        int res = cast(int)callback(audioMasterGetVendorString, 0, 0, _vendorStringBuf.ptr, 0.0f);
        if (res == 1)
        {
            return _vendorStringBuf.ptr;
        }
        else
            return "unknown";
    }

    const(char)* productString() nothrow
    {
        int res = cast(int)callback(audioMasterGetProductString, 0, 0, _productStringBuf.ptr, 0.0f);
        if (res == 1)
        {
            return _productStringBuf.ptr;
        }
        else
            return "unknown";
    }

    /// Gets VSTTimeInfo structure, null if not all flags are supported
    TimeInfo getVSTTimeInfo(long fallbackTimeInSamples) nothrow @nogc
    {
        TimeInfo info;
        int filters = kVstTempoValid;
        VstTimeInfo* ti = cast(VstTimeInfo*) callback(audioMasterGetTime, 0, filters, null, 0);
        if (ti && ti.sampleRate > 0)
        {
            info.timeInSamples = cast(long)(0.5f + ti.samplePos);
            if ((ti.flags & kVstTempoValid) && ti.tempo > 0)
                info.tempo = ti.tempo;
        }
        else
        {
            // probably a very simple host, fake time
            info.timeInSamples = fallbackTimeInSamples;
        }
        return info;
    }

    /// Capabilities

    enum HostCaps
    {
        SEND_VST_EVENTS,                      // Host supports send of Vst events to plug-in.
        SEND_VST_MIDI_EVENTS,                 // Host supports send of MIDI events to plug-in.
        SEND_VST_TIME_INFO,                   // Host supports send of VstTimeInfo to plug-in.
        RECEIVE_VST_EVENTS,                   // Host can receive Vst events from plug-in.
        RECEIVE_VST_MIDI_EVENTS,              // Host can receive MIDI events from plug-in.
        REPORT_CONNECTION_CHANGES,            // Host will indicates the plug-in when something change in plug-in´s routing/connections with suspend()/resume()/setSpeakerArrangement().
        ACCEPT_IO_CHANGES,                    // Host supports ioChanged().
        SIZE_WINDOW,                          // used by VSTGUI
        OFFLINE,                              // Host supports offline feature.
        OPEN_FILE_SELECTOR,                   // Host supports function openFileSelector().
        CLOSE_FILE_SELECTOR,                  // Host supports function closeFileSelector().
        START_STOP_PROCESS,                   // Host supports functions startProcess() and stopProcess().
        SHELL_CATEGORY,                       // 'shell' handling via uniqueID. If supported by the Host and the Plug-in has the category kPlugCategShell
        SEND_VST_MIDI_EVENT_FLAG_IS_REALTIME, // Host supports flags for VstMidiEvent.
        SUPPLY_IDLE                           // ???
    }

    bool canDo(HostCaps caps) nothrow
    {
        const(char)* capsString = hostCapsString(caps);
        assert(capsString !is null);

        // note: const is casted away here
        return callback(audioMasterCanDo, 0, 0, cast(void*)capsString, 0.0f) == 1;
    }

private:

    AEffect* _effect;
    HostCallbackFunction _hostCallback;
    char[65] _vendorStringBuf;
    char[96] _productStringBuf;
    int _vendorVersion;

    VstIntPtr callback(VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt) nothrow @nogc
    {
        // Saves FP state
        FPControl fpctrl;
        fpctrl.initialize();
        return _hostCallback(_effect, opcode, index, value, ptr, opt);
    }

    static const(char)* hostCapsString(HostCaps caps) pure nothrow
    {
        switch (caps)
        {
            case HostCaps.SEND_VST_EVENTS: return "sendVstEvents";
            case HostCaps.SEND_VST_MIDI_EVENTS: return "sendVstMidiEvent";
            case HostCaps.SEND_VST_TIME_INFO: return "sendVstTimeInfo";
            case HostCaps.RECEIVE_VST_EVENTS: return "receiveVstEvents";
            case HostCaps.RECEIVE_VST_MIDI_EVENTS: return "receiveVstMidiEvent";
            case HostCaps.REPORT_CONNECTION_CHANGES: return "reportConnectionChanges";
            case HostCaps.ACCEPT_IO_CHANGES: return "acceptIOChanges";
            case HostCaps.SIZE_WINDOW: return "sizeWindow";
            case HostCaps.OFFLINE: return "offline";
            case HostCaps.OPEN_FILE_SELECTOR: return "openFileSelector";
            case HostCaps.CLOSE_FILE_SELECTOR: return "closeFileSelector";
            case HostCaps.START_STOP_PROCESS: return "startStopProcess";
            case HostCaps.SHELL_CATEGORY: return "shellCategory";
            case HostCaps.SEND_VST_MIDI_EVENT_FLAG_IS_REALTIME: return "sendVstMidiEventFlagIsRealtime";
            case HostCaps.SUPPLY_IDLE: return "supplyIdle";
            default:
                assert(false);
        }
    }
}

private
{
    struct Message
    {
        enum Type
        {
            resetState, // reset plugin state, set samplerate and buffer size (samplerate = fParam, buffersize in frames = iParam)
            changedIO,  // number of inputs/outputs changes (num. inputs = iParam, num. outputs = iParam2)
            midi
        }

        this(Type type_, int maxFrames_, float samplerate_, int usedInputs_, int usedOutputs_)
        {
            type = type_;
            maxFrames = maxFrames_;
            samplerate = samplerate_;
            usedInputs = usedInputs_;
            usedOutputs = usedOutputs_;
        }

        Type type;
        int maxFrames;
        float samplerate;
        int usedInputs;
        int usedOutputs;
        MidiMessage midiMessage;
    }

    Message makeMIDIMessage(MidiMessage midiMessage)
    {
        Message msg;
        msg.type = Message.Type.midi;
        msg.midiMessage = midiMessage;
        return msg;
    }
}

