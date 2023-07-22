/**
 * N-dimensional half-open interval [a, b[.
 *
 * Copyright: Copyright Guillaume Piolat 2015-2021.
 *            Copyright Ahmet Sait 2021.
 *            Copyright Ryan Roden-Corrent 2016.
 *            Copyright Nathan Sashihara 2018.
 *            Copyright Colden Cullen 2014.
 *
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module dplug.math.box;

import std.math,
       std.traits;

import dplug.math.vector;

/// N-dimensional half-open interval [a, b[.
struct Box(T, int N)
{
    static assert(N > 0);

    public
    {
        alias bound_t = Vector!(T, N);

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

            /// Sets size of the box assuming min point is the pivot.
            /// Returns: Dimensions of the box.
            @nogc bound_t size(bound_t value) pure nothrow
            {
                max = min + value;
                return value;
            }

            /// Returns: Center of the box.
            @nogc bound_t center() pure const nothrow
            {
                return (min + max) / 2;
            }

            static if (N >= 1)
            {
                /// Returns: Width of the box, always applicable.
                @nogc T width() pure const nothrow @property
                {
                    return max.x - min.x;
                }

                /// Sets width of the box assuming min point is the pivot.
                /// Returns: Width of the box, always applicable.
                @nogc T width(T value) pure nothrow @property
                {
                    max.x = min.x + value;
                    return value;
                }
            }

            static if (N >= 2)
            {
                /// Returns: Height of the box, if applicable.
                @nogc T height() pure const nothrow @property
                {
                    return max.y - min.y;
                }

                /// Sets height of the box assuming min point is the pivot.
                /// Returns: Height of the box, if applicable.
                @nogc T height(T value) pure nothrow @property
                {
                    max.y = min.y + value;
                    return value;
                }
            }

            static if (N >= 3)
            {
                /// Returns: Depth of the box, if applicable.
                @nogc T depth() pure const nothrow @property
                {
                    return max.z - min.z;
                }

                /// Sets depth of the box assuming min point is the pivot.
                /// Returns: Depth of the box, if applicable.
                @nogc T depth(T value) pure nothrow @property
                {
                    max.z = min.z + value;
                    return value;
                }
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
                mixin(generateLoopCode!("if (min[@] == max[@]) return true;", N)());
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

        static if (N >= 2)
        {
            /// Returns: true if it contains point `x`, `y`.
            @nogc bool contains(T x, T y) pure const nothrow
            {
                assert(isSorted());
                if ( !(x >= min.x && x < max.x) )
                    return false;
                if ( !(y >= min.y && y < max.y) )
                    return false;
                return true;
            }
        }

        static if (N >= 3)
        {
            /// Returns: true if it contains point `x`, `y`, `z`.
            @nogc bool contains(T x, T y, T z) pure const nothrow
            {
                assert(isSorted());
                if ( !(x >= min.x && x < max.x) )
                    return false;
                if ( !(y >= min.y && y < max.y) )
                    return false;
                if ( !(z >= min.z && z < max.z) )
                    return false;
                return true;
            }
        }

        /// Returns: true if it contains box other.
        @nogc bool contains(Box other) pure const nothrow
        {
            assert(isSorted());
            assert(other.isSorted());

            mixin(generateLoopCode!("if ( (other.min[@] < min[@]) || (other.max[@] > max[@]) ) return false;", N)());
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

        /// Scale the box by factor `scale`, and round the result to integer if needed.
        @nogc Box scaleByFactor(float scale) const nothrow
        {
            Box res;
            static if (isFloatingPoint!T)
            {
                res.min.x = min.x * scale;
                res.min.y = min.y * scale;
                res.max.x = max.x * scale;
                res.max.y = max.y * scale;
            }
            else
            {
                res.min.x = cast(T)( round(min.x * scale) );
                res.min.y = cast(T)( round(min.y * scale) );
                res.max.x = cast(T)( round(max.x * scale) );
                res.max.y = cast(T)( round(max.y * scale) );
            }
            return res;
        }

        static if (N == 2) // useful for UI that have horizontal and vertical scale
        {
            /// Scale the box by factor `scaleX` horizontally and `scaleY` vetically. 
            /// Round the result to integer if needed.
            @nogc Box scaleByFactor(float scaleX, float scaleY) const nothrow
            {
                Box res;
                static if (isFloatingPoint!T)
                {
                    res.min.x = min.x * scaleX;
                    res.min.y = min.y * scaleY;
                    res.max.x = max.x * scaleX;
                    res.max.y = max.y * scaleY;
                }
                else
                {
                    res.min.x = cast(T)( round(min.x * scaleX) );
                    res.min.y = cast(T)( round(min.y * scaleY) );
                    res.max.x = cast(T)( round(max.x * scaleX) );
                    res.max.y = cast(T)( round(max.y * scaleY) );
                }
                return res;
            }
        }

        static if (N >= 2)
        {
            /// Translate this Box by `x`, `y`.
            @nogc Box translate(T x, T y) pure const nothrow
            {
                Box res = this;
                res.min.x += x;
                res.min.y += y;
                res.max.x += x;
                res.max.y += y;
                return res;
            }
        }

        static if (N >= 3)
        {
            /// Translate this Box by `x`, `y`.
            @nogc Box translate(T x, T y, T z) pure const nothrow
            {
                Box res = this;
                res.min.x += x;
                res.min.y += y;
                res.min.z += z;
                res.max.x += x;
                res.max.y += y;
                res.max.z += z;
                return res;
            }
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
            import vector = dplug.math.vector;
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

        /// Returns: Absolute value of the Box to ensure each dimension of the
        /// box is >= 0.
        @nogc Box abs() pure const nothrow
        {
            Box!(T, N) s = this;
            for (int i = 0; i < N; ++i)
            {
                if (s.min.v[i] > s.max.v[i])
                {
                    T tmp = s.min.v[i];
                    s.min.v[i] = s.max.v[i];
                    s.max.v[i] = tmp;
                }
            }
            return s;
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

        /// Cast to other box types.
        @nogc U opCast(U)() pure const nothrow if (isBox!U)
        {
            U b = void;
            for(int i = 0; i < N; ++i)
            {
                b.min[i] = cast(U.element_t)(min[i]);
                b.max[i] = cast(U.element_t)(max[i]);
            }
            return b; // return a box where each element has been casted
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

/// Returns: A 2D rectangle with point `x`,`y`, `width` and `height`.
box2i rectangle(int x, int y, int width, int height) pure nothrow @nogc
{
    return box2i(x, y, x + width, y + height);
}

/// Returns: A 2D rectangle with point `x`,`y`, `width` and `height`.
box2f rectanglef(float x, float y, float width, float height) pure nothrow @nogc
{
    return box2f(x, y, x + width, y + height);
}

/// Returns: A 2D rectangle with point `x`,`y`, `width` and `height`.
box2d rectangled(double x, double y, double width, double height) pure nothrow @nogc
{
    return box2d(x, y, x + width, y + height);
}


unittest
{
    box2i a = box2i(1, 2, 3, 4);
    assert(a.width == 2);
    assert(a.height == 2);
    assert(a.volume == 4);
    box2i b = box2i(vec2i(1, 2), vec2i(3, 4));
    assert(a == b);

    box3i q = box3i(-3, -2, -1, 0, 1, 2);
    q.bound_t s = q.bound_t(11, 17, 19);
    q.bound_t q_min = q.min;
    assert((q.size = s) == s);
    assert(q.size == s);
    assert(q.min == q_min);
    assert(q.max == q.min + s);
    assert(q.max -  q.min == s);

    assert((q.width = s.z) == s.z);
    assert(q.width == s.z);
    assert(q.min.x == q_min.x);
    assert(q.max.x == q.min.x + s.z);
    assert(q.max.x -  q.min.x == s.z);

    assert((q.height = s.y) == s.y);
    assert(q.height == s.y);
    assert(q.min.y == q_min.y);
    assert(q.max.y == q.min.y + s.y);
    assert(q.max.y -  q.min.y == s.y);

    assert((q.depth = s.x) == s.x);
    assert(q.depth == s.x);
    assert(q.min.z == q_min.z);
    assert(q.max.z == q.min.z + s.x);
    assert(q.max.z -  q.min.z == s.x);

    assert(q.size == s.zyx);

    box3i n = box3i(2, 1, 0, -1, -2, -3);
    assert(n.abs == box3i(-1, -2, -3, 2, 1, 0));

    box2f bf = cast(box2f)b;
    assert(bf == box2f(1.0f, 2.0f, 3.0f, 4.0f));

    box3f qf = box3f(-0, 1f, 2.5f, 3.25f, 5.125f, 7.0625f);
    qf.bound_t sf = qf.bound_t(-11.5f, -17.25f, -19.125f);
    qf.bound_t qf_min = qf.min;
    assert((qf.size = sf) == sf);
    assert(qf.size == sf);
    assert(qf.min == qf_min);
    assert(qf.max == qf.min + sf);
    assert(qf.max -  qf.min == sf);

    assert((qf.width = sf.z) == sf.z);
    assert(qf.width == sf.z);
    assert(qf.min.x == qf_min.x);
    assert(qf.max.x == qf.min.x + sf.z);
    assert(qf.max.x -  qf.min.x == sf.z);

    assert((qf.height = sf.y) == sf.y);
    assert(qf.height == sf.y);
    assert(qf.min.y == qf_min.y);
    assert(qf.max.y == qf.min.y + sf.y);
    assert(qf.max.y -  qf.min.y == sf.y);

    assert((qf.depth = sf.x) == sf.x);
    assert(qf.depth == sf.x);
    assert(qf.min.z == qf_min.z);
    assert(qf.max.z == qf.min.z + sf.x);
    assert(qf.max.z -  qf.min.z == sf.x);

    assert(qf.size == sf.zyx);

    box2i c = box2i(0, 0, 1,1);
    assert(c.translate(vec2i(3, 3)) == box2i(3, 3, 4, 4));
    assert(c.translate(3, 3) == box2i(3, 3, 4, 4));
    assert(c.contains(vec2i(0, 0)));
    assert(c.contains(0, 0));
    assert(!c.contains(vec2i(1, 1)));
    assert(!c.contains(1, 1));
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
    assert(rectangle(1, 2, 3, 4) == box2i(1, 2, 4, 6));
    assert(rectanglef(1, 2, 3, 4) == box2f(1, 2, 4, 6));
    assert(rectangled(1, 2, 3, 4) == box2d(1, 2, 4, 6));

    assert(rectangle(10, 10, 20, 20).scaleByFactor(1.5f) == rectangle(15, 15, 30, 30));
    assert(rectangle(10, 10, 20, 20).scaleByFactor(1.5f, 2.0f) == rectangle(15, 20, 30, 40));
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

