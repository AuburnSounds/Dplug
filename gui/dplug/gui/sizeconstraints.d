/**
Defines possible size for a plugin.

Copyright: Guillaume Piolat 2020.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.sizeconstraints;

import dplug.core.math;

nothrow:
@nogc:
@safe:


/// Build a `SizeConstraints` that describes a fixed UI dimensions, in logical pixels.
SizeConstraints makeSizeConstraintsFixed(int width, int height)
{
    float[1] ratio = 1.0f;
    return makeSizeConstraintsDiscrete(width, height, ratio[]);
}

/// Build a `SizeConstraints` that describes multiple UI dimensions, in logical pixels.
/// Aspect ratio is preserved.
///
/// Params:
///     defaultWidth base width in pixels.
///     defaultHeight base height in pixels.
///     availableRatios sorted list of UI scale factors, should contain 1.0f.
///                     That list of scale factors: - must be increasing
///                                                 - must contain 1.0f
///                                                 - all factors must be > 0.0f
///
/// Warning: no more than 8 possible scales are possible.
SizeConstraints makeSizeConstraintsDiscrete(int defaultWidth, 
                                            int defaultHeight, 
                                            scope const(float)[] availableScales)
{
    SizeConstraints sc;
    sc.type = SizeConstraints.Type.discreteRatio;
    sc.defaultWidth = defaultWidth;
    sc.defaultHeight = defaultHeight;
    assert(availableScales.length <= SizeConstraints.MAX_POSSIBLE_SCALES);
    int N = cast(int)availableScales.length;
    sc.numDiscreteScales = N;
    sc.discreteScales[0..N] = availableScales[0..N];
    return sc;
}

/// Build a `SizeConstraints` that describes UI dimensions, in logical pixels.
/// Aspect ratio is preserved over a range of continuously possible scale factors.
///
/// Params:
///     defaultWidth base width in pixels.
///     defaultHeight base height in pixels.
///     availableRatios sorted list of ratios, should contain 1.0f.
SizeConstraints makeSizeConstraintsContinuous(int defaultWidth, 
                                              int defaultHeight,
                                              float minScale, 
                                              float maxScale)
{
    assert(minScale > 0.0f && minScale <= 1.0f);
    assert(maxScale >= 1.0f);
    SizeConstraints sc;
    sc.type = SizeConstraints.Type.continuousRatio;
    sc.defaultWidth = defaultWidth;
    sc.defaultHeight = defaultHeight;
    sc.minScale = minScale;
    sc.maxScale = maxScale;
    return sc;
}

/// Build a `SizeConstraints` that describes a rectangular range of size, in logical pixels.
/// All continous sizes are valid within these bounds.
/// Aspect ratio is NOT preserved.
SizeConstraints makeSizeConstraintsBounds(int minWidth, 
                                          int minHeight, 
                                          int maxWidth, 
                                          int maxHeight,
                                          int defaultWidth,
                                          int defaultHeight)
{
    assert(defaultWidth >= minWidth && defaultWidth <= maxWidth);
    assert(defaultHeight >= minHeight && defaultHeight <= maxHeight);

    SizeConstraints sc;
    sc.type = SizeConstraints.Type.rectangularBounds;
    sc.defaultWidth = defaultWidth;
    sc.defaultHeight = defaultHeight;
    sc.minWidth = minWidth;
    sc.maxWidth = maxWidth;
    sc.minHeight = minHeight;
    sc.maxHeight = maxHeight;
    return sc;
}


/// Build a `SizeConstraints` that describes several scale factors for X and Y, in logical pixels.
/// Aspect ratio is NOT preserved.
///
/// Params:
///     defaultWidth base width in pixels.
///     defaultHeight base height in pixels.
///     availableRatiosX sorted list of UI scale factors for the X dimension, should contain 1.0f.
///                      That list of scale factors: - must be increasing
///                                                  - must contain 1.0f
///                                                  - all factors must be > 0.0f
///     availableRatiosY  sorted list of UI scale factors for the Y dimension. Same as above.
///
/// Warning: no more than 8 possible scales are possible for each axis.
SizeConstraints makeSizeConstraintsDiscreteXY(int defaultWidth, 
                                              int defaultHeight, 
                                              const(float)[] availableRatiosX,
                                              const(float)[] availableRatiosY)
{
    SizeConstraints sc;
    sc.type = SizeConstraints.Type.discreteRatioXY;
    sc.defaultWidth = defaultWidth;
    sc.defaultHeight = defaultHeight;
    assert(availableRatiosX.length <= SizeConstraints.MAX_POSSIBLE_SCALES);
    assert(availableRatiosY.length <= SizeConstraints.MAX_POSSIBLE_SCALES);

    int N = cast(int)availableRatiosX.length;
    sc.numDiscreteScalesX = N;
    sc.discreteScalesX[0..N] = availableRatiosX[0..N];

    N = cast(int)availableRatiosY.length;
    sc.numDiscreteScalesY = N;
    sc.discreteScalesY[0..N] = availableRatiosY[0..N];
    return sc;
}


/// Describe what size in logical pixels are possible.
/// A GUIGraphics is given a `SizeConstraints` in its constructor.
struct SizeConstraints
{
public:
nothrow:
@nogc:

    enum Type /// Internal type of size constraint
    {
        continuousRatio,       /// Continuous zoom factors, preserve aspect ratio
        discreteRatio,         /// Discrete zoom factors, preserve aspect ratio (recommended)
        rectangularBounds,     /// Continuous separate zoom factors for X and Y, given with rectangular bounds.
        discreteRatioXY,       /// Discrete separate zoom factors for X and Y (recommended)
    }

    /// Suggest a valid size for plugin first opening.
    void suggestDefaultSize(int* width, int* height)
    {
        *width = defaultWidth;
        *height = defaultHeight;
    }

    /// Returns `true` if several size are possible.
    bool isResizable()
    {
        final switch(type) with (Type)
        {
            case continuousRatio:
                return true;
            case discreteRatio:
                return numDiscreteScales > 1;
            case rectangularBounds: 
                return true;
            case discreteRatioXY: 
                return numDiscreteScalesX > 1 && numDiscreteScalesY > 1;
        }
    }

    /// Returns `true` if this `SizeConstraints` preserve plugin aspect ratio.
    bool preserveAspectRatio()
    {
        final switch(type) with (Type)
        {
            case continuousRatio:
            case discreteRatio:
                return true;
            case rectangularBounds: 
            case discreteRatioXY: 
                return false;
        }
    }

    /// Returns `true` if this `SizeConstraints` allows this size.
    bool isValidSize(int width, int height) @trusted
    {
        int validw = width,
            validh = height;
        getNearestValidSize(&validw, &validh);
        return validw == width && validh == height; // if the input size is valid, will return the same
    }

    /// Given an input size, get the nearest valid size.
    void getNearestValidSize(int* inoutWidth, int* inoutHeight)
    {
        final switch(type) with (Type)
        {
            case continuousRatio:
                // find estimate of scale
                float scale = 0.5f * (*inoutWidth / (cast(float)defaultWidth) 
                                      + *inoutHeight / (cast(float)defaultHeight));
                if (scale < minScale) scale = minScale;
                if (scale > maxScale) scale = maxScale;
                *inoutWidth = cast(int)(0.5f + scale * defaultWidth);
                *inoutHeight = cast(int)(0.5f + scale * defaultHeight);
                break;

            case discreteRatio:
            {
                float scale = 0.5f * (*inoutWidth / (cast(float)defaultWidth) 
                                      + *inoutHeight / (cast(float)defaultHeight));
                scale = findBestMatchingFloat(scale, discreteScales[0..numDiscreteScales]);
                *inoutWidth = cast(int)(0.5f + scale * defaultWidth);
                *inoutHeight = cast(int)(0.5f + scale * defaultHeight);
                break;
            }

            case rectangularBounds: 
                alias w = inoutWidth;
                alias h = inoutHeight;
                if (*w < minWidth)  *w = minWidth;
                if (*h < minHeight) *h = minHeight;
                if (*w > maxWidth)  *w = maxWidth;
                if (*h > maxHeight) *h = maxHeight;
                break;

            case discreteRatioXY:
            {
                float scaleX = (*inoutWidth) / (cast(float)defaultWidth);
                float scaleY = (*inoutHeight) / (cast(float)defaultHeight);
                scaleX = findBestMatchingFloat(scaleX, discreteScalesX[0..numDiscreteScalesX]);
                scaleY = findBestMatchingFloat(scaleY, discreteScalesY[0..numDiscreteScalesY]);
                *inoutWidth = cast(int)(0.5f + scaleX * defaultWidth);
                *inoutHeight = cast(int)(0.5f + scaleY * defaultHeight);
            }
        }
    }

    /// Given an input size, get a valid size that is the maximum that would fit inside a `inoutWidth` x `inoutHeight`, but smaller.
    /// Prefer validity if no smaller size is available.
    void getMaxSmallerValidSize(int* inoutWidth, int* inoutHeight)
    {
        final switch(type) with (Type)
        {
            case continuousRatio:
            {
                // find estimate of scale
                float scaleX = *inoutWidth / (cast(float)defaultWidth);
                float scaleY = *inoutHeight / (cast(float)defaultHeight);
                float scale = (scaleX < scaleY) ? scaleX : scaleY;
                if (scale < minScale) scale = minScale;
                if (scale > maxScale) scale = maxScale;
                *inoutWidth = cast(int)(0.5f + scale * defaultWidth);
                *inoutHeight = cast(int)(0.5f + scale * defaultHeight);
                break;
            }

            case discreteRatio:
            {
                // Note: because of ugly rounding issue, we cannot just find the scale from input size.
                // See Issue #593. Find the best size by generating the size forward and see which one fits.

                int w = 0;
                int h = 0;

                int bestIndex = 0; // should be the smallest size... not checked
                float bestScore = float.infinity;
                for (int n = 0; n < numDiscreteScales; ++n)
                {
                    // Generate a possible size.
                    int cand_w = cast(int)(0.5f + discreteScales[n] * defaultWidth);
                    int cand_h = cast(int)(0.5f + discreteScales[n] * defaultHeight);

                    float scoreX = (*inoutWidth - cand_w);
                    float scoreY = (*inoutHeight - cand_h);
                    float score = scoreX + scoreY;
                    if ( (scoreX >= 0) && (scoreY >= 0) && (score < bestScore) )
                    {
                        bestScore = score;
                        bestIndex = n;
                    }
                }

                *inoutWidth = cast(int)(0.5f + discreteScales[bestIndex] * defaultWidth);
                *inoutHeight = cast(int)(0.5f + discreteScales[bestIndex] * defaultHeight);
                break;
            }

            case rectangularBounds: 
                alias w = inoutWidth;
                alias h = inoutHeight;
                if (*w < minWidth)  *w = minWidth;
                if (*h < minHeight) *h = minHeight;
                if (*w > maxWidth)  *w = maxWidth;
                if (*h > maxHeight) *h = maxHeight;
                break;

            case discreteRatioXY:
            {
                // +0.5f since a smaller ratio would lead to a smaller size being generated
                float scaleX = (*inoutWidth + 0.5f) / (cast(float)defaultWidth);
                float scaleY = (*inoutHeight + 0.5f) / (cast(float)defaultHeight);
                scaleX = findMinMatchingFloat(scaleX, discreteScalesX[0..numDiscreteScalesX]);
                scaleY = findMinMatchingFloat(scaleY, discreteScalesY[0..numDiscreteScalesY]);
                *inoutWidth = cast(int)(0.5f + scaleX * defaultWidth);
                *inoutHeight = cast(int)(0.5f + scaleY * defaultHeight);
            }
        }
    }

private:

    enum MAX_POSSIBLE_SCALES = 12;

    Type type;

    int defaultWidth;
    int defaultHeight;
    
    int numDiscreteScales = 0;
    float[MAX_POSSIBLE_SCALES] discreteScales; // only used with discreteRatio or rectangularBoundsDiscrete case

    alias numDiscreteScalesX = numDiscreteScales;
    alias discreteScalesX = discreteScales;
    int numDiscreteScalesY = 0;
    float[MAX_POSSIBLE_SCALES] discreteScalesY; // only used with rectangularBoundsDiscrete case

    float minScale, maxScale;          // only used with continuousRatio case

    int minWidth;                      // only used in rectangularBounds case
    int minHeight;
    int maxWidth;
    int maxHeight;
}

private:

// Return arr[n], the nearest element of the array to x
static float findBestMatchingFloat(float x, const(float)[] arr) pure @trusted
{
    assert(arr.length > 0);
    float bestScore = -float.infinity;
    int bestIndex = 0;
    for (int n = 0; n < cast(int)arr.length; ++n)
    {
        float score = -fast_fabs(arr[n] - x);
        if (score > bestScore)
        {
            bestScore = score;
            bestIndex = n;
        }
    }
    return arr[bestIndex];
}

// Return arr[n], the element of the array that approach `threshold` better without exceeding it
// (unless every proposed item exceed)
static float findMinMatchingFloat(float threshold, const(float)[] arr) pure @trusted
{
    assert(arr.length > 0);
    float bestScore = float.infinity;
    int bestIndex = 0;
    for (int n = 0; n < cast(int)arr.length; ++n)
    {
        float score = (threshold - arr[n]);
        if ( (score >= 0) && (score < bestScore) )
        {
            bestScore = score;
            bestIndex = n;
        }
    }

    // All items were above the threshold, use nearest item.
    if (bestIndex == -1)
        return findBestMatchingFloat(threshold, arr);

    return arr[bestIndex];
}

@trusted unittest
{
    int w, h;

    SizeConstraints a, b;
    a = makeSizeConstraintsFixed(640, 480);
    b = a;

    float[3] ratios = [0.5f, 1.0f, 2.0f];
    SizeConstraints c = makeSizeConstraintsDiscrete(640, 480, ratios[]);
    assert(c.isValidSize(640, 480));

    w = 640*2-1;
    h = 480-1;
    c.getMaxSmallerValidSize(&w, &h);
    assert(w == 320 && h == 240);

    w = 640-1;
    h = 480;
    c.getMaxSmallerValidSize(&w, &h);
    assert(w == 320 && h == 240);

    c = makeSizeConstraintsContinuous(640, 480, 0.5f, 2.0f);
    assert(c.isValidSize(640, 480));
    assert(!c.isValidSize(640/4, 480/4));
    assert(c.isValidSize(640/2, 480/2));
    assert(c.isValidSize(640*2, 480*2));
    
    a.suggestDefaultSize(&w, &h);
    assert(w == 640 && h == 480);

    float[3] ratiosX = [0.5f, 1.0f, 2.0f];
    float[4] ratiosY = [0.5f, 1.0f, 2.0f, 3.0f];
    c = makeSizeConstraintsDiscreteXY(900, 500, ratiosX[], ratiosY[]);
    c.suggestDefaultSize(&w, &h);
    assert(w == 900 && h == 500);

    w = 100; h = 501;
    c.getNearestValidSize(&w, &h);
    assert(w == 450 && h == 500);

    w = 1000; h = 2500;
    c.getNearestValidSize(&w, &h);
    assert(w == 900 && h == 1500);
}

unittest
{
    float[4] A = [1.0f, 2, 3, 4];
    assert( findMinMatchingFloat(3.8f, A) == 3 );
    assert( findMinMatchingFloat(10.0f, A) == 4 );
    assert( findMinMatchingFloat(2.0f, A) == 2 );
    assert( findMinMatchingFloat(-1.0f, A) == 1 );
    assert( findBestMatchingFloat(3.8f, A) == 4 );
    assert( findBestMatchingFloat(10.0f, A) == 4 );
    assert( findBestMatchingFloat(2.0f, A) == 2 );
    assert( findBestMatchingFloat(-1.0f, A) == 1 );
}

// Issue #593, max min valid size not matching
@trusted unittest
{
    static immutable float[6] ratios = [0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
    SizeConstraints c = makeSizeConstraintsDiscrete(626, 487, ratios);
    int w = 1096, h = 852;
    c.getMaxSmallerValidSize(&w, &h);
    assert(w == 1096 && h == 852);

    // Same but with separate XY
    c = makeSizeConstraintsDiscreteXY(487, 487, ratios, ratios);
    w = 852;
    h = 852;
    c.getMaxSmallerValidSize(&w, &h);
    assert(w == 852 && h == 852);
}