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
module dplug.client.midi;

import std.algorithm.mutation;
import dplug.core.alignedbuffer;

/// It's the same abstraction that in IPlug.
/// For VST raw Midi messages are passed.
/// For AU Midi messages gets synthesized.
struct MidiMessage
{
pure:
nothrow:
@nogc:
    int offset = 0;

    ubyte status = 0;

    ubyte data1 = 0;

    ubyte data2 = 0;   

    int channel() const
    {
        return status & 0x0F;
    }
}


enum MidiStatus : ubyte
{
    none = 0,
    noteOff = 8,
    noteOn = 9,
    polyAftertouch = 10,
    controlChange = 11,
    programChange = 12,
    channelAftertouch = 13,
    pitchWheel = 14
};

enum MidiControlChange : ubyte
{
    modWheel = 1,
    breathController = 2,
    undefined003 = 3,
    footController = 4,
    portamentoTime = 5,
    channelVolume = 7,
    balance = 8,
    undefined009 = 9,
    pan = 10,
    expressionController = 11,
    effectControl1 = 12,
    effectControl2 = 13,
    generalPurposeController1 = 16,
    generalPurposeController2 = 17,
    generalPurposeController3 = 18,
    generalPurposeController4 = 19,
    sustainOnOff = 64,
    portamentoOnOff = 65,
    sustenutoOnOff = 66,
    softPedalOnOff = 67,
    legatoOnOff = 68,
    hold2OnOff = 69,
    soundVariation = 70,
    resonance = 71,
    releaseTime = 72,
    attackTime = 73,
    cutoffFrequency = 74,
    decayTime = 75,
    vibratoRate = 76,
    vibratoDepth = 77,
    vibratoDelay = 78,
    soundControllerUndefined = 79,
    tremoloDepth = 92,
    chorusDepth = 93,
    phaserDepth = 95,
    allNotesOff = 123
}

nothrow @nogc:

MidiMessage makeMidiMessage(int offset, int channel, MidiStatus status, int data1, int data2)
{
    assert(channel >= 0 && channel <= 15);
    assert(status >= 0 && status <= 15);
    assert(data1 >= 0 && data2 <= 255);
    assert(data1 >= 0 && data2 <= 255);
    MidiMessage msg;
    msg.offset = offset;
    msg.status = cast(ubyte)( channel | (status << 4) );
    msg.data1 = cast(ubyte)data1;
    msg.data2 = cast(ubyte)data2;
    return msg;
}

MidiMessage makeMidiMessageNoteOn(int offset, int channel, int noteNumber, int velocity)
{    
    return makeMidiMessage(offset, channel, MidiStatus.noteOn, noteNumber, velocity);
}

MidiMessage makeMidiMessageNoteOff(int offset, int channel, int noteNumber)
{    
    return makeMidiMessage(offset, channel, MidiStatus.noteOff, noteNumber, 0);
}

MidiMessage makeMidiMessagePitchWheel(int offset, int channel, float value)
{
    int ivalue = 8192 + cast(int)(value * 8192.0);
    if (ivalue < 0) 
        ivalue = 0;
    if (ivalue > 16383) 
        ivalue = 16383;
    return makeMidiMessage(offset, channel, MidiStatus.pitchWheel, ivalue & 0x7F, ivalue >> 7);
}

MidiMessage makeMidiMessageControlChange(int offset, int channel, MidiControlChange index, float value)
{
    // MAYDO: mapping is a bit strange here, not sure it can make +127 except exactly for 1.0f
    return makeMidiMessage(offset, channel, MidiStatus.controlChange, index, cast(int)(value * 127.0f) );    
}


MidiQueue makeMidiQueue()
{
    return MidiQueue(42);
}

/// Queue for MIDI messages
/// TODO: use a priority queue
struct MidiQueue
{
nothrow:
@nogc:

    this(int dummy)
    {
    }

    @disable this(this);

    ~this()
    {
    }

    void initialize()
    {
        // Clears all pending MIDI messages
        _framesElapsed = 0;
        _numElements = 0;
    }

    /// Enqueue a message in the priority queue.
    void enqueue(MidiMessage message)
    {
        // Tweak message to mark it with current stamp
        // This allows to have an absolute offset for MIDI messages.
        message.offset += _framesElapsed;
        insertElement(message);
    }

    /// Gets all the MIDI messages for the next `frames` samples.
    /// Clears the output buffer and push the messages that will happen in the next `frames` samples.
    void getMessagesForNextFrames(int frames, ref AlignedBuffer!MidiMessage outMessages)
    {
        outMessages.clearContents();

        int framesLimit = _framesElapsed;

        if (!empty())
        {
            MidiMessage m = minElement();

            while(m.offset < _framesElapsed)
            {
                // Subtract the timestamp again
                m.offset -= _framesElapsed;
                outMessages.pushBack(m);
                popMinElement();

                if (empty())
                    break;

                m = minElement();
            }
        }
        _framesElapsed += frames;
    }

private:

    // Frames elapsed since the beginning
    int _framesElapsed = 0;

    //
    // Min heap implementation below.
    //

    int _numElements = 0;

    // Useful slots are in 1..512
    // means it can contain 511 items at most
    MidiMessage[512] _heap; 

    void insertElement(MidiMessage message)
    {
        // Insert the element at the next available bottom level slot
        int slot = _numElements + 1;

        _numElements++;

        if (slot >= _heap.length)
        {
            // TODO: limitation here, we can't accept more than 511 MIDI messages by audio buffer
            debug 
                assert(false); // dropping excessive message
            else
                return;
        }

        _heap[slot] = message;

        // Bubble up
        while (slot > 1 && _heap[parentOf(slot)].offset > _heap[slot].offset)
        {
            // swap with parent if larger
            swap(_heap[slot], _heap[parentOf(slot)]);
            slot = parentOf(slot);
        }
    }

    bool empty()
    {
        assert(_numElements >= 0);
        return _numElements == 0;
    }

    MidiMessage minElement()
    {
        assert(!empty);
        return _heap[1];
    }

    void popMinElement()
    {
        assert(!empty);

        // Put the last element into root
        _heap[1] = _heap[_numElements];

        _numElements = _numElements-1;

        int slot = 1;

        if (slot >= _heap.length)
        {
            debug assert(false); // dropping excessive message
        }

        while (1)
        {
            // Looking for the minimum of self and children

            int left = leftChildOf(slot);
            int right = rightChildOf(slot);
            int best = slot;
            if (left <= _numElements && _heap[left].offset < _heap[best].offset)
                best = left;
            if (left <= _numElements && _heap[left].offset < _heap[best].offset)
                best = right;

            if (best == slot) // no swap, final position
            {
                // both children (if any) are larger, everything good
                break;
            }
            else
            {
                // swap with smallest of children
                swap(_heap[slot], _heap[best]);

                // continue to bubble down
                slot = best;
            }
        }
    }

    static int parentOf(int index)
    {
        return index >> 1;
    }

    static int leftChildOf(int index)
    {
        return 2*index;
    }

    static int rightChildOf(int index)
    {
        return 2*index+1;
    }
}