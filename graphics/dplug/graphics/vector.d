/**
* Copyright: Copyright Auburn Sounds 2016.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.graphics.vector;

import std.traits,
       std.math,
       std.conv,
       std.array,
       std.string;

import dplug.core.math;

/**
 * Generic 1D small vector.
 * Params:
 *    N = number of elements
 *    T = type of elements
 */
struct Vector(T, int N)
{
nothrow:
@nogc:
    public
    {
        static assert(N >= 1);

        // fields definition
        union
        {
            T[N] v;
            struct
            {
                static if (N >= 1)
                {
                    T x;
                    alias x r;
                }
                static if (N >= 2)
                {
                    T y;
                    alias y g;
                }
                static if (N >= 3)
                {
                    T z;
                    alias z b;
                }
                static if (N >= 4)
                {
                    T w;
                    alias w a;
                }
            }
        }

        @nogc this(Args...)(Args args) pure nothrow
        {
            static if (args.length == 1)
            {
                // Construct a Vector from a single value.
                opAssign!(Args[0])(args[0]);
            }
            else
            {
                // validate the total argument count across scalars and vectors
                template argCount(T...) {
                    static if(T.length == 0)
                        enum argCount = 0; // done recursing
                    else static if(isVector!(T[0]))
                        enum argCount = T[0]._N + argCount!(T[1..$]);
                    else
                        enum argCount = 1 + argCount!(T[1..$]);
                }

                static assert(argCount!Args <= N, "Too many arguments in vector constructor");

                int index = 0;
                foreach(arg; args)
                {
                    static if (isAssignable!(T, typeof(arg)))
                    {
                        v[index] = arg;
                        index++; // has to be on its own line (DMD 2.068)
                    }
                    else static if (isVector!(typeof(arg)) && isAssignable!(T, arg._T))
                    {
                        mixin(generateLoopCode!("v[index + @] = arg[@];", arg._N)());
                        index += arg._N;
                    }
                    else
                        static assert(false, "Unrecognized argument in Vector constructor");
                }
                assert(index == N, "Bad arguments in Vector constructor");
            }
        }

        /// Assign a Vector from a compatible type.
        @nogc ref Vector opAssign(U)(U x) pure nothrow if (isAssignable!(T, U))
        {
            mixin(generateLoopCode!("v[@] = x;", N)()); // copy to each component
            return this;
        }

        /// Assign a Vector with a static array type.
        @nogc ref Vector opAssign(U)(U arr) pure nothrow if ((isStaticArray!(U) && isAssignable!(T, typeof(arr[0])) && (arr.length == N)))
        {
            mixin(generateLoopCode!("v[@] = arr[@];", N)());
            return this;
        }

        /// Assign with a dynamic array.
        /// Size is checked in debug-mode.
        @nogc ref Vector opAssign(U)(U arr) pure nothrow if (isDynamicArray!(U) && isAssignable!(T, typeof(arr[0])))
        {
            assert(arr.length == N);
            mixin(generateLoopCode!("v[@] = arr[@];", N)());
            return this;
        }

        /// Assign from a samey Vector.
        @nogc ref Vector opAssign(U)(U u) pure nothrow if (is(U : Vector))
        {
            v[] = u.v[];
            return this;
        }

        /// Assign from other vectors types (same size, compatible type).
        @nogc ref Vector opAssign(U)(U x) pure nothrow if (isVector!U
                                                       && isAssignable!(T, U._T)
                                                       && (!is(U: Vector))
                                                       && (U._N == _N))
        {
            mixin(generateLoopCode!("v[@] = x.v[@];", N)());
            return this;
        }

        /// Returns: a pointer to content.
        @nogc inout(T)* ptr() pure inout nothrow @property
        {
            return v.ptr;
        }

        @nogc bool opEquals(U)(U other) pure const nothrow
            if (is(U : Vector))
        {
            for (int i = 0; i < N; ++i)
            {
                if (v[i] != other.v[i])
                {
                    return false;
                }
            }
            return true;
        }

        @nogc bool opEquals(U)(U other) pure const nothrow
            if (isConvertible!U)
        {
            Vector conv = other;
            return opEquals(conv);
        }

        @nogc Vector opUnary(string op)() pure const nothrow
            if (op == "+" || op == "-" || op == "~" || op == "!")
        {
            Vector res = void;
            mixin(generateLoopCode!("res.v[@] = " ~ op ~ " v[@];", N)());
            return res;
        }

        @nogc ref Vector opOpAssign(string op, U)(U operand) pure nothrow
            if (is(U : Vector))
        {
            mixin(generateLoopCode!("v[@] " ~ op ~ "= operand.v[@];", N)());
            return this;
        }

        @nogc ref Vector opOpAssign(string op, U)(U operand) pure nothrow if (isConvertible!U)
        {
            Vector conv = operand;
            return opOpAssign!op(conv);
        }

        @nogc Vector opBinary(string op, U)(U operand) pure const nothrow
            if (is(U: Vector) || (isConvertible!U))
        {
            Vector result = void;
            static if (is(U: T))
                mixin(generateLoopCode!("result.v[@] = cast(T)(v[@] " ~ op ~ " operand);", N)());
            else
            {
                Vector other = operand;
                mixin(generateLoopCode!("result.v[@] = cast(T)(v[@] " ~ op ~ " other.v[@]);", N)());
            }
            return result;
        }

        @nogc Vector opBinaryRight(string op, U)(U operand) pure const nothrow if (isConvertible!U)
        {
            Vector result = void;
            static if (is(U: T))
                mixin(generateLoopCode!("result.v[@] = cast(T)(operand " ~ op ~ " v[@]);", N)());
            else
            {
                Vector other = operand;
                mixin(generateLoopCode!("result.v[@] = cast(T)(other.v[@] " ~ op ~ " v[@]);", N)());
            }
            return result;
        }

        @nogc ref T opIndex(size_t i) pure nothrow
        {
            return v[i];
        }

        @nogc ref const(T) opIndex(size_t i) pure const nothrow
        {
            return v[i];
        }

        @nogc T opIndexAssign(U : T)(U x, size_t i) pure nothrow
        {
            return v[i] = x;
        }


        /// Implements swizzling.
        ///
        /// Example:
        /// ---
        /// vec4i vi = [4, 1, 83, 10];
        /// assert(vi.zxxyw == [83, 4, 4, 1, 10]);
        /// ---
        @nogc @property auto opDispatch(string op, U = void)() pure const nothrow if (isValidSwizzle!(op))
        {
            alias Vector!(T, op.length) returnType;
            returnType res = void;
            enum indexTuple = swizzleTuple!op;
            foreach(i, index; indexTuple)
                res.v[i] = v[index];
            return res;
        }

        /// Support swizzling assignment like in shader languages.
        ///
        /// Example:
        /// ---
        /// vec3f v = [0, 1, 2];
        /// v.yz = v.zx;
        /// assert(v == [0, 2, 0]);
        /// ---
        @nogc @property void opDispatch(string op, U)(U x) pure
            if ((op.length >= 2)
                && (isValidSwizzleUnique!op)                   // v.xyy will be rejected
                && is(typeof(Vector!(T, op.length)(x)))) // can be converted to a small vector of the right size
        {
            Vector!(T, op.length) conv = x;
            enum indexTuple = swizzleTuple!op;
            foreach(i, index; indexTuple)
                v[index] = conv[i];
        }

        /// Casting to small vectors of the same size.
        /// Example:
        /// ---
        /// vec4f vf;
        /// vec4d vd = cast!(vec4d)vf;
        /// ---
        @nogc U opCast(U)() pure const nothrow if (isVector!U && (U._N == _N))
        {
            U res = void;
            mixin(generateLoopCode!("res.v[@] = cast(U._T)v[@];", N)());
            return res;
        }

        /// Implement slices operator overloading.
        /// Allows to go back to slice world.
        /// Returns: length.
        @nogc int opDollar() pure const nothrow
        {
            return N;
        }

        /// Returns: a slice which covers the whole Vector.
        @nogc T[] opSlice() pure nothrow
        {
            return v[];
        }

        // vec[a..b]
        @nogc T[] opSlice(int a, int b) pure nothrow
        {
            return v[a..b];
        }

        /// Returns: squared length.
        @nogc T squaredLength() pure const nothrow
        {
            T sumSquares = 0;
            mixin(generateLoopCode!("sumSquares += v[@] * v[@];", N)());
            return sumSquares;
        }

        // Returns: squared Euclidean distance.
        @nogc T squaredDistanceTo(Vector v) pure const nothrow
        {
            return (v - this).squaredLength();
        }

        static if (isFloatingPoint!T)
        {
            /// Returns: Euclidean length
            @nogc T length() pure const nothrow
            {
                return sqrt(squaredLength());
            }

            /// Returns: Inverse of Euclidean length.
            @nogc T inverseLength() pure const nothrow
            {
                return 1 / sqrt(squaredLength());
            }

            /// Faster but less accurate inverse of Euclidean length.
            /// Returns: Inverse of Euclidean length.
            @nogc T fastInverseLength() pure const nothrow
            {
                return inverseSqrt!T(squaredLength());
            }

            /// Returns: Euclidean distance between this and other.
            @nogc T distanceTo(Vector other) pure const nothrow
            {
                return (other - this).length();
            }

            /// In-place normalization.
            @nogc void normalize() pure nothrow
            {
                auto invLength = inverseLength();
                mixin(generateLoopCode!("v[@] *= invLength;", N)());
            }

            /// Returns: Normalized vector.
            @nogc Vector normalized() pure const nothrow
            {
                Vector res = this;
                res.normalize();
                return res;
            }

            /// Faster but less accurate in-place normalization.
            @nogc void fastNormalize() pure nothrow
            {
                auto invLength = fastInverseLength();
                mixin(generateLoopCode!("v[@] *= invLength;", N)());
            }

            /// Faster but less accurate vector normalization.
            /// Returns: Normalized vector.
            @nogc Vector fastNormalized() pure const nothrow
            {
                Vector res = this;
                res.fastNormalize();
                return res;
            }

            static if (N == 3)
            {
                /// Gets an orthogonal vector from a 3-dimensional vector.
                /// Doesn’t normalize the output.
                /// Authors: Sam Hocevar
                /// See_also: Source at $(WEB lolengine.net/blog/2013/09/21/picking-orthogonal-vector-combing-coconuts).
                @nogc Vector getOrthogonalVector() pure const nothrow
                {
                    return abs(x) > abs(z) ? Vector(-y, x, 0.0) : Vector(0.0, -z, y);
                }
            }
        }
    }

    private
    {
        enum _N = N;
        alias T _T;

        // define types that can be converted to this, but are not the same type
        template isConvertible(T)
        {
            enum bool isConvertible = (!is(T : Vector))
            && is(typeof(
                {
                    T x;
                    Vector v = x;
                }()));
        }

        // define types that can't be converted to this
        template isForeign(T)
        {
            enum bool isForeign = (!isConvertible!T) && (!is(T: Vector));
        }

        template isValidSwizzle(string op, int lastSwizzleClass = -1)
        {
            static if (op.length == 0)
                enum bool isValidSwizzle = true;
            else
            {
                enum len = op.length;
                enum int swizzleClass = swizzleClassify!(op[0]);
                enum bool swizzleClassValid = (lastSwizzleClass == -1 || (swizzleClass == lastSwizzleClass));
                enum bool isValidSwizzle = (swizzleIndex!(op[0]) != -1)
                                         && swizzleClassValid
                                         && isValidSwizzle!(op[1..len], swizzleClass);
            }
        }

        template searchElement(char c, string s)
        {
            static if (s.length == 0)
            {
                enum bool result = false;
            }
            else
            {
                enum string tail = s[1..s.length];
                enum bool result = (s[0] == c) || searchElement!(c, tail).result;
            }
        }

        template hasNoDuplicates(string s)
        {
            static if (s.length == 1)
            {
                enum bool result = true;
            }
            else
            {
                enum tail = s[1..s.length];
                enum bool result = !(searchElement!(s[0], tail).result) && hasNoDuplicates!(tail).result;
            }
        }

        // true if the swizzle has at the maximum one time each letter
        template isValidSwizzleUnique(string op)
        {
            static if (isValidSwizzle!op)
                enum isValidSwizzleUnique = hasNoDuplicates!op.result;
            else
                enum bool isValidSwizzleUnique = false;
        }

        template swizzleIndex(char c)
        {
            static if((c == 'x' || c == 'r') && N >= 1)
                enum swizzleIndex = 0;
            else static if((c == 'y' || c == 'g') && N >= 2)
                enum swizzleIndex = 1;
            else static if((c == 'z' || c == 'b') && N >= 3)
                enum swizzleIndex = 2;
            else static if ((c == 'w' || c == 'a') && N >= 4)
                enum swizzleIndex = 3;
            else
                enum swizzleIndex = -1;
        }

        template swizzleClassify(char c)
        {
            static if(c == 'x' || c == 'y' || c == 'z' || c == 'w')
                enum swizzleClassify = 0;
            else static if(c == 'r' || c == 'g' || c == 'b' || c == 'a')
                enum swizzleClassify = 1;
            else
                enum swizzleClassify = -1;
        }

        template swizzleTuple(string op)
        {
            enum opLength = op.length;
            static if (op.length == 0)
                enum swizzleTuple = [];
            else
                enum swizzleTuple = [ swizzleIndex!(op[0]) ] ~ swizzleTuple!(op[1..op.length]);
        }
    }
}

/// True if `T` is some kind of `Vector`
enum isVector(T) = is(T : Vector!U, U...);

///
unittest
{
    static assert(isVector!vec2f);
    static assert(isVector!vec3d);
    static assert(isVector!(vec4!real));
    static assert(!isVector!float);
}

/// Get the numeric type used to measure a vectors's coordinates.
alias DimensionType(T : Vector!U, U...) = U[0];

///
unittest
{
    static assert(is(DimensionType!vec2f == float));
    static assert(is(DimensionType!vec3d == double));
}

template vec2(T) { alias Vector!(T, 2) vec2; }
template vec3(T) { alias Vector!(T, 3) vec3; }
template vec4(T) { alias Vector!(T, 4) vec4; }

alias vec2!byte   vec2b;
alias vec2!ubyte  vec2ub;
alias vec2!short  vec2s;
alias vec2!ushort vec2us;
alias vec2!int    vec2i;
alias vec2!uint   vec2ui;
alias vec2!long   vec2l;
alias vec2!ulong  vec2ul;
alias vec2!float  vec2f;
alias vec2!double vec2d;

alias vec3!byte   vec3b;
alias vec3!ubyte  vec3ub;
alias vec3!short  vec3s;
alias vec3!ushort vec3us;
alias vec3!int    vec3i;
alias vec3!uint   vec3ui;
alias vec3!long   vec3l;
alias vec3!ulong  vec3ul;
alias vec3!float  vec3f;
alias vec3!double vec3d;

alias vec4!byte   vec4b;
alias vec4!ubyte  vec4ub;
alias vec4!short  vec4s;
alias vec4!ushort vec4us;
alias vec4!int    vec4i;
alias vec4!uint   vec4ui;
alias vec4!long   vec4l;
alias vec4!ulong  vec4ul;
alias vec4!float  vec4f;
alias vec4!double vec4d;

private
{
    static string generateLoopCode(string formatString, int N)() pure nothrow
    {
        string result;
        for (int i = 0; i < N; ++i)
        {
            string index = ctIntToString(i);
            // replace all @ by indices
            result ~= formatString.replace("@", index);
        }
        return result;
    }

    // Speed-up CTFE conversions
    static string ctIntToString(int n) pure nothrow
    {
        static immutable string[16] table = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];
        if (n < 10)
            return table[n];
        else
            return to!string(n);
    }
}


/// Element-wise minimum.
@nogc Vector!(T, N) minByElem(T, int N)(const Vector!(T, N) a, const Vector!(T, N) b) pure nothrow
{
    import std.algorithm.comparison: min;
    Vector!(T, N) res = void;
    mixin(generateLoopCode!("res.v[@] = min(a.v[@], b.v[@]);", N)());
    return res;
}

/// Element-wise maximum.
@nogc Vector!(T, N) maxByElem(T, int N)(const Vector!(T, N) a, const Vector!(T, N) b) pure nothrow
{
    import std.algorithm.comparison: max;
    Vector!(T, N) res = void;
    mixin(generateLoopCode!("res.v[@] = max(a.v[@], b.v[@]);", N)());
    return res;
}

/// Returns: Dot product.
@nogc T dot(T, int N)(const Vector!(T, N) a, const Vector!(T, N) b) pure nothrow
{
    T sum = 0;
    mixin(generateLoopCode!("sum += a.v[@] * b.v[@];", N)());
    return sum;
}

/// Returns: 3D cross product.
/// Thanks to vuaru for corrections.
@nogc Vector!(T, 3) cross(T)(const Vector!(T, 3) a, const Vector!(T, 3) b) pure nothrow
{
    return Vector!(T, 3)(a.y * b.z - a.z * b.y,
                         a.z * b.x - a.x * b.z,
                         a.x * b.y - a.y * b.x);
}

/// 3D reflect, like the GLSL function.
/// Returns: a reflected by normal b.
@nogc Vector!(T, N) reflect(T, int N)(const Vector!(T, N) a, const Vector!(T, N) b) pure nothrow
{
    return a - (2 * dot(b, a)) * b;
}

///
@nogc unittest
{
    // reflect a 2D vector across the x axis (the normal points along the y axis)
    assert(vec2f(1,1).reflect(vec2f(0,1)) == vec2f(1,-1));
    assert(vec2f(1,1).reflect(vec2f(0,-1)) == vec2f(1,-1));

    // note that the normal must be, well, normalized:
    assert(vec2f(1,1).reflect(vec2f(0,20)) != vec2f(1,-1));

    // think of this like a ball hitting a flat floor at an angle.
    // the x and y components remain unchanged, and the z inverts
    assert(vec3f(2,3,-0.5).reflect(vec3f(0,0,1)) == vec3f(2,3,0.5));
}

/// Returns: angle between vectors.
/// See_also: "The Right Way to Calculate Stuff" at $(WEB www.plunk.org/~hatch/rightway.php)
@nogc T angleBetween(T, int N)(const Vector!(T, N) a, const Vector!(T, N) b) pure nothrow
{
    auto aN = a.normalized();
    auto bN = b.normalized();
    auto dp = dot(aN, bN);

    if (dp < 0)
        return PI - 2 * asin((-bN-aN).length / 2);
    else
        return 2 * asin((bN-aN).length / 2);
}

static assert(vec2f.sizeof == 8);
static assert(vec3d.sizeof == 24);
static assert(vec4i.sizeof == 16);


unittest
{
    static assert(vec2i.isValidSwizzle!"xyx");
    static assert(!vec2i.isValidSwizzle!"xyz");
    static assert(vec4i.isValidSwizzle!"brra");
    static assert(!vec4i.isValidSwizzle!"rgyz");
    static assert(vec2i.isValidSwizzleUnique!"xy");
    static assert(vec2i.isValidSwizzleUnique!"yx");
    static assert(!vec2i.isValidSwizzleUnique!"xx");

    assert(vec2l(0, 1) == vec2i(0, 1));

    int[2] arr = [0, 1];
    int[] arr2 = new int[2];
    arr2[] = arr[];
    vec2i a = vec2i([0, 1]);
    vec2i a2 = vec2i(0, 1);
    immutable vec2i b = vec2i(0);
    assert(b[0] == 0 && b[1] == 0);
    vec2i c = arr;
    vec2l d = arr2;
    assert(a == a2);
    assert(a == c);
    assert(vec2l(a) == vec2l(a));
    assert(vec2l(a) == d);

    vec4i x = [4, 5, 6, 7];
    assert(x == x);
    --x[0];
    assert(x[0] == 3);
    ++x[0];
    assert(x[0] == 4);
    x[1] &= 1;
    x[2] = 77 + x[2];
    x[3] += 3;
    assert(x == [4, 1, 83, 10]);
    assert(x.xxywz == [4, 4, 1, 10, 83]);
    assert(x.xxxxxxx == [4, 4, 4, 4, 4, 4, 4]);
    assert(x.abgr == [10, 83, 1, 4]);
    assert(a != b);
    x = vec4i(x.xyz, 166);
    assert(x == [4, 1, 83, 166]);

    vec2l e = a;
    vec2l f = a + b;
    assert(f == vec2l(a));

    vec3ui g = vec3i(78,9,4);
    g ^= vec3i(78,9,4);
    assert(g == vec3ui(0));
    //g[0..2] = 1u;
    //assert(g == [2, 1, 0]);

    assert(vec2i(4, 5) + 1 == vec2i(5,6));
    assert(vec2i(4, 5) - 1 == vec2i(3,4));
    assert(1 + vec2i(4, 5) == vec2i(5,6));
    assert(vec3f(1,1,1) * 0 == 0);
    assert(1.0 * vec3d(4,5,6) == vec3f(4,5.0f,6.0));

    auto dx = vec2i(1,2);
    auto dy = vec2i(4,5);
    auto dp = dot(dx, dy);
    assert(dp == 14 );

    vec3i h = cast(vec3i)(vec3d(0.5, 1.1, -2.2));
    assert(h == [0, 1, -2]);
    assert(h[] == [0, 1, -2]);
    assert(h[1..3] == [1, -2]);
    assert(h.zyx == [-2, 1, 0]);

    h.yx = vec2i(5, 2); // swizzle assignment

    assert(h.xy == [2, 5]);
    assert(-h[1] == -5);
    assert(++h[0] == 3);

    //assert(h == [-2, 1, 0]);
    assert(!__traits(compiles, h.xx = h.yy));
    vec4ub j;

    assert(lerp(vec2f(-10, -1), vec2f(10, 1), 0.5) == vec2f(0, 0));

    // larger vectors
    alias Vector!(float, 5) vec5f;
    vec5f l = vec5f(1, 2.0f, 3.0, 4u, 5.0L);
    l = vec5f(l.xyz, vec2i(1, 2));

    // the ctor should not compile if given too many arguments
    static assert(!is(typeof(vec2f(1, 2, 3))));
    static assert(!is(typeof(vec2f(vec2f(1, 2), 3))));
    static assert( is(typeof(vec3f(vec2f(1, 2), 3))));
    static assert( is(typeof(vec3f(1, 2, 3))));
}

