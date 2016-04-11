/**
 * Copyright: Copyright Auburn Sounds 2016.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.client.messagequeue;

import dplug.core.lockedqueue;
import dplug.client.midi;


alias AudioThreadQueue = LockedQueue!AudioThreadMessage;

/// A message for the audio thread.
/// Intended to be passed from a non critical thread to the audio thread.
struct AudioThreadMessage
{
    enum Type
    {
        resetState, // reset plugin state, set samplerate and buffer size (samplerate = fParam, buffersize in frames = iParam)
        midi
    }

    this(Type type_, int maxFrames_, float samplerate_, int usedInputs_, int usedOutputs_) pure const nothrow @nogc
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

AudioThreadMessage makeMIDIMessage(MidiMessage midiMessage) pure nothrow @nogc
{
    AudioThreadMessage msg;
    msg.type = AudioThreadMessage.Type.midi;
    msg.midiMessage = midiMessage;
    return msg;
}
