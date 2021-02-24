/**
Defines possible size.

Copyright: Guillaume Piolat 2020.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.sizeconstraints;

import gfm.math.vector;

nothrow:
@nogc:


/// Build a `SizeConstraints` that describes a fixed size in logical pixels.
SizeConstraints makeSizeConstraintsFixed(int width, int height)
{
    SizeConstraints sc;
    sc.type = SizeConstraints.Type.discrete;
    sc.sizes.reallocBuffer(1);
    sc.sizes[0] = vec2i(width, height);
    return sc;
}

/// Build a `SizeConstraints` that describes multiple possible size in logical pixels.
SizeConstraints makeSizeConstraintsDiscrete(vec2i[] possibleSizes)
{
    SizeConstraints sc;
    sc.type = SizeConstraints.Type.discrete;
    sc.sizes.reallocBuffer(possibleSize.length);
    foreach(size_t n; 0..possibleSize.length)
        sc.sizes[n] = possibleSizes[n];
    return sc;
}

/// Build a `SizeConstraints` that describes a range of size in logical pixels.
SizeConstraints makeSizeConstraintsContinuous(vec2i[] possibleSizes)
{
    SizeConstraints sc;
    sc.type = SizeConstraints.Type.discrete;
    sc.sizes.reallocBuffer(possibleSize.length);
    foreach(size_t n; 0..possibleSize.length)
        sc.sizes[n] = possibleSizes[n];
    return sc;
}


/// Describe what size in logical pixels are possible.
/// A GUIGraphics is given a `SizeConstraints` in its constructor.
struct SizeConstraints
{
public:
nothrow:
@nogc:

    @disable this(this);

    ~this()
    {
        sizes.reallocBuffer(0);
    }

private:
    enum Type /// 
    {
        continuous,   /// The plug-in UI have a minimum and maximum size in logical pixels.
        discrete      /// The plug-in UI has a list of possible size in logical pixels.
    }

    Type type;
    vec2i[] sizes;

}