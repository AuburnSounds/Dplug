/**
 * Copyright: Copyright Auburn Sounds 2016
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Guillaume Piolat
 */
module dplug.audio.sound;


/**
 *  This module defines the interfaces that describe a "sound".
 *  A sound is a multi-channel concept, that can be combined like input-range.
 *  Can represent a buffer, an audio processing block, a sound sample.
 *  For now they only deal with float.
 */
enum isSound(S) = true; // All Sound capabilities are optional!


/// Duration.
/// A sound can optionally have a duration.
template hasDuration(S)
{
    enum bool hasDuration = is(typeof(
    (inout int = 0)
    {
        S s = S.init;
        int d = s.duration;
    }));
}

/// Is this duration a static property?
template hasStaticDuration(S)
{
    enum bool hasStaticDuration = hasDuration!S && __traits(compiles, int[S.duration]);
}

/// Is this duration a runtime property?
enum bool hasRuntimeDuration(S) = !hasStaticDuration!S;

unittest
{
    struct Yes
    {
        enum duration = 128;
    }
    static assert(hasStaticDuration!Yes);
    static assert(!hasRuntimeDuration!Yes);

    struct No
    {
        int duration = 128;
    }
    static assert(!hasStaticDuration!No);
    static assert(hasRuntimeDuration!Yes);
}


/// Number of channels.
// A sound can optionally have a duration field.
template hasDuration(S)
{
    enum bool hasDuration = is(typeof(
    (inout int = 0)
    {
        S s = S.init;
        int d = s.duration;
    }));
}

/// Is this duration a static property?
template hasStaticDuration(S)
{
    enum bool hasStaticDuration = hasDuration!S && __traits(compiles, int[S.duration]);
}

/// Is this duration a runtime property?
enum bool hasRuntimeDuration(S) = !hasStaticDuration!S;




/// A Sound can optionally process sample with a `nextSample` function.
template hasProcessSample(S)
{
    enum bool hasProcessSample = is(typeof(S.init.processSample));
}

/// A Sound can optionally process sample with a `nextBuffer` function.
template hasProcessBuffer(S)
{
    enum bool hasProcessBuffer = is(typeof(S.init.processSample));
}







/+

/// Renders the sound into an array slice.
void renderToSlice(S)(auto ref S sound, float[] outBuffer) if (isSound!S)
{
    // Must be mono
    static assert(sound.channels == 1);

    // TODO: allow to render to static array if
    static if (hasDuration!D)
        assert(outBuffer.length == sound.duration);

    static if (hasProcessSample)

}

float{ubyte[] toPNG(SRC)(auto ref SRC src)
    if (isView!SRC)
{


 enum isView(T) =
    is(typeof(T.init.w) : size_t) && // width
    is(typeof(T.init.h) : size_t) && // height
    is(typeof(T.init[0, 0])     );   // color information

/// Returns the color type of the specified view.
/// By convention, colors are structs with numeric
/// fields named after the channel they indicate.
alias ViewColor(T) = typeof(T.init[0, 0]);

/// Views can be read-only or writable.
enum isWritableView(T) =
    isView!T &&
    is(typeof(T.init[0, 0] = ViewColor!T.init));

/// Optionally, a view can also provide direct pixel
/// access. We call these "direct views".
enum isDirectView(T) =
    isView!T &&
is(typeof(T.init.scanline(0)) : ViewColor!T[]);

+/