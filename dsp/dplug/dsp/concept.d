module dplug.dsp.concept;


/// Abstraction for time-invariant processors like most audio processing.
///
/// Before making an actual concept existing, here are the primitive functions
/// to write for audio processors (currently transitionning):
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
///     Post-blit must be disabledif the processor owns something.
///
/// All processors should be structs.
///
