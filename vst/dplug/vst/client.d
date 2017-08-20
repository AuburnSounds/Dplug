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

import core.stdc.stdlib,
       core.stdc.string,
       core.stdc.stdio;

import std.algorithm.comparison;

import dplug.core.alignedbuffer,
       dplug.core.nogc,
       dplug.core.math,
       dplug.core.lockedqueue,
       dplug.core.runtime,
       dplug.core.fpcontrol,
       dplug.core.thread,
       dplug.core.sync;

import dplug.client.client,
       dplug.client.daw,
       dplug.client.preset,
       dplug.client.graphics,
       dplug.client.midi;

import dplug.vst.aeffect;
import dplug.vst.aeffectx;

template VSTEntryPoint(alias ClientClass)
{
    enum entry_VSTPluginMain =
        "export extern(C) nothrow AEffect* VSTPluginMain(HostCallbackFunction hostCallback) " ~
        "{" ~
        "    return myVSTEntryPoint!" ~ ClientClass.stringof ~ "(hostCallback);" ~
        "}\n";
    enum entry_main =
        "export extern(C) nothrow AEffect* main(HostCallbackFunction hostCallback) " ~
        "{" ~
        "    return myVSTEntryPoint!" ~ ClientClass.stringof ~ "(hostCallback);" ~
        "}\n";
    enum entry_main_macho =
        "extern(C) nothrow AEffect* main_macho(HostCallbackFunction hostCallback) " ~
        "{" ~
        "    return myVSTEntryPoint!" ~ ClientClass.stringof ~ "(hostCallback);" ~
        "}\n";

    version(OSX)
        // OSX has two VST entry points
        const char[] VSTEntryPoint =entry_VSTPluginMain ~ entry_main_macho;
    else version(Windows)
    {
        static if (size_t.sizeof == int.sizeof)
            // 32-bit Windows needs a legacy "main" entry point
            const char[] VSTEntryPoint = entry_VSTPluginMain ~ entry_main;
        else
            // 64-bit Windows does not
            const char[] VSTEntryPoint = entry_VSTPluginMain;

    }
    else version(linux)
        const char[] VSTEntryPoint = entry_VSTPluginMain ~ entry_main;
    else
        static assert(false);
}

// This is the main VST entrypoint
nothrow AEffect* myVSTEntryPoint(alias ClientClass)(HostCallbackFunction hostCallback)
{
    if (hostCallback is null)
        return null;

    ScopedForeignCallback!(false, true) scopedCallback;
    scopedCallback.enter();
    auto client = mallocNew!ClientClass();

    // malloc'd else the GC would not register roots for some reason!
    VSTClient plugin = mallocNew!VSTClient(client, hostCallback);
    return &plugin._effect;
};

// FUTURE: later
//version = useChunks;

//version = logVSTDispatcher;

/// VST client wrapper
class VSTClient
{
public:
nothrow:
@nogc:

    AEffect _effect;

    this(Client client, HostCallbackFunction hostCallback)
    {
        int queueSize = 2048;
        _messageQueue = lockedQueue!AudioThreadMessage(queueSize);

        _client = client;

        _effect = _effect.init;

        _effect.magic = kEffectMagic;


        int flags = effFlagsCanReplacing | effFlagsCanDoubleReplacing;

        version(useChunks)
            flags |= effFlagsProgramChunks;

        if ( client.hasGUI() )
            flags |= effFlagsHasEditor;

        if ( client.isSynth() )
            flags |= effFlagsIsSynth;

        _effect.flags = flags;
        _maxParams = cast(int)(client.params().length);
        _maxInputs = _effect.numInputs = _client.maxInputs();
        _maxOutputs = _effect.numOutputs = _client.maxOutputs();
        assert(_maxParams >= 0 && _maxInputs >= 0 && _maxOutputs >= 0);
        _effect.numParams = cast(int)(client.params().length);
        _effect.numPrograms = cast(int)(client.presetBank().numPresets());
        _effect.version_ = client.getPublicVersion().toVSTVersion();
        char[4] uniqueID = client.getPluginUniqueID();
        _effect.uniqueID = CCONST(uniqueID[0], uniqueID[1], uniqueID[2], uniqueID[3]);
        _effect.processReplacing = &processReplacingCallback;
        _effect.dispatcher = &dispatcherCallback;
        _effect.setParameter = &setParameterCallback;
        _effect.getParameter = &getParameterCallback;
        _effect.user = cast(void*)(this);
        _effect.initialDelay = _client.latencySamples(44100); // Note: we can't have a sample-rate yet
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


        // GUI thread can allocate
        _inputScratchBuffer = mallocSlice!(Vec!float)(_maxInputs);
        _outputScratchBuffer = mallocSlice!(Vec!float)(_maxOutputs);

        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffer[i] = makeVec!float();

        for (int i = 0; i < _maxOutputs; ++i)
            _outputScratchBuffer[i] = makeVec!float();

        _zeroesBuffer = makeVec!float();

        _inputPointers = mallocSlice!(float*)(_maxInputs);
        _outputPointers = mallocSlice!(float*)(_maxOutputs);

        // because effSetSpeakerArrangement might never come, take a default
        chooseIOArrangement(_maxInputs, _maxOutputs);
        sendResetMessage();

        // Create host callback wrapper
        _host = mallocNew!VSTHostFromClientPOV(hostCallback, &_effect);
        client.setHostCommand(_host);

        if ( client.receivesMIDI() )
        {
            _host.wantEvents();
        }

        _graphicsMutex = makeMutex();
    }

    ~this()
    {
        _client.destroyFree();

        for (int i = 0; i < _maxInputs; ++i)
            _inputScratchBuffer[i].destroy();

        for (int i = 0; i < _maxOutputs; ++i)
            _outputScratchBuffer[i].destroy();

        _inputScratchBuffer.freeSlice();
        _outputScratchBuffer.freeSlice();

        _zeroesBuffer.destroy();

        _inputPointers.freeSlice();
        _outputPointers.freeSlice();

        _host.destroyFree();

        _messageQueue.destroy();
    }

private:

    VSTHostFromClientPOV _host;
    Client _client;

    float _sampleRate; // samplerate from opcode thread POV
    int _maxFrames; // max frames from opcode thread POV
    int _maxFramesInProcess; // max frames supported by the plugin, buffers will be splitted to follow this.
    int _maxInputs;
    int _maxOutputs;
    int _maxParams;

    // Actual channels the host will give.
    IO _hostIOFromOpcodeThread;

    // Logical number of channels the plugin will use.
    // This might be different with hosts that call effSetSpeakerArrangement with
    // an invalid number of channels (like Audition which uses 1-1 even if not available).
    IO _processingIOFromOpcodeThread;

    // Fills _hostIOFromOpcodeThread and _processingIOFromOpcodeThread
    final void chooseIOArrangement(int numInputs, int numOutputs) nothrow @nogc
    {
        _hostIOFromOpcodeThread = IO(numInputs, numOutputs);

        // Note: _hostIOFromOpcodeThread may contain invalid stuff
        // Compute acceptable number of channels based on I/O legality.

        // Find the legal I/O combination with the highest score.
        int bestScore = -10000;
        IO bestProcessingIO = _hostIOFromOpcodeThread;
        bool found = false;

        foreach(LegalIO io; _client.legalIOs())
        {
            // The reasoning is: try to match exactly inputs and outputs.
            // If this isn't possible, better have the largest number of channels,
            // all other things being equal.
            // Note: this heuristic will prefer 1-2 to 2-1 if 1-1 was asked.
            int score = 0;
            if (io.numInputChannels == numInputs)
                score += 2000;
            else
                score += (io.numInputChannels - numInputs);

            if (io.numOutputChannels == numOutputs)
                score += 1000;
            else
                score += (io.numOutputChannels - numOutputs);

            if (score > bestScore)
            {
                bestScore = score;
                bestProcessingIO = IO(io.numInputChannels, io.numOutputChannels);
            }
        }
        _processingIOFromOpcodeThread = bestProcessingIO;
    }

    // Same data, but on the audio thread point of view.
    IO _hostIOFromAudioThread;
    IO _processingIOFromAudioThread;

    long _samplesAlreadyProcessed; // For hosts that don't provide time info, fake it by counting samples.

    ERect _editRect;  // structure holding the UI size

    Vec!float[] _inputScratchBuffer;  // input buffer, one per possible input
    Vec!float[] _outputScratchBuffer; // input buffer, one per output
    Vec!float   _zeroesBuffer;        // used for disconnected inputs
    float*[] _inputPointers;  // where processAudio will take its audio input, one per possible input
    float*[] _outputPointers; // where processAudio will output audio, one per possible output

    // stores the last asked preset/bank chunk
    ubyte[] _lastPresetChunk = null;
    ubyte[] _lastBankChunk = null;

    // Inter-locked message queue from opcode thread to audio thread
    LockedQueue!AudioThreadMessage _messageQueue;

    UncheckedMutex _graphicsMutex;

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

    void sendResetMessage()
    {
        AudioThreadMessage msg = AudioThreadMessage(AudioThreadMessage.Type.resetState,
                                                    _maxFrames,
                                                    _sampleRate,
                                                    _hostIOFromOpcodeThread,
                                                    _processingIOFromOpcodeThread);
        _messageQueue.pushBack(msg);
    }

    /// VST opcode dispatcher
    final VstIntPtr dispatcher(int opcode, int index, ptrdiff_t value, void *ptr, float opt) nothrow @nogc
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
            case effClose: // opcode 1
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
            {
                // FUTURE: will probably need to be zero with internal preset management
                return _client.presetBank.currentPresetIndex();
            }

            case effSetProgramName: // opcode 4
            {
                char* p = cast(char*)ptr;
                int len = cast(int)strlen(p);
                PresetBank bank = _client.presetBank();
                Preset current = bank.currentPreset();
                if (current !is null)
                {
                    current.setName(p[0..len]);
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

            case effSetSampleRate: // opcode 10
            {
                _sampleRate = opt;
                sendResetMessage();
                return 0;
            }

            case effSetBlockSize: // opcode 11
            {
                if (value < 0)
                    return 1;

                _maxFrames = cast(int)value;
                sendResetMessage();
                return 0;
            }

            case effMainsChanged: // opcode 12
                {
                    if (value == 0)
                    {
                        // Audio processing was switched off.
                        // The plugin must flush its state because otherwise pending data
                        // would sound again when the effect is switched on next time.
                        // MAYDO: this sounds backwards...
                        sendResetMessage();
                    }
                    else // "resume()" in VST parlance
                    {
                        // Audio processing was switched on. Update the latency. #154
                        int latency = _client.latencySamples(_sampleRate);
                        _effect.initialDelay = latency;
                    }
                    return 0;
                }

            case effEditGetRect: // opcode 13
                {
                    if ( _client.hasGUI() && ptr)
                    {
                        // Cubase may call effEditOpen and effEditGetRect simultaneously
                        _graphicsMutex.lock();

                        int width, height;
                        if (_client.getGUISize(&width, &height))
                        {
                            _graphicsMutex.unlock();
                            _editRect.top = 0;
                            _editRect.left = 0;
                            _editRect.right = cast(short)(width);
                            _editRect.bottom = cast(short)(height);
                            *cast(ERect**)(ptr) = &_editRect;

                            return 1;
                        }
                        else
                        {
                            _graphicsMutex.unlock();
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
                        // Cubase may call effEditOpen and effEditGetRect simultaneously
                        _graphicsMutex.lock();
                        _client.openGUI(ptr, null, GraphicsBackend.autodetect);
                        _graphicsMutex.unlock();
                        return 1;
                    }
                    else
                        return 0;
                }

            case effEditClose: // opcode 15
                {
                    if ( _client.hasGUI() )
                    {
                        _graphicsMutex.lock();
                        _client.closeGUI();
                        _graphicsMutex.unlock();
                        return 1;
                    }
                    else
                        return 0;
                }

            case DEPRECATED_effIdentify: // opcode 22
                return CCONST('N', 'v', 'E', 'f');

            case effGetChunk: // opcode 23
            {
                version(useChunks)
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
                }
                return 0;
            }

            case effSetChunk: // opcode 24
            {
                version(useChunks)
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
                        e.destroyFree();
                        // Chunk didn't parse
                        return 0;
                    }
                }
                else
                {
                    return 0;
                }
            }

            case effProcessEvents: // opcode 25, "host usually call ProcessEvents just before calling ProcessReplacing"
                VstEvents* pEvents = cast(VstEvents*) ptr;
                if (pEvents != null)
                {
                    VstEvent** allEvents = pEvents.events.ptr;
                    for (int i = 0; i < pEvents.numEvents; ++i)
                    {
                        VstEvent* pEvent = allEvents[i];
                        if (pEvent)
                        {
                            if (pEvent.type == kVstMidiType)
                            {
                                VstMidiEvent* pME = cast(VstMidiEvent*) pEvent;

                                // Enqueue midi message to be processed by the audio thread.
                                // Note that not all information is kept, some is discarded like in IPlug.
                                MidiMessage msg = MidiMessage(pME.deltaFrames,
                                                              pME.midiData[0],
                                                              pME.midiData[1],
                                                              pME.midiData[2]);
                                _messageQueue.pushBack(makeMIDIMessage(msg));
                            }
                            else
                            {
                                // FUTURE handle sysex
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
                    const(char)[] name = bank.preset(index).name();
                    stringNCopy(p, 24, name);
                    return (name.length > 0) ? 1 : 0;
                }
                else
                    return 0;
            }

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

            case effSetSpeakerArrangement: // opcode 42
            {
                VstSpeakerArrangement* pInputArr = cast(VstSpeakerArrangement*) value;
                VstSpeakerArrangement* pOutputArr = cast(VstSpeakerArrangement*) ptr;
                if (pInputArr !is null && pOutputArr !is null )
                {
                    int numInputs = pInputArr.numChannels;
                    int numOutputs = pOutputArr.numChannels;
                    chooseIOArrangement(numInputs, numOutputs);
                    sendResetMessage();
                    return 0; // MAYDO: this looks very wrong
                }
                return 1;
            }

            case effGetEffectName: // opcode 45
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    stringNCopy(p, 32, _client.pluginName());
                    return 1;
                }
                return 0;
            }

            case effGetVendorString: // opcode 47
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    stringNCopy(p, 64, _client.vendorName());
                    return 1;
                }
                return 0;
            }

            case effGetProductString: // opcode 48
            {
                char* p = cast(char*)ptr;
                if (p !is null)
                {
                    _client.getPluginFullName(p, 64);
                    return 1;
                }
                return 0;
            }

            case effCanDo: // opcode 51
            {
                char* str = cast(char*)ptr;
                if (str is null)
                    return 0;

                if (strcmp(str, "receiveVstTimeInfo") == 0)
                    return 1;

                if (_client.isSynth())
                {
                    // Not supported yet
                    /*
                    if (strcmp(str, "sendVstEvents") == 0)
                        return 1;
                    if (strcmp(str, "sendVstMidiEvents") == 0)
                        return 1;
                    */
                }

                if (_client.receivesMIDI())
                {
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

            case effGetVstVersion: // opcode 58
                return 2400; // version 2.4

        default:
            return 0; // unknown opcode, should never happen
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


    void processMessages() nothrow @nogc
    {
        // Race condition here.
        // Being a tryPop, there is a tiny chance that we miss a message from the queue.
        // Thankfully it isn't that bad:
        // - we are going to read it next buffer
        // - not clearing the state for a buffer duration does no harm
        // - plugin is initialized first with the maximum amount of input and outputs
        //   so missing such a message isn't that bad: the audio callback will have some outputs that are untouched
        // (a third thread might start a collect while the UI thread takes the queue lock) which is another unlikely race condition.
        // Perhaps it's the one to favor, I don't know.
        // TODO: Objectionable decision, for MIDI input, think about impact.

        AudioThreadMessage msg = void;
        while(_messageQueue.tryPopFront(msg))
        {
            final switch(msg.type) with (AudioThreadMessage.Type)
            {
                case resetState:
                    resizeScratchBuffers(msg.maxFrames);

                    _hostIOFromAudioThread = msg.hostIO;
                    _processingIOFromAudioThread = msg.processingIO;

                    _client.resetFromHost(msg.samplerate,
                                          msg.maxFrames,
                                          _processingIOFromAudioThread.inputs,
                                          _processingIOFromAudioThread.outputs);
                    break;

                case midi:
                    _client.enqueueMIDIFromHost(msg.midiMessage);
            }
        }
    }

    void process(float **inputs, float **outputs, int sampleFrames) nothrow @nogc
    {
        processMessages();
        int hostInputs = _hostIOFromAudioThread.inputs;
        int hostOutputs = _hostIOFromAudioThread.outputs;
        int usedInputs = _processingIOFromAudioThread.inputs;
        int usedOutputs = _processingIOFromAudioThread.outputs;
        int minOutputs = std.algorithm.comparison.min(usedOutputs, hostOutputs);

        // Not sure if the hosts would support an overwriting of these pointers, so copy them
        for (int i = 0; i < usedInputs; ++i)
        {
            // Points to zeros if the host provides a buffer, or the host buffer otherwise.
            // Note: all input channels point on same buffer, but it's ok since input channels are const
            _inputPointers[i] = (i < hostInputs) ? inputs[i] : _zeroesBuffer.ptr;
        }

        for (int i = 0; i < usedOutputs; ++i)
        {
            _outputPointers[i] = _outputScratchBuffer[i].ptr;
        }

        _client.processAudioFromHost(_inputPointers[0..usedInputs],
                                     _outputPointers[0..usedOutputs],
                                     sampleFrames,
                                     _host.getVSTTimeInfo(_samplesAlreadyProcessed));
        _samplesAlreadyProcessed += sampleFrames;

        // accumulate on available host output channels
        for (int i = 0; i < minOutputs; ++i)
        {
            float* source = _outputScratchBuffer[i].ptr;
            float* dest = outputs[i];
            for (int f = 0; f < sampleFrames; ++f)
                dest[f] += source[f];
        }
    }

    void processReplacing(float **inputs, float **outputs, int sampleFrames) nothrow @nogc
    {
        processMessages();
        int hostInputs = _hostIOFromAudioThread.inputs;
        int hostOutputs = _hostIOFromAudioThread.outputs;
        int usedInputs = _processingIOFromAudioThread.inputs;
        int usedOutputs = _processingIOFromAudioThread.outputs;
        int minOutputs = std.algorithm.comparison.min(usedOutputs, hostOutputs);

        // Some hosts (Live, Orion, and others) send identical input and output pointers.
        // This is actually legal in VST.
        // We copy them to a scratch buffer to keep the constness guarantee of input buffers.
        for (int i = 0; i < usedInputs; ++i)
        {
            if (i < hostInputs)
            {
                float* source = inputs[i];
                float* dest = _inputScratchBuffer[i].ptr;
                dest[0..sampleFrames] = source[0..sampleFrames];
                _inputPointers[i] = dest;
            }
            else
            {
                _inputPointers[i] = _zeroesBuffer.ptr;
            }
        }

        for (int i = 0; i < usedOutputs; ++i)
        {
            if (i < hostOutputs)
                _outputPointers[i] = outputs[i];
            else
                _outputPointers[i] = _outputScratchBuffer[i].ptr; // dummy output
        }

        _client.processAudioFromHost(_inputPointers[0..usedInputs],
                                     _outputPointers[0..usedOutputs],
                                     sampleFrames,
                                     _host.getVSTTimeInfo(_samplesAlreadyProcessed));
        _samplesAlreadyProcessed += sampleFrames;

        // Fills remaining host channels (if any) with zeroes
        for (int i = minOutputs; i < hostOutputs; ++i)
        {
            float* dest = outputs[i];
            for (int f = 0; f < sampleFrames; ++f)
                dest[f] = 0;
        }
    }

    void processDoubleReplacing(double **inputs, double **outputs, int sampleFrames) nothrow @nogc
    {
        processMessages();
        int hostInputs = _hostIOFromAudioThread.inputs;
        int hostOutputs = _hostIOFromAudioThread.outputs;
        int usedInputs = _processingIOFromAudioThread.inputs;
        int usedOutputs = _processingIOFromAudioThread.outputs;
        int minOutputs = std.algorithm.comparison.min(usedOutputs, hostOutputs);

        // Existing inputs gets converted to double
        // Non-connected inputs are zeroes
        for (int i = 0; i < usedInputs; ++i)
        {
            if (i < hostInputs)
            {
                double* source = inputs[i];
                float* dest = _inputScratchBuffer[i].ptr;
                for (int f = 0; f < sampleFrames; ++f)
                    dest[f] = source[f];
                _inputPointers[i] = dest;
            }
            else
                _inputPointers[i] = _zeroesBuffer.ptr;
        }

        for (int i = 0; i < usedOutputs; ++i)
        {
            _outputPointers[i] = _outputScratchBuffer[i].ptr;
        }

        _client.processAudioFromHost(_inputPointers[0..usedInputs],
                                     _outputPointers[0..usedOutputs],
                                     sampleFrames,
                                     _host.getVSTTimeInfo(_samplesAlreadyProcessed));
        _samplesAlreadyProcessed += sampleFrames;

        // Converts back to double on available host output channels
        for (int i = 0; i < minOutputs; ++i)
        {
            float* source = _outputScratchBuffer[i].ptr;
            double* dest = outputs[i];
            for (int f = 0; f < sampleFrames; ++f)
                dest[f] = cast(double)source[f];
        }

        // Fills remaining host channels (if any) with zeroes
        for (int i = minOutputs; i < hostOutputs; ++i)
        {
            double* dest = outputs[i];
            for (int f = 0; f < sampleFrames; ++f)
                dest[f] = 0;
        }
    }
}

// This look-up table speed-up unimplemented opcodes
private static immutable ubyte[64] opcodeShouldReturn0Immediately =
[ 1, 0, 0, 0, 0, 0, 0, 0,
  0, 1, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 0, 0,
  0, 0, 0, 0, 0, 0, 1, 1,
  1, 0, 0, 0, 1, 1, 1, 1,
  1, 1, 0, 1, 1, 0, 1, 0,
  0, 1, 1, 0, 1, 1, 1, 1,
  1, 1, 0, 1, 1, 1, 1, 1 ];

//
// VST callbacks
//
extern(C) private nothrow
{
    VstIntPtr dispatcherCallback(AEffect *effect, int opcode, int index, ptrdiff_t value, void *ptr, float opt) nothrow @nogc
    {
        VstIntPtr result = 0;

        // Short-circuit inconsequential opcodes to gain speed
        if (cast(uint)opcode >= 64)
            return 0;
        if (opcodeShouldReturn0Immediately[opcode])
            return 0;

        ScopedForeignCallback!(true, true) scopedCallback;
        scopedCallback.enter();

        version(logVSTDispatcher)
            printf("dispatcher effect %p thread %p opcode %d \n", effect, currentThreadId(), opcode);

        auto plugin = cast(VSTClient)(effect.user);
        result = plugin.dispatcher(opcode, index, value, ptr, opt);
        if (opcode == effClose)
        {
            destroyFree(plugin);
        }
        return result;
    }

    // VST callback for DEPRECATED_process
    void processCallback(AEffect *effect, float **inputs, float **outputs, int sampleFrames) nothrow @nogc
    {
        FPControl fpctrl;
        fpctrl.initialize();

        auto plugin = cast(VSTClient)effect.user;
        plugin.process(inputs, outputs, sampleFrames);
    }

    // VST callback for processReplacing
    void processReplacingCallback(AEffect *effect, float **inputs, float **outputs, int sampleFrames) nothrow @nogc
    {
        FPControl fpctrl;
        fpctrl.initialize();

        auto plugin = cast(VSTClient)effect.user;
        plugin.processReplacing(inputs, outputs, sampleFrames);
    }

    // VST callback for processDoubleReplacing
    void processDoubleReplacingCallback(AEffect *effect, double **inputs, double **outputs, int sampleFrames) nothrow @nogc
    {
        FPControl fpctrl;
        fpctrl.initialize();

        auto plugin = cast(VSTClient)effect.user;
        plugin.processDoubleReplacing(inputs, outputs, sampleFrames);
    }

    // VST callback for setParameter
    void setParameterCallback(AEffect *effect, int index, float parameter) nothrow @nogc
    {
        FPControl fpctrl;
        fpctrl.initialize();

        auto plugin = cast(VSTClient)effect.user;
        Client client = plugin._client;

        if (!plugin.isValidParamIndex(index))
            return;

        client.setParameterFromHost(index, parameter);
    }

    // VST callback for getParameter
    float getParameterCallback(AEffect *effect, int index) nothrow @nogc
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
}

/// Access to VST host from the VST client perspective.
/// The IHostCommand subset is accessible from the plugin client with no knowledge of the format
class VSTHostFromClientPOV : IHostCommand
{
public:
nothrow:
@nogc:

    this(HostCallbackFunction hostCallback, AEffect* effect)
    {
        _hostCallback = hostCallback;
        _effect = effect;
    }

    /**
     * Deprecated: This call is deprecated, but was added to support older hosts (like MaxMSP).
     * Plugins (VSTi2.0 thru VSTi2.3) call this to tell the host that the plugin is an instrument.
     */
    void wantEvents() nothrow @nogc
    {
        callback(DEPRECATED_audioMasterWantMidi, 0, 1, null, 0);
    }

    /// Request plugin window resize.
    override bool requestResize(int width, int height) nothrow @nogc
    {
        return (callback(audioMasterSizeWindow, width, height, null, 0.0f) != 0);
    }

    override void beginParamEdit(int paramIndex) nothrow @nogc
    {
        callback(audioMasterBeginEdit, paramIndex, 0, null, 0.0f);
    }

    override void paramAutomate(int paramIndex, float value) nothrow @nogc
    {
        callback(audioMasterAutomate, paramIndex, 0, null, value);
    }

    override void endParamEdit(int paramIndex) nothrow @nogc
    {
        callback(audioMasterEndEdit, paramIndex, 0, null, 0.0f);
    }

    override DAW getDAW() nothrow @nogc
    {
        return identifyDAW(productString());
    }

    const(char)* vendorString() nothrow @nogc
    {
        int res = cast(int)callback(audioMasterGetVendorString, 0, 0, _vendorStringBuf.ptr, 0.0f);
        if (res == 1)
        {
            return _vendorStringBuf.ptr;
        }
        else
            return "unknown";
    }

    const(char)* productString() nothrow @nogc
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
            info.hostIsPlaying = (ti.flags & kVstTransportPlaying) != 0;
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


/** Four Character Constant (for AEffect->uniqueID) */
private int CCONST(int a, int b, int c, int d) pure nothrow @nogc
{
    return (a << 24) | (b << 16) | (c << 8) | (d << 0);
}

struct IO
{
    int inputs;  /// number of input channels
    int outputs; /// number of output channels
}

//
// Message queue
//

private:

/// A message for the audio thread.
/// Intended to be passed from a non critical thread to the audio thread.
struct AudioThreadMessage
{
    enum Type
    {
        resetState, // reset plugin state, set samplerate and buffer size (samplerate = fParam, buffersize in frames = iParam)
        midi
    }

    this(Type type_, int maxFrames_, float samplerate_, IO hostIO_, IO processingIO_) pure const nothrow @nogc
    {
        type = type_;
        maxFrames = maxFrames_;
        samplerate = samplerate_;
        hostIO = hostIO_;
        processingIO = processingIO_;
    }

    Type type;
    int maxFrames;
    float samplerate;
    IO hostIO;
    IO processingIO;
    MidiMessage midiMessage;
}

AudioThreadMessage makeMIDIMessage(MidiMessage midiMessage) pure nothrow @nogc
{
    AudioThreadMessage msg;
    msg.type = AudioThreadMessage.Type.midi;
    msg.midiMessage = midiMessage;
    return msg;
}
