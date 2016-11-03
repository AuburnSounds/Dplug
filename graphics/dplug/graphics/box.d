/**
* Copyright: Copyright Auburn Sounds 2016.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
/**
  This module implements a generic axis-aligned bounding box (AABB).
 */
module dplug.graphics.box;

import std.math,
       std.traits,
       std.conv,
       std.string;

import dplug.graphics.vector;

/// N-dimensional half-open interval [a, b[.
struct Box(T, int N)
{
nothrow:
@nogc:

    static assert(N > 0);

    public
    {
        alias Vector!(T, N) bound_t;

        bound_t min; // not enforced, the box can have negative volume
        bound_t max;

        /// Construct a box which extends between 2 points.
        /// Boundaries: min is inside the box, max is just outside.
        @nogc this(bound_t min_, bound_t max_) pure nothrow
        {
            min = min_;
            max = max_;
        }

        static if (N == 1)
        {
            @nogc this(T min_, T max_) pure nothrow
            {
                min.x = min_;
                max.x = max_;
            }
        }

        static if (N == 2)
        {
            @nogc this(T min_x, T min_y, T max_x, T max_y) pure nothrow
            {
                min = bound_t(min_x, min_y);
                max = bound_t(max_x, max_y);
            }
        }

        static if (N == 3)
        {
            @nogc this(T min_x, T min_y, T min_z, T max_x, T max_y, T max_z) pure nothrow
            {
                min = bound_t(min_x, min_y, min_z);
                max = bound_t(max_x, max_y, max_z);
            }
        }


        @property
        {
            /// Returns: Dimensions of the box.
            @nogc bound_t size() pure const nothrow
            {
                return max - min;
            }

            /// Returns: Center of the box.
            @nogc bound_t center() pure const nothrow
            {
                return (min + max) / 2;
            }

            /// Returns: Width of the box, always applicable.
            static if (N >= 1)
            @nogc T width() pure const nothrow @property
            {
                return max.x - min.x;
            }

            /// Returns: Height of the box, if applicable.
            static if (N >= 2)
            @nogc T height() pure const nothrow @property
            {
                return max.y - min.y;
            }

            /// Returns: Depth of the box, if applicable.
            static if (N >= 3)
            @nogc T depth() pure const nothrow @property
            {
                return max.z - min.z;
            }

            /// Returns: Signed volume of the box.
            @nogc T volume() pure const nothrow
            {
                T res = 1;
                bound_t size = size();
                for(int i = 0; i < N; ++i)
                    res *= size[i];
                return res;
            }

            /// Returns: true if empty.
            @nogc bool empty() pure const nothrow
            {
                bound_t size = size();
                mixin(generateLoopCode("if (min[@] == max[@]) return true;", N));
                return false;
            }
        }

        /// Returns: true if it contains point.
        @nogc bool contains(bound_t point) pure const nothrow
        {
            assert(isSorted());
            for(int i = 0; i < N; ++i)
                if ( !(point[i] >= min[i] && point[i] < max[i]) )
                    return false;

            return true;
        }

        /// Returns: true if it contains box other.
        @nogc bool contains(Box other) pure const nothrow
        {
            assert(isSorted());
            assert(other.isSorted());

            mixin(generateLoopCode("if ( (other.min[@] < min[@]) || (other.max[@] > max[@]) ) return false;", N));
            return true;
        }

        /// Euclidean squared distance from a point.
        /// See_also: Numerical Recipes Third Edition (2007)
        @nogc real squaredDistance(bound_t point) pure const nothrow
        {
            assert(isSorted());
            real distanceSquared = 0;
            for (int i = 0; i < N; ++i)
            {
                if (point[i] < min[i])
                    distanceSquared += (point[i] - min[i]) ^^ 2;

                if (point[i] > max[i])
                    distanceSquared += (point[i] - max[i]) ^^ 2;
            }
            return distanceSquared;
        }

        /// Euclidean distance from a point.
        /// See_also: squaredDistance.
        @nogc real distance(bound_t point) pure const nothrow
        {
            return sqrt(squaredDistance(point));
        }

        /// Euclidean squared distance from another box.
        /// See_also: Numerical Recipes Third Edition (2007)
        @nogc real squaredDistance(Box o) pure const nothrow
        {
            assert(isSorted());
            assert(o.isSorted());
            real distanceSquared = 0;
            for (int i = 0; i < N; ++i)
            {
                if (o.max[i] < min[i])
                    distanceSquared += (o.max[i] - min[i]) ^^ 2;

                if (o.min[i] > max[i])
                    distanceSquared += (o.min[i] - max[i]) ^^ 2;
            }
            return distanceSquared;
        }

        /// Euclidean distance from another box.
        /// See_also: squaredDistance.
        @nogc real distance(Box o) pure const nothrow
        {
            return sqrt(squaredDistance(o));
        }

        /// Assumes sorted boxes.
        /// This function deals with empty boxes correctly.
        /// Returns: Intersection of two boxes.
        @nogc Box intersection(Box o) pure const nothrow
        {
            assert(isSorted());
            assert(o.isSorted());

            // Return an empty box if one of the boxes is empty
            if (empty())
                return this;

            if (o.empty())
                return o;

            Box result = void;
            for (int i = 0; i < N; ++i)
            {
                T maxOfMins = (min.v[i] > o.min.v[i]) ? min.v[i] : o.min.v[i];
                T minOfMaxs = (max.v[i] < o.max.v[i]) ? max.v[i] : o.max.v[i];
                result.min.v[i] = maxOfMins;
                result.max.v[i] = minOfMaxs >= maxOfMins ? minOfMaxs : maxOfMins;
            }
            return result;
        }

        /// Assumes sorted boxes.
        /// This function deals with empty boxes correctly.
        /// Returns: Intersection of two boxes.
        @nogc bool intersects(Box other) pure const nothrow
        {
            Box inter = this.intersection(other);
            return inter.isSorted() && !inter.empty();
        }

        /// Extends the area of this Box.
        @nogc Box grow(bound_t space) pure const nothrow
        {
            Box res = this;
            res.min -= space;
            res.max += space;
            return res;
        }

        /// Shrink the area of this Box. The box might became unsorted.
        @nogc Box shrink(bound_t space) pure const nothrow
        {
            return grow(-space);
        }

        /// Extends the area of this Box.
        @nogc Box grow(T space) pure const nothrow
        {
            return grow(bound_t(space));
        }

        /// Translate this Box.
        @nogc Box translate(bound_t offset) pure const nothrow
        {
            return Box(min + offset, max + offset);
        }

        /// Shrinks the area of this Box.
        /// Returns: Shrinked box.
        @nogc Box shrink(T space) pure const nothrow
        {
            return shrink(bound_t(space));
        }

        /// Expands the box to include point.
        /// Returns: Expanded box.
        @nogc Box expand(bound_t point) pure const nothrow
        {
            import vector = dplug.graphics.vector;
            return Box(vector.minByElem(min, point), vector.maxByElem(max, point));
        }

        /// Expands the box to include another box.
        /// This function deals with empty boxes correctly.
        /// Returns: Expanded box.
        @nogc Box expand(Box other) pure const nothrow
        {
            assert(isSorted());
            assert(other.isSorted());

            // handle empty boxes
            if (empty())
                return other;
            if (other.empty())
                return this;

            Box result = void;
            for (int i = 0; i < N; ++i)
            {
                T minOfMins = (min.v[i] < other.min.v[i]) ? min.v[i] : other.min.v[i];
                T maxOfMaxs = (max.v[i] > other.max.v[i]) ? max.v[i] : other.max.v[i];
                result.min.v[i] = minOfMins;
                result.max.v[i] = maxOfMaxs;
            }
            return result;
        }

        /// Returns: true if each dimension of the box is >= 0.
        @nogc bool isSorted() pure const nothrow
        {
            for(int i = 0; i < N; ++i)
            {
                if (min[i] > max[i])
                    return false;
            }
            return true;
        }

        /// Assign with another box.
        @nogc ref Box opAssign(U)(U x) nothrow if (isBox!U)
        {
            static if(is(U.element_t : T))
            {
                static if(U._size == _size)
                {
                    min = x.min;
                    max = x.max;
                }
                else
                {
                    static assert(false, "no conversion between boxes with different dimensions");
                }
            }
            else
            {
                static assert(false, "no conversion from " ~ U.element_t.stringof ~ " to " ~ element_t.stringof);
            }
            return this;
        }

        /// Returns: true if comparing equal boxes.
        @nogc bool opEquals(U)(U other) pure const nothrow if (is(U : Box))
        {
            return (min == other.min) && (max == other.max);
        }

        static if (N == 2)
        {
            /// Helper function to create rectangle with a given point, width and height.
            static @nogc Box rectangle(T x, T y, T width, T height) pure nothrow
            {
                return Box(x, y, x + width, y + height);
            }
        }
    }

    private
    {
        enum _size = N;
        alias T element_t;
    }
}

/// Instanciate to use a 2D box.
template box2(T)
{
    alias Box!(T, 2) box2;
}

/// Instanciate to use a 3D box.
template box3(T)
{
    alias Box!(T, 3) box3;
}


alias box2!int box2i; /// 2D box with integer coordinates.
alias box3!int box3i; /// 3D box with integer coordinates.
alias box2!float box2f; /// 2D box with float coordinates.
alias box3!float box3f; /// 3D box with float coordinates.
alias box2!double box2d; /// 2D box with double coordinates.
alias box3!double box3d; /// 3D box with double coordinates.

unittest
{
    box2i a = box2i(1, 2, 3, 4);
    assert(a.width == 2);
    assert(a.height == 2);
    assert(a.volume == 4);
    box2i b = box2i(vec2i(1, 2), vec2i(3, 4));
    assert(a == b);
    box2i c = box2i(0, 0, 1,1);
    assert(c.translate(vec2i(3, 3)) == box2i(3, 3, 4, 4));
    assert(c.contains(vec2i(0, 0)));
    assert(!c.contains(vec2i(1, 1)));
    assert(b.contains(b));
    box2i d = c.expand(vec2i(3, 3));
    assert(d.contains(vec2i(2, 2)));

    assert(d == d.expand(d));

    assert(!box2i(0, 0, 4, 4).contains(box2i(2, 2, 6, 6)));

    assert(box2f(0, 0, 0, 0).empty());
    assert(!box2f(0, 2, 1, 1).empty());
    assert(!box2f(0, 0, 1, 1).empty());

    assert(box2i(260, 100, 360, 200).intersection(box2i(100, 100, 200, 200)).empty());

    // union with empty box is identity
    assert(a.expand(box2i(10, 4, 10, 6)) == a);

    // intersection with empty box is empty
    assert(a.intersection(box2i(10, 4, 10, 6)).empty);

    assert(box2i.rectangle(1, 2, 3, 4) == box2i(1, 2, 4, 6));
}

/// True if `T` is a kind of Box
enum isBox(T) = is(T : Box!U, U...);

unittest
{
    static assert( isBox!box2f);
    static assert( isBox!box3d);
    static assert( isBox!(Box!(real, 2)));
    static assert(!isBox!vec2f);
}

/// Get the numeric type used to measure a box's dimensions.
alias DimensionType(T : Box!U, U...) = U[0];

///
unittest
{
    static assert(is(DimensionType!box2f == float));
    static assert(is(DimensionType!box3d == double));
}

private
{
    static const(char)[] generateLoopCode(string formatString, int N) pure nothrow
    {
        if (!__ctfe)
            return null;
        else
        {
            if (N < 10)
            {
                size_t L = formatString.length;
                char[] result;
                result.length = L * N;
                for (int i = 0; i < N; ++i)
                {
                    size_t start = i * L;
                    for(size_t j = 0; j < L; ++j)
                    {
                        char ch = formatString[j];
                        if (ch == '@')
                            result[start + j] = cast(char)('0' + i);
                        else
                            result[start + j] = ch;
                    }
                }
                return result;
            }
            else
            {
                char[] result;
                for (int i = 0; i < N; ++i)
                {
                    string index = ctIntToString(i);
                    // replace all @ by indices
                    result ~= formatString.replace("@", index);
                }
                return result;
            }
        }
    }

    // Speed-up CTFE conversions
    static string ctIntToString(int n) pure nothrow
    {
        static immutable string[10] table = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
        if (n < 10)
            return table[n];
        else
            return to!string(n);
    }
}