/**
Dynamic bindings to the CoreAudio framework.

Copyright: Guillaume Piolat 2015.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
/**
    
*/
module derelict.carbon.coreaudio;


import derelict.carbon.corefoundation;

// <CoreAudio/CoreAudioTypes.h>

struct SMPTETime
{
    short          mSubframes;
    short          mSubframeDivisor;
    uint           mCounter;
    uint           mType;
    uint           mFlags;
    short          mHours;
    short          mMinutes;
    short          mSeconds;
    short          mFrames;
}


alias AudioTimeStampFlags = UInt32;
enum : AudioTimeStampFlags
{
    kAudioTimeStampNothingValid         = 0,
    kAudioTimeStampSampleTimeValid      = (1U << 0),
    kAudioTimeStampHostTimeValid        = (1U << 1),
    kAudioTimeStampRateScalarValid      = (1U << 2),
    kAudioTimeStampWordClockTimeValid   = (1U << 3),
    kAudioTimeStampSMPTETimeValid       = (1U << 4),
    kAudioTimeStampSampleHostTimeValid  = (kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid)
}


struct AudioTimeStamp
{
    double              mSampleTime;
    ulong               mHostTime;
    double              mRateScalar;
    ulong               mWordClockTime;
    SMPTETime           mSMPTETime;
    uint                mFlags;
    uint                mReserved;
}

struct AudioBuffer
{
    uint              mNumberChannels;
    uint              mDataByteSize;
    void*             mData;
}

struct AudioBufferList
{
    uint      mNumberBuffers;
    AudioBuffer[1] mBuffers;
}

alias AudioSampleType = float;

alias AudioFormatID = uint;
alias AudioFormatFlags = uint;
enum : AudioFormatFlags
{
    kAudioFormatFlagIsFloat                     = (1U << 0),     // 0x1
    kAudioFormatFlagIsBigEndian                 = (1U << 1),     // 0x2
    kAudioFormatFlagIsSignedInteger             = (1U << 2),     // 0x4
    kAudioFormatFlagIsPacked                    = (1U << 3),     // 0x8
    kAudioFormatFlagIsAlignedHigh               = (1U << 4),     // 0x10
    kAudioFormatFlagIsNonInterleaved            = (1U << 5),     // 0x20
    kAudioFormatFlagIsNonMixable                = (1U << 6),     // 0x40
    kAudioFormatFlagsAreAllClear                = 0x80000000,

    kLinearPCMFormatFlagIsFloat                 = kAudioFormatFlagIsFloat,
    kLinearPCMFormatFlagIsBigEndian             = kAudioFormatFlagIsBigEndian,
    kLinearPCMFormatFlagIsSignedInteger         = kAudioFormatFlagIsSignedInteger,
    kLinearPCMFormatFlagIsPacked                = kAudioFormatFlagIsPacked,
    kLinearPCMFormatFlagIsAlignedHigh           = kAudioFormatFlagIsAlignedHigh,
    kLinearPCMFormatFlagIsNonInterleaved        = kAudioFormatFlagIsNonInterleaved,
    kLinearPCMFormatFlagIsNonMixable            = kAudioFormatFlagIsNonMixable,
    kLinearPCMFormatFlagsSampleFractionShift    = 7,
    kLinearPCMFormatFlagsSampleFractionMask     = (0x3F << kLinearPCMFormatFlagsSampleFractionShift),
    kLinearPCMFormatFlagsAreAllClear            = kAudioFormatFlagsAreAllClear,

    kAppleLosslessFormatFlag_16BitSourceData    = 1,
    kAppleLosslessFormatFlag_20BitSourceData    = 2,
    kAppleLosslessFormatFlag_24BitSourceData    = 3,
    kAppleLosslessFormatFlag_32BitSourceData    = 4
}
version(LittleEndian)
{
    enum : AudioFormatFlags
    {
        kAudioFormatFlagsNativeEndian = 0
    }
}

version(BigEndian)
{
    enum : AudioFormatFlags
    {
        kAudioFormatFlagsNativeEndian = kAudioFormatFlagIsBigEndian
    }
}

enum : AudioFormatFlags
{
    kAudioFormatFlagsNativeFloatPacked = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked
}


struct AudioStreamBasicDescription
{
    double              mSampleRate;
    AudioFormatID       mFormatID;
    AudioFormatFlags    mFormatFlags;
    uint              mBytesPerPacket;
    uint              mFramesPerPacket;
    uint              mBytesPerFrame;
    uint              mChannelsPerFrame;
    uint              mBitsPerChannel;
    uint              mReserved;
}

enum : AudioFormatID
{
    kAudioFormatLinearPCM = CCONST('l', 'p', 'c', 'm')
}

alias AudioChannelLayoutTag = UInt32;
enum : AudioChannelLayoutTag
{
    kAudioChannelLayoutTag_Mono                     = (100U<<16) | 1,   // a standard mono stream
    kAudioChannelLayoutTag_Stereo                   = (101U<<16) | 2,   // a standard stereo stream (L R) - implied playback
    kAudioChannelLayoutTag_StereoHeadphones         = (102U<<16) | 2,   // a standard stereo stream (L R) - implied headphone playback
    kAudioChannelLayoutTag_MatrixStereo             = (103U<<16) | 2,   // a matrix encoded stereo stream (Lt, Rt)
    kAudioChannelLayoutTag_MidSide                  = (104U<<16) | 2,   // mid/side recording
    kAudioChannelLayoutTag_XY                       = (105U<<16) | 2,   // coincident mic pair (often 2 figure 8's)
    kAudioChannelLayoutTag_Binaural                 = (106U<<16) | 2,   // binaural stereo (left, right)
    kAudioChannelLayoutTag_Unknown                  = 0xFFFF0000        // needs to be OR'd with number of channels
}

