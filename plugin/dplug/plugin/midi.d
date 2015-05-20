module dplug.plugin.midi;

/// MIDI types
struct MidiMessage
{
    //int mOffset;
    ubyte mStatus, mData1, mData2;

    enum Status
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

    enum ControlChange
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
};