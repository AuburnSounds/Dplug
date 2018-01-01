/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 - 2017 Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
/**
    MIDI messages definitions.
*/
module dplug.client.midi;

import std.algorithm.mutation;
import dplug.core.vec;

/// It's the same abstraction that in IPlug.
/// For VST raw MIDI messages are passed.
/// For AU MIDI messages gets synthesized.
struct MidiMessage
{
pure:
nothrow:
@nogc:

    this( int offset, ubyte status, ubyte data1, ubyte data2)
    {
        _offset = offset;
        _status = status;
        _data1 = data1;
        _data2 = data2;
    }

    int offset() const
    {
        return _offset;
    }

    /// Midi channels 1 .. 16
    ///
    /// Returns: [0 .. 15]
    int channel() const
    {
        return status & 0x0F;
    }

    /// Status Type
    ///
    /// See_Also: dplug.client.midi : MidiStatus
    int status() const
    {
        return _status >> 4;
    }

    // Status type distinction properties

    bool isChannelAftertouch() const
    {
        return status() == MidiStatus.channelAftertouch;
    }

    bool isControlChange() const
    {
        return status() == MidiStatus.controlChange;
    }

    bool isNoteOn() const
    {
        return status() == MidiStatus.noteOn;
    }

    bool isNoteOff() const
    {
        return status() == MidiStatus.noteOff;
    }

    bool isPitchBend() const
    {
        return status() == MidiStatus.pitchWheel;
    }

    alias isPitchWheel = isPitchBend;

    bool isPolyAftertouch() const
    {
        return status() == MidiStatus.polyAftertouch;
    }

    bool isProgramChange() const
    {
        return status() == MidiStatus.programChange;
    }

    // Data value properties

    /// Channel pressure
    int channelAftertouch() const
    {
        assert(isChannelAftertouch());
        return _data1;
    }

    /// Number of the changed controller
    MidiControlChange controlChangeControl() const
    {
        assert(isControlChange());
        return cast(MidiControlChange)(_data1);
    }

    /// Controller's new value
    ///
    /// Returns: [1 .. 127]
    int controlChangeValue() const
    {
        assert(isControlChange());
        return _data2;
    }

    /// Controller's new value
    ///
    /// Returns: [0.0 .. 1.0]
    float controlChangeValue0to1() const
    {
        assert(isControlChange());
        return cast(float)(_data2) / 127.0f;
    }

    /// Returns: true = on
    bool controlChangeOnOff() const
    {
        return controlChangeValue() >= 64;
    }

    int noteNumber() const
    {
        assert(isNoteOn() || isNoteOff() || isPolyAftertouch());
        return _data1;
    }

    int noteVelocity() const
    {
        assert(isNoteOn() || isNoteOff());
        return _data2;
    }

    /// Returns: [-1.0 .. 1.0]
    double pitchBend() const
    {
        assert(isPitchBend());
        immutable int iVal = (_data2 << 7) + _data1;
        return cast(double) (iVal - 8192) / 8192.0;
    }

    alias pitchWheel = pitchBend;

    /// Amount of pressure
    int polyAftertouch() const
    {
        assert(isPolyAftertouch());
        return _data2;
    }

    /// Program number
    int program() const
    {
        assert(isProgramChange());
        return _data1;
    }

private:
    int _offset = 0;

    ubyte _status = 0;

    ubyte _data1 = 0;

    ubyte _data2 = 0; 
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
    pitchBend = 14,
    pitchWheel = pitchBend
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
    msg._offset = offset;
    msg._status = cast(ubyte)( channel | (status << 4) );
    msg._data1 = cast(ubyte)data1;
    msg._data2 = cast(ubyte)data2;
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

    enum QueueCapacity = 511;

    private this(int dummy)
    {
        _outMessages = makeVec!MidiMessage(QueueCapacity);
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
        assert(message._offset >= 0);
        message._offset += _framesElapsed;
        insertElement(message);
    }

    /// Gets all the MIDI messages for the next `frames` samples.
    /// It is guaranteed to be in order relative to time.
    /// These messages are valid until the next call to `getNextMidiMessages`.
    const(MidiMessage)[] getNextMidiMessages(int frames)
    {
        _outMessages.clearContents();

        int framesLimit = _framesElapsed;

        if (!empty())
        {
            MidiMessage m = minElement();

            while(m._offset < (_framesElapsed + frames))
            {
                // Subtract the timestamp again
                m._offset -= _framesElapsed;
                assert(m._offset >= 0);
                assert(m._offset < frames);
                _outMessages.pushBack(m);
                popMinElement();

                if (empty())
                    break;

                m = minElement();
            }
        }
        _framesElapsed += frames;
        return _outMessages[];
    }

private:

    // Frames elapsed since the beginning
    int _framesElapsed = 0;

    // Scratch buffer to return slices of messages on demand (messages are copied there).
    Vec!MidiMessage _outMessages;

    //
    // Min heap implementation below.
    //

    int _numElements = 0;

    // Useful slots are in 1..QueueCapacity+1
    // means it can contain QueueCapacity items at most
    MidiMessage[QueueCapacity+1] _heap;    

    void insertElement(MidiMessage message)
    {
        // Insert the element at the next available bottom level slot
        int slot = _numElements + 1;

        _numElements++;

        if (slot >= _heap.length)
        {
            // TODO: limitation here, we can't accept more than QueueCapacity MIDI messages in the queue
            debug
            {
                // MIDI messages heap is on full capacity.
                // That can happen because you have forgotten to call `getNextMidiMessages` 
                // with the necessary number of frames.
                assert(false); 
            }
            else
            {
                return; // dropping excessive message
            }
        }

        _heap[slot] = message;

        // Bubble up
        while (slot > 1 && _heap[parentOf(slot)]._offset > _heap[slot]._offset)
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
            if (left <= _numElements && _heap[left]._offset < _heap[best]._offset)
                best = left;
            if (right <= _numElements && _heap[right]._offset < _heap[best]._offset)
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

unittest
{
    MidiQueue queue = makeMidiQueue();

    foreach (k; 0..2)
    {
        // Enqueue QueueCapacity messages with decreasing timestamps
        foreach(i; 0..MidiQueue.QueueCapacity)
        {
            queue.enqueue( makeMidiMessageNoteOn(MidiQueue.QueueCapacity-1-i, 0, 60, 100) );
            assert(queue._numElements == i+1);
        }

        const(MidiMessage)[] messages = queue.getNextMidiMessages(1024);
        foreach(int i, m; messages)
        {
            import core.stdc.stdio;
            // each should be in order
            assert(m.offset == i);
            assert(m.isNoteOn);
        }
    }
}