module dplug.dsp.concept;


/// Abstraction for time-invariant processors like most audio processing.

/// Primitive functions to transition towards for audio processors:
/// 
/// initialize() nothrow @nogc
///     Defined if this audio processor need initialization.
///     Must leave the object ready to process audio.
///     Can be called repeatedly.
///     Can allocate.
///
/// clearState() nothrow @nogc
///     Defined if andonly if this audio processort is stateful.
///     Can be called repeatedly.
///     Should not allocate.
///
/// nextSample() nothrow @nogc
///     To process one sample of input.
///     Should not allocate.
///
/// nextBuffer() nothrow @nogc
///     To process any number of sample of input.
///     Should not allocate.
///
/// @disable this(this);
///     Post-blit must be disabled.
///
/// All these functions must be nothrow @nogc.

import std.traits;




hasMember(