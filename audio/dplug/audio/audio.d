module dplug.audio.audio;

import std.traits;

/// An Audio is any type which provides:
/// - readable audio samples
/// - a number of channels
/// - a number of samples
enum isAudio(T) = 

    // number of samples (ie. length of audio)
    // Can be a runtime or compile-time value.
    is(typeof(T.init.numSamples) : size_t) && 
    
    // number of channels (mono = 1, stereo = 2, etc...)
    // Can be a runtime or compile-time value.
    is(typeof(T.init.numChannels) : int) && 

    // Get audio data (first index is channel, second one is time)
    is(typeof(T.init.sample(0, 0)));

/// Returns the sample type of the specified Audio.
alias SampleType(T) = typeof(T.init.sample(0, 0));

/// Optionally, an Audio can provide write access to samples.
enum isWritableAudio(T) = isAudio!T &&
    is(typeof(T.init.sample(0, 0) = SampleType!T.init));


/// Optionally, an Audio can provide direct sample access with a 
/// .channel(index) method.
enum isDirectAudio(T) =	isWritableAudio!T &&
    is(Unqual!(typeof(T.init.channel(0))) : SampleType!T[]);


/// Make builtin slices fulfill the isDirectAudio trait.
struct DynamicAudio(T)
{
    T[] data;
    alias data this; // DynamicAudio is a subtype of T[]

    @property size_t numSamples()
    {
        return data.length;
    }

    ref T sample(int channel, size_t n)
    {
        assert(channel == 0);
        return data[n];
    }

    T[] channel(int channel)
    {
    	assert(channel == 0);
    	return data;
    }

    enum int numChannels = 1;
}

static assert(isDirectAudio!(DynamicAudio!float));
static assert(isDirectAudio!(DynamicAudio!double));
static assert(isDirectAudio!(DynamicAudio!real));


/// Make static arrays fulfill the isDirectAudio trait.
struct StaticAudio(T, size_t N)
{
	T[N] data;
	alias data this;

	enum size_t numSamples = data.length;
	enum int numChannels = 1;

	ref T sample(int channel, size_t n)
	{
		assert(channel == 0);
		return data[n];
	}

	T[] channel(int channel)
	{
		assert(channel == 0);
		return data[0..$];
	}
}

static assert(isDirectAudio!(StaticAudio!(float, 4)));
static assert(isDirectAudio!(StaticAudio!(double, 5)));
static assert(isDirectAudio!(StaticAudio!(real, 6)));
