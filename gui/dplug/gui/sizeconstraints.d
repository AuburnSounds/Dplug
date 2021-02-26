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
                                            const(float)[] availableScales)
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


/// Describe what size in logical pixels are possible.
/// A GUIGraphics is given a `SizeConstraints` in its constructor.
struct SizeConstraints
{
public:
nothrow:
@nogc:

    enum Type /// 
    {
        continuousRatio,
        discreteRatio,
        rectangularBounds
    }

    /// Suggest a valid size for plugin first opening.
    void suggestDefaultSize(int* width, int* height)
    {
        *width = defaultWidth;
        *height = defaultHeight;
    }

    /// Returns `true` if this `SizeConstraints` preserve plugin aspect ratio.
    bool preserveAspectRatio()
    {
        final switch(type) with (Type)
        {
            case continuousRatio:
            case discreteRatio:     return true;
            case rectangularBounds: return false;
        }
    }

    /// Returns `true` if this `SizeConstraints` allows this size.
    bool isValidSize(int width, int height)
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
                float scale = 0.5f * (*inoutWidth / defaultWidth + *inoutHeight / defaultHeight);
                if (scale < minScale) scale = minScale;
                if (scale > maxScale) scale = maxScale;
                *inoutWidth = cast(int)(0.5f + scale * defaultWidth);
                *inoutHeight = cast(int)(0.5f + scale * defaultHeight);
                break;

            case discreteRatio:
                float scale = 0.5f * (*inoutWidth / defaultWidth + *inoutHeight / defaultHeight);
                float bestScore = -float.infinity;
                int bestScale = 0;
                for (int n = 0; n < numDiscreteScales; ++n)
                {
                    float score = -fast_fabs(discreteScales[n] - scale);
                    if (score > bestScore)
                    {
                        bestScore = score;
                        bestScale = n;
                    }
                }
                scale = discreteScales[bestScale];
                *inoutWidth = cast(int)(0.5f + scale * defaultWidth);
                *inoutHeight = cast(int)(0.5f + scale * defaultHeight);
                break;

            case rectangularBounds: 
                alias w = inoutWidth;
                alias h = inoutHeight;
                if (*w < minWidth)  *w = minWidth;
                if (*h < minHeight) *h = minHeight;
                if (*w > maxWidth)  *w = maxWidth;
                if (*h > maxHeight) *h = maxHeight;
                break;
        }
    }

private:

    enum MAX_POSSIBLE_SCALES = 8;

    Type type;

    int defaultWidth;
    int defaultHeight;
    
    int numDiscreteScales = 0;
    float[MAX_POSSIBLE_SCALES] discreteScales; // only used with discreteRatio case

    float minScale, maxScale;          // only used with continuousRatio case

    int minWidth;                      // only used in rectangularBounds case
    int minHeight;
    int maxWidth;
    int maxHeight;
}

unittest
{
    SizeConstraints a, b;
    a = makeSizeConstraintsFixed(640, 480);
    b = a;

    float[3] ratios = [0.5f, 1.0f, 2.0f];
    SizeConstraints c = makeSizeConstraintsDiscrete(640, 480, ratios[]);
    assert(c.isValidSize(640, 480));

    c = makeSizeConstraintsContinuous(640, 480, 0.5f, 2.0f);
    assert(c.isValidSize(640, 480));
    assert(!c.isValidSize(640/4, 480/4));
    assert(c.isValidSize(640/2, 480/2));
    assert(c.isValidSize(640*2, 480*2));

    int w, h;
    a.suggestDefaultSize(&w, &h);
    assert(w == 640 && h == 480);
}