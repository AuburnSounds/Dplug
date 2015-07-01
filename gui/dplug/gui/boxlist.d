/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.boxlist;

// Operations on list of boxes

import std.algorithm;

import gfm.math;

import dplug.core.alignedbuffer;

/// Returns: Bounding boxes of all bounding boxes.
box2i boundingBox(box2i[] boxes) pure nothrow @nogc
{
    if (boxes.length == 0)
        return box2i(0, 0, 0, 0);
    else
    {
        // Computes union of all boxes
        box2i unionBox = boxes[0];
        for(int i = 1; i < cast(int)boxes.length; ++i)
            unionBox = unionBox.expand(boxes[i]);
        return unionBox;
    }
}


/// Make 4 boxes that are A without C (C is contained in A)
/// Some may be empty though since C touch at least one edge of A

/// General case
/// +---------+               +---------+
/// |    A    |               |    D    |
/// |  +---+  |   After split +--+---+--+
/// |  | C |  |        =>     | E|   |F |   At least one of D, E, F or G is empty
/// |  +---+  |               +--+---+--+
/// |         |               |    G    |
/// +---------+               +---------+
void boxSubtraction(in box2i A, in box2i C, out box2i D, out box2i E, out box2i F, out box2i G) pure nothrow @nogc
{
    D = box2i(A.min.x, A.min.y, A.max.x, C.min.y);
    E = box2i(A.min.x, C.min.y, C.min.x, C.max.y);
    F = box2i(C.max.x, C.min.y, A.max.x, C.max.y);
    G = box2i(A.min.x, C.max.y, A.max.x, A.max.y);
}

// Change the list of boxes so that the coverage is the same but none overlaps
// Every box pushed in filtered are non-intersecting.
// TODO: something better than O(n^2)
void removeOverlappingAreas(box2i[] boxes, AlignedBuffer!box2i filtered)
{
    for(int i = 0; i < cast(int)(boxes.length); ++i)
    {
        box2i A = boxes[i];

        assert(A.isSorted());

        // empty boxes aren't kept
        if (A.volume() <= 0)
            continue;

        bool foundIntersection = false;

        // test A against all other rectangles, if it pass, it is pushed
        for(int j = i + 1; j < cast(int)(boxes.length); ++j)
        {
            box2i B = boxes[j];

            box2i C = A.intersection(B);
            bool doesIntersect =  C.isSorted() && (!C.empty());

            if (doesIntersect)
            {
                // case 1: A contains B, B is removed from the array, and no intersection considered
                if (A.contains(B))
                {
                    boxes = boxes.remove(j); // TODO: remove this allocation
                    j = j - 1;
                    continue;
                }

                foundIntersection = true; // A will not be pushed as is

                if (B.contains(A))
                {
                    break; // nothing from A is kept
                }
                else
                {
                    // computes A without C
                    box2i D, E, F, G;
                    boxSubtraction(A, C, D, E, F, G);

                    if (!D.empty)
                        boxes ~= D;
                    if (!E.empty)
                        boxes ~= E;
                    if (!F.empty)
                        boxes ~= F;
                    if (!G.empty)
                        boxes ~= G;

                    // no need to search for other intersection in A, since its parts have
                    // been pushed
                    break;
                }
            }
        }

        if (!foundIntersection)
            filtered.pushBack(A);
    }
}

unittest
{
    box2i[] bl = [
        box2i(0, 0, 4, 4),
        box2i(2, 2, 6, 6),
        box2i(1, 1, 2, 2)
    ];
    import std.stdio;

    box2i[] bb;
    removeOverlappingAreas(bl, bb);
    assert(bb == [ box2i(2, 2, 6, 6), box2i(0, 0, 4, 2), box2i(0, 2, 2, 4) ] );

    assert(bl.boundingBox() == box2i(0, 0, 6, 6));
}


// Split each boxes in smaller boxes.
void tileAreas(in box2i[] areas, int maxWidth, int maxHeight, AlignedBuffer!box2i splitted) nothrow
{
    foreach(area; areas)
    {
        assert(!area.empty);
        int nWidth = (area.width + maxWidth - 1) / maxWidth;
        int nHeight = (area.height + maxHeight - 1) / maxHeight;

        foreach (int j; 0..nHeight)
        {
            int y0 = maxHeight * j;
            int y1 = std.algorithm.min(y0 + maxHeight, area.height);

            foreach (int i; 0..nWidth)
            {
                int x0 = maxWidth * i;
                int x1 = std.algorithm.min(x0 + maxWidth, area.width);

                box2i b = box2i(x0, y0, x1, y1).translate(area.min);
                assert(area.contains(b));
                splitted.pushBack(b);
            }
        }
    }
}

/// For debug purpose.
/// Returns: true if none of the boxes overlap.
bool haveNoOverlap(in box2i[] areas) nothrow @nogc
{
    int N = cast(int)areas.length;

    // check every pair of boxes for overlap, inneficient
    for (int i = 0; i < N; ++i)
    {
        assert(areas[i].isSorted());
        for (int j = i + 1; j < N; ++j)
        {
            if (areas[i].intersects(areas[j]))
                return false;
        }
    }
    return true;
}

unittest
{
    assert(haveNoOverlap([ box2i( 0, 0, 1, 1), box2i(1, 1, 2, 2) ]));
    assert(!haveNoOverlap([ box2i( 0, 0, 1, 1), box2i(0, 0, 2, 1) ]));
}
