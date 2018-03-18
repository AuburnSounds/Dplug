/**
 * Color type and operations. Port of ae.utils.graphics.
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 *   Guillaume Piolat <contact@auburnsounds.com>
 */

module dplug.graphics.color;

import std.traits;
import std.math;
import std.algorithm : min, max, swap;

import dplug.core.math;


/// Evaluates to array of strings with name for each field.
@property string[] structFields(T)()
if (is(T == struct) || is(T == class))
{
	import std.string : split;

	string[] fields;
	foreach (i, f; T.init.tupleof)
	{
		string field = T.tupleof[i].stringof;
		field = field.split(".")[$-1];
		fields ~= field;
	}
	return fields;
}


T itpl(T, U)(T low, T high, U r, U rLow, U rHigh)
{
	return cast(T)(low + (cast(Signed!T)high-cast(Signed!T)low) * (cast(Signed!U)r - cast(Signed!U)rLow) / (cast(Signed!U)rHigh - cast(Signed!U)rLow));
}

auto sqr(T)(T x) { return x*x; }


void sort2(T)(ref T x, ref T y)
{
    if (x > y)
    {
        T z = x;
        x = y;
        y = z;
    }
}

byte sign(T)(T x)
{
    return x<0 ? -1 : (x>0 ? 1 : 0);
}

/// Integer log2.
private ubyte ilog2(T)(T n)
{
	ubyte result = 0;
	while (n >>= 1)
		result++;
	return result;
}

private T nextPowerOfTwo(T)(T x)
{
	x |= x >>  1;
	x |= x >>  2;
	x |= x >>  4;
	static if (T.sizeof > 1)
		x |= x >>  8;
	static if (T.sizeof > 2)
		x |= x >> 16;
	static if (T.sizeof > 4)
		x |= x >> 32;
	return x + 1;
}

/// Like std.typecons.Tuple, but a template mixin.
/// Unlike std.typecons.Tuple, names may not be omitted - but repeating types may be.
/// Example: FieldList!(ubyte, "r", "g", "b", ushort, "a");
mixin template FieldList(Fields...)
{
	mixin(GenFieldList!(void, Fields));
}

template GenFieldList(T, Fields...)
{
	static if (Fields.length == 0)
		enum GenFieldList = "";
	else
	{
		static if (is(typeof(Fields[0]) == string))
			enum GenFieldList = T.stringof ~ " " ~ Fields[0] ~ ";\n" ~ GenFieldList!(T, Fields[1..$]);
		else
			enum GenFieldList = GenFieldList!(Fields[0], Fields[1..$]);
	}
}

unittest
{
	struct S
	{
		mixin FieldList!(ubyte, "r", "g", "b", ushort, "a");
	}
	S s;
	static assert(is(typeof(s.r) == ubyte));
	static assert(is(typeof(s.g) == ubyte));
	static assert(is(typeof(s.b) == ubyte));
	static assert(is(typeof(s.a) == ushort));
}


/// Return the number of bits used to store the value part, i.e.
/// T.sizeof*8 for integer parts and the mantissa size for
/// floating-point types.
template valueBits(T)
{
	static if (is(T : ulong))
		enum valueBits = T.sizeof * 8;
	else
        static if (is(T : real))
            enum valueBits = T.mant_dig;
        else
            static assert(false, "Don't know how many value bits there are in " ~ T.stringof);
}

static assert(valueBits!uint == 32);
static assert(valueBits!double == 53);



/// Instantiates to a color type.
/// FieldTuple is the color specifier, as parsed by
/// the FieldList template from ae.utils.meta.
/// By convention, each field's name indicates its purpose:
/// - x: padding
/// - a: alpha
/// - l: lightness (or grey, for monochrome images)
/// - others (r, g, b, etc.): color information

// MAYDO: figure out if we need all these methods in the color type itself
//   - code such as gamma conversion needs to create color types
//   - ReplaceType can't copy methods
//   - even if we move out all conventional methods, that still leaves operator overloading

struct Color(FieldTuple...)
{
	alias Spec = FieldTuple;
	mixin FieldList!FieldTuple;

	// A "dumb" type to avoid cyclic references.
	private struct Fields { mixin FieldList!FieldTuple; }

	/// Whether or not all channel fields have the same base type.
	// Only "true" supported for now, may change in the future (e.g. for 5:6:5)
	enum homogenous = true;

	/// The number of fields in this color type.
	enum channels = Fields.init.tupleof.length;

	static if (homogenous)
	{
		alias ChannelType = typeof(Fields.init.tupleof[0]);
		enum channelBits = valueBits!ChannelType;
	}

	/// Return a Color instance with all fields set to "value".
	static typeof(this) monochrome(ChannelType value)
	{
		typeof(this) r;
		foreach (i, f; r.tupleof)
			r.tupleof[i] = value;
		return r;
	}

	/// Interpolate between two colors.
	static typeof(this) itpl(P)(typeof(this) c0, typeof(this) c1, P p, P p0, P p1)
	{
		alias ExpandNumericType!(ChannelType, P.sizeof*8) U;
		alias Signed!U S;
		typeof(this) r;
		foreach (i, f; r.tupleof)
			static if (r.tupleof[i].stringof != "r.x") // skip padding
				r.tupleof[i] = cast(ChannelType).itpl(cast(U)c0.tupleof[i], cast(U)c1.tupleof[i], cast(S)p, cast(S)p0, cast(S)p1);
		return r;
	}

	/// Alpha-blend two colors.
	static typeof(this) blend()(typeof(this) c0, typeof(this) c1)
		if (is(typeof(a)))
	{
		alias A = typeof(c0.a);
		A a = ~cast(A)(~c0.a * ~c1.a / A.max);
		if (!a)
			return typeof(this).init;
		A x = cast(A)(c1.a * A.max / a);

		typeof(this) r;
		foreach (i, f; r.tupleof)
			static if (r.tupleof[i].stringof == "r.x")
				{} // skip padding
			else
			static if (r.tupleof[i].stringof == "r.a")
				r.a = a;
			else
			{
				auto v0 = c0.tupleof[i];
				auto v1 = c1.tupleof[i];
				auto vr = .blend(v1, v0, x);
				r.tupleof[i] = vr;
			}
		return r;
	}

	/// Construct an RGB color from a typical hex string.
	static if (is(typeof(this.r) == ubyte) && is(typeof(this.g) == ubyte) && is(typeof(this.b) == ubyte))
	{
		static typeof(this) fromHex(in char[] s)
		{
			import std.conv;
			import std.exception;

			enforce(s.length == 6, "Invalid color string");
			typeof(this) c;
			c.r = s[0..2].to!ubyte(16);
			c.g = s[2..4].to!ubyte(16);
			c.b = s[4..6].to!ubyte(16);
			return c;
		}

		string toHex() const
		{
			import std.string;
			return format("%02X%02X%02X", r, g, b);
		}
	}

	/// Warning: overloaded operators preserve types and may cause overflows
	typeof(this) opUnary(string op)()
		if (op=="~" || op=="-")
	{
		typeof(this) r;
		foreach (i, f; r.tupleof)
			static if(r.tupleof[i].stringof != "r.x") // skip padding
				r.tupleof[i] = cast(typeof(r.tupleof[i])) mixin(op ~ `this.tupleof[i]`);
		return r;
	}

	/// ditto
	typeof(this) opOpAssign(string op)(int o)
	{
		foreach (i, f; this.tupleof)
			static if(this.tupleof[i].stringof != "this.x") // skip padding
				this.tupleof[i] = cast(typeof(this.tupleof[i])) mixin(`this.tupleof[i]` ~ op ~ `=o`);
		return this;
	}

	/// ditto
	typeof(this) opOpAssign(string op, T)(T o)
		if (is(T==struct) && structFields!T == structFields!Fields)
	{
		foreach (i, f; this.tupleof)
			static if(this.tupleof[i].stringof != "this.x") // skip padding
				this.tupleof[i] = cast(typeof(this.tupleof[i])) mixin(`this.tupleof[i]` ~ op ~ `=o.tupleof[i]`);
		return this;
	}

	/// ditto
	typeof(this) opBinary(string op, T)(T o)
		if (op != "~")
	{
		auto r = this;
		mixin("r" ~ op ~ "=o;");
		return r;
	}

	/// Apply a custom operation for each channel. Example:
	/// COLOR.op!q{(a + b) / 2}(colorA, colorB);
	static typeof(this) op(string expr, T...)(T values)
	{
		static assert(values.length <= 10);

		string genVars(string channel)
		{
			string result;
			foreach (j, Tj; T)
			{
				static if (is(Tj == struct)) // TODO: tighter constraint (same color channels)?
					result ~= "auto " ~ cast(char)('a' + j) ~ " = values[" ~ cast(char)('0' + j) ~ "]." ~  channel ~ ";\n";
				else
					result ~= "auto " ~ cast(char)('a' + j) ~ " = values[" ~ cast(char)('0' + j) ~ "];\n";
			}
			return result;
		}

		typeof(this) r;
		foreach (i, f; r.tupleof)
			static if(r.tupleof[i].stringof != "r.x") // skip padding
			{
				mixin(genVars(r.tupleof[i].stringof[2..$]));
				r.tupleof[i] = mixin(expr);
			}
		return r;
	}

	T opCast(T)()
		if (is(T==struct) && structFields!T == structFields!Fields)
	{
		T t;
		foreach (i, f; this.tupleof)
			t.tupleof[i] = cast(typeof(t.tupleof[i])) this.tupleof[i];
		return t;
	}

	/// Sum of all channels
	ExpandIntegerType!(ChannelType, ilog2(nextPowerOfTwo(channels))) sum()
	{
		typeof(return) result;
		foreach (i, f; this.tupleof)
			static if (this.tupleof[i].stringof != "this.x") // skip padding
				result += this.tupleof[i];
		return result;
	}
}

// The "x" has the special meaning of "padding" and is ignored in some circumstances
alias Color!(ubyte  , "r", "g", "b"     ) RGB    ;
alias Color!(ubyte  , "r", "g", "b", "a") RGBA   ;


alias Color!(ubyte  , "l"               ) L8     ;
alias Color!(ushort , "l"               ) L16    ;



unittest
{
	static assert(RGB.sizeof == 3);
	RGB[2] arr;
	static assert(arr.sizeof == 6);

	RGB hex = RGB.fromHex("123456");
	assert(hex.r == 0x12 && hex.g == 0x34 && hex.b == 0x56);

	assert(RGB(1, 2, 3) + RGB(4, 5, 6) == RGB(5, 7, 9));

	RGB c = RGB(1, 1, 1);
	c += 1;
	assert(c == RGB(2, 2, 2));
	c += c;
	assert(c == RGB(4, 4, 4));
}

unittest
{
	import std.conv;

	L8 r;

	r = L8.itpl(L8(100), L8(200), 15, 10, 20);
	assert(r ==  L8(150), text(r));
}


unittest
{
	Color!(real, "r", "g", "b") c;
}

/// Obtains the type of each channel for homogenous colors.
template ChannelType(T)
{
	static if (is(T == struct))
		alias ChannelType = T.ChannelType;
	else
		alias ChannelType = T;
}

/// Resolves to a Color instance with a different ChannelType.
template ChangeChannelType(COLOR, T)
	if (isNumeric!COLOR)
{
	alias ChangeChannelType = T;
}

/// ditto
template ChangeChannelType(COLOR, T)
	if (is(COLOR : Color!Spec, Spec...))
{
	static assert(COLOR.homogenous, "Can't change ChannelType of non-homogenous Color");
	alias ChangeChannelType = Color!(T, COLOR.Spec[1..$]);
}

static assert(is(ChangeChannelType!(int, ushort) == ushort));


/// Expand to a built-in numeric type of the same kind
/// (signed integer / unsigned integer / floating-point)
/// with at least the indicated number of bits of precision.
template ResizeNumericType(T, uint bits)
{
	static if (is(T : ulong))
		static if (isSigned!T)
			alias ResizeNumericType = SignedBitsType!bits;
		else
			alias ResizeNumericType = UnsignedBitsType!bits;
	else
        static if (is(T : real))
        {
            static if (bits <= float.mant_dig)
                alias ResizeNumericType = float;
            else
                static if (bits <= double.mant_dig)
                    alias ResizeNumericType = double;
                else
                    static if (bits <= real.mant_dig)
                        alias ResizeNumericType = real;
                    else
                        static assert(0, "No floating-point type big enough to fit " ~ bits.stringof ~ " bits");
        }
        else
            static assert(false, "Don't know how to resize type: " ~ T.stringof);
}

static assert(is(ResizeNumericType!(float, double.mant_dig) == double));

/// Expand to a built-in numeric type of the same kind
/// (signed integer / unsigned integer / floating-point)
/// with at least additionalBits more bits of precision.
alias ExpandNumericType(T, uint additionalBits) =
    ResizeNumericType!(T, valueBits!T + additionalBits);

/// Unsigned integer type big enough to fit N bits of precision.
template UnsignedBitsType(uint bits)
{
	static if (bits <= 8)
		alias ubyte UnsignedBitsType;
	else
        static if (bits <= 16)
            alias ushort UnsignedBitsType;
        else
            static if (bits <= 32)
                alias uint UnsignedBitsType;
            else
                static if (bits <= 64)
                    alias ulong UnsignedBitsType;
                else
                    static assert(0, "No integer type big enough to fit " ~ bits.stringof ~ " bits");
}

template SignedBitsType(uint bits)
{
	alias Signed!(UnsignedBitsType!bits) SignedBitsType;
}


/// Wrapper around ExpandNumericType to only expand numeric types.
template ExpandIntegerType(T, size_t bits)
{
	static if (is(T:real))
		alias ExpandIntegerType = T;
	else
		alias ExpandIntegerType = ExpandNumericType!(T, bits);
}

alias ExpandChannelType(COLOR, int BYTES) =
	ChangeChannelType!(COLOR,
		ExpandNumericType!(ChannelType!COLOR, BYTES * 8));

alias temp = ExpandChannelType!(RGB, 1);
//static assert(is(ExpandChannelType!(RGB, 1) == RGB16));

unittest
{
	alias RGBf = ChangeChannelType!(RGB, float);
	auto rgb = RGB(1, 2, 3);
	import std.conv : to;
	auto rgbf = rgb.to!RGBf();
	assert(rgbf.r == 1f);
	assert(rgbf.g == 2f);
	assert(rgbf.b == 3f);
}

// ***************************************************************************

T blend(T)(T f, T b, T a) pure nothrow @nogc
    if (is(typeof(f*a+~b)))
{
    return cast(T) ( ((f*a) + (b*(~cast(int)a))) / T.max );
}
