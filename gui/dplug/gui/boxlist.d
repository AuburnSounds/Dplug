module dplug.gui.boxlist;

import std.algorithm;

import gfm.math;

/// A boxlist is a collection of box2i, used in culling algorithms.

struct BoxList
{
    box2i[] boxes;
    alias boxes this; // subtype of box

    /// Returns: Bounding boxes of all bounding boxes.
    box2i boundingBox() pure const nothrow @nogc
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

    // change the list of boxes so that the coverage is the same but none overlaps
    // also filters out empty/invalid boxes
    // TODO: something better than O(n^2)
    //       in-place to avoid reallocating an array
    box2i[] removeOverlappingAreas()
    {
        // every box push in this list are non-intersecting
        box2i[] filtered;

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

                    // case 1: A contains B, B is simply removed, no intersection considered
                    if (A.contains(B))
                    {
                        continue;
                    }

                    foundIntersection = true; // A will not be pushed as is

                    if (B.contains(A))
                    {
                        break; // nothing from A is kept
                    }
                    else 
                    {
                        // Make 4 boxes that are A without C (C is contained in A)
                        // Some may be empty though since C touch at least one edge of A

                        // General case
                        // +---------+               +---------+ 
                        // |    A    |               |    D    |
                        // |  +---+  |   After split +--+---+--+
                        // |  | C |  |        =>     | E|   |F |   At least one of D, E, F or G is empty
                        // |  +---+  |               +--+---+--+
                        // |         |               |    G    |
                        // +---------+               +---------+

                        box2i D = box2i(A.min.x, A.min.y, A.max.x, C.min.y);
                        box2i E = box2i(A.min.x, C.min.y, C.min.x, C.max.y);
                        box2i F = box2i(C.max.x, C.min.y, A.max.x, C.max.y);
                        box2i G = box2i(A.min.x, C.max.y, A.max.x, A.max.y);    


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
                filtered ~= A;
        }    
        return filtered;
    }
}

unittest
{
    BoxList bl;

    bl.boxes = [
        box2i(0, 0, 4, 4),
        box2i(2, 2, 6, 6),
        box2i(1, 1, 2, 2)
    ];
    import std.stdio;

    auto bb = bl.removeOverlappingAreas();
    assert(bb == [ box2i(2, 2, 6, 6), box2i(0, 0, 4, 2), box2i(0, 2, 2, 4) ] );

    assert(bl.boundingBox() == box2i(0, 0, 6, 6));
}