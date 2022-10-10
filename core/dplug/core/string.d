/**
String build code, plus no-locale float parsing functions.

Copyright: Guillaume Piolat, 2022.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/

module dplug.core.string;

import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.stdarg;
import dplug.core.vec;


nothrow @nogc:

/// Create a `String` from a D `string`.
String makeString(const(char)[] s)
{
    return String(s);
}

/// For now, just a string builder that owns its memory.
/// Dplug `String`, designed to ease the usage of all the C string function,
/// allow appending, etc.
/// `String` always owns its memory, and can return as a D slice.
/// FUTURE: use realloc to be able to size down.
///         Capacity to be a slice into existing memory and not own.
///         Capacity to disown memory (implies: stop using Vec)
/// QUESTION: should String just be a managed slice!T instead? Like Go slices.
struct String
{
public:
nothrow @nogc:

    this(char ch)
    {
        this ~= ch;
    }

    this(const(char)[] s)
    {
        this ~= s;
    }

    ~this()
    {
    }

    @disable this(this);

    /// Sets as empty/null string.
    void makeEmpty()
    {
        _chars.clearContents();
    }

    /// Pointer to first character in the string, or `null`.
    inout(char)* ptr() inout return
    {
        return _chars.ptr;
    }

    /// Length in bytes of the string.
    size_t length() const
    {
        return _chars.length;
    }

    /// Converts to a D string, sliced into the `String` memory.
    inout(char)[] asSlice() inout return
    {
        size_t len = length();
        if (len == 0)
            return null;
        return _chars[0..len];
    }

    /// Returns: Whole content of the sring in one slice.
    inout(char)[] opSlice() inout return
    {
        return asSlice();
    }

    /// Returns: A slice of the array.
    inout(char)[] opSlice(size_t i1, size_t i2) inout
    {
        return _chars[i1 .. i2];
    }

    void opAssign(T : char)(T x)
    {
        makeEmpty();
        this ~= x;
    }

    void opAssign(T : const(char)[])(T x)
    {
        makeEmpty();
        this ~= x;
    }

    void opAssign(T : String)(T x)
    {
        makeEmpty();
        this ~= x;
    }

    // <Appending>

    /// Append a character to the string. This invalidates pointers to characters
    /// returned before.
    void opOpAssign(string op)(char x) if (op == "~")
    {
        _chars.pushBack(x);
    }

    /// Append a characters to the string.
    void opOpAssign(string op)(const(char)[] str) if (op == "~")
    {
        size_t len = str.length;
        for (size_t n = 0; n < len; ++n)
            _chars.pushBack(str[n]);
    }

    /// Append a characters to the string.
    void opOpAssign(string op)(ref const(String) str) if (op == "~")
    {
        this ~= str.asSlice();
    }

    /// Append a zero-terminated character to the string.
    /// Name is explicit, because it should be rare and overload conflict.
    void appendZeroTerminatedString(const(char)* str)
    {
        while(*str != '\0')
            _chars.pushBack(*str++);
    }

    bool opEquals(const(char)[] s)
    {
        size_t lenS = s.length;
        size_t lenT = this.length;
        if (lenS != lenT)
            return false;
        for (size_t n = 0; n < lenS; ++n)
        {
            if (s[n] != _chars[n])
                return false;
        }        
        return true;
    }

    bool opEquals(ref const(String) str)
    {
        return this.asSlice() == str.asSlice();
    }

    // </Appending>

private:

    // FUTURE

    /*alias Flags = int;
    enum : Flags
    {
        owned          = 1, /// String data is currently owned (C's malloc/free), not borrowed.
        zeroTerminated = 2, /// String data is currently zero-terminated.
    }

    Flags _flags = 0;
    */

    Vec!char _chars;

    void clearContents()
    {
        _chars.clearContents();
    }
}

// Null and .ptr
unittest
{
    string z;
    string a = "";
    string b = null;

    assert(a == z);
    assert(b == z);
    assert(a == b);
    assert(a !is b);
    assert(a.length == 0);
    assert(b.length == 0);
    assert(a.ptr !is null);

    // Must preserve semantics from D strings.
    String Z = z;
    String A = a;
    String B = b;
    assert(A == Z);
    assert(B == Z);
    assert(A == B);
}

// Basic appending.
unittest
{
    String s = "Hello,";
    s ~= " world!";
    assert(s == "Hello, world!");
    s.makeEmpty();
    assert(s == null);
    assert(s.length == 0);
}

/// strtod replacement, but without locale
///     s Must be a zero-terminated string.
public double strtod_nolocale(const(char)* s, const(char)** p)
{
    bool strtod_err = false;
    const(char)* pend;
    double r = stb__clex_parse_number_literal(s, &pend, &strtod_err);
    if (p) 
        *p = pend;
    if (strtod_err)
        r = 0.0;
    return r;
}
unittest
{
    string[8] sPartial = ["0x123lol", "+0x1.921fb54442d18p+0001()", "0,", "-0.0,,,,", "0.65,stuff", "1.64587okokok", "-1.0e+9HELLO", "1.1454e-25f#STUFF"]; 
    for (int n = 0; n < 8; ++n)
    {
        const(char)* p1, p2;
        double r1 = strtod(sPartial[n].ptr, &p1); // in unittest, no program tampering the C locale
        double r2 = strtod_nolocale(sPartial[n].ptr, &p2);
        //import core.stdc.stdio;
        //debug printf("parsing \"%s\" %lg %lg %p %p\n", sPartial[n].ptr, r1, r2, p1, p2);
        assert(p1 == p2);
    }
}

/// C-locale independent string to float parsing.
/// For when you have the complete delimitation of the string.
/// Params:
///     s Must be a zero-terminated string.
///     mustConsumeEntireInput if true, check that s is entirely consumed by parsing the number.
///     err: optional bool
public double convertStringToDouble(const(char)* s, 
                                    bool mustConsumeEntireInput,
                                    bool* err) pure nothrow @nogc
{
    if (s is null)
    {
        if (err) *err = true;
        return 0.0;
    }

    const(char)* end;
    bool strtod_err = false;
    double r = stb__clex_parse_number_literal(s, &end, &strtod_err);
    
    if (mustConsumeEntireInput)
    {
        size_t len = strlen(s);
        if (end != s + len)
        {
            if (err) *err = true; // did not consume whole string
            return 0.0;
        }
    }

    if (strtod_err)
    {
        if (err) *err = true;
        return 0.0;
    }
    if (err) *err = false;
    return r;
}
 
unittest
{
    //import core.stdc.stdio;
    import std.math.operations;

    string[9] s = ["14", "0x123", "+0x1.921fb54442d18p+0001", "0", "-0.0", "   \n\t\n\f\r 0.65", "1.64587", "-1.0e+9", "1.1454e-25"]; 
    double[9] correct = [14, 0x123, +0x1.921fb54442d18p+0001, 0.0, -0.0, 0.65L, 1.64587, -1e9, 1.1454e-25f];

    string[9] sPartial = ["14top", "0x123lol", "+0x1.921fb54442d18p+0001()", "0,", "-0.0,,,,", "   \n\t\n\f\r 0.65,stuff", "1.64587okokok", "-1.0e+9HELLO", "1.1454e-25f#STUFF"]; 
    for (int n = 0; n < s.length; ++n)
    {
        /*
        // Check vs scanf
        double sa;
        if (sscanf(s[n].ptr, "%lf", &sa) == 1)
        {
            debug printf("scanf finds %lg\n", sa);
        }
        else
            debug printf("scanf no parse\n");
        */

        bool err;
        double a = convertStringToDouble(s[n].ptr, true, &err);
        //import std.stdio;
        //debug writeln(a, " correct is ", correct[n]);
        assert(!err);
        assert( isClose(a, correct[n], 0.0001) );

        bool err2;
        double b = convertStringToDouble(s[n].ptr, false, &err2);
        assert(!err2);
        assert(b == a); // same parse

        //debug printf("%lf\n", a);

        convertStringToDouble(s[n].ptr, true, null); // should run without error pointer
    }
}

private double stb__clex_parse_number_literal(const(char)* p, const(char)**q, bool* err) pure nothrow @nogc
{
    const(char)* s = p;
    double value=0;
    int base=10;
    int exponent=0;
    int signMantissa = 1;

    // Skip leading whitespace, like scanf and strtod do
    while (true)
    {
        char ch = *p;
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '\f' || ch == '\r')
        {
            p += 1;
        }
        else
            break;
    }


    if (*p == '-') 
    {
        signMantissa = -1;
        p += 1;
    } 
    else if (*p == '+') 
    {
        p += 1;
    }

    if (*p == '0') 
    {
        if (p[1] == 'x' || p[1] == 'X') 
        {
            base=16;
            p += 2;
        }
    }

    for (;;) 
    {
        if (*p >= '0' && *p <= '9')
            value = value*base + (*p++ - '0');
        else if (base == 16 && *p >= 'a' && *p <= 'f')
            value = value*base + 10 + (*p++ - 'a');
        else if (base == 16 && *p >= 'A' && *p <= 'F')
            value = value*base + 10 + (*p++ - 'A');
        else
            break;
    }

    if (*p == '.') 
    {
        double pow, addend = 0;
        ++p;
        for (pow=1; ; pow*=base) 
        {
            if (*p >= '0' && *p <= '9')
                addend = addend*base + (*p++ - '0');
            else if (base == 16 && *p >= 'a' && *p <= 'f')
                addend = addend*base + 10 + (*p++ - 'a');
            else if (base == 16 && *p >= 'A' && *p <= 'F')
                addend = addend*base + 10 + (*p++ - 'A');
            else
                break;
        }
        value += addend / pow;
    }
    if (base == 16) {
        // exponent required for hex float literal, else it's an integer literal like 0x123
        exponent = (*p == 'p' || *p == 'P');
    } else
        exponent = (*p == 'e' || *p == 'E');

    if (exponent) 
    {
        int sign = p[1] == '-';
        uint exponent2 = 0;
        double power=1;
        ++p;
        if (*p == '-' || *p == '+')
            ++p;
        while (*p >= '0' && *p <= '9')
            exponent2 = exponent2*10 + (*p++ - '0');

        if (base == 16)
            power = stb__clex_pow(2, exponent2);
        else
            power = stb__clex_pow(10, exponent2);
        if (sign)
            value /= power;
        else
            value *= power;
    }

    if (q) *q = p;
    if (err) *err = false; // seen no error
    if (signMantissa < 0)
        value = -value;
    return value;
}

private double stb__clex_pow(double base, uint exponent) pure nothrow @nogc
{
    double value=1;
    for ( ; exponent; exponent >>= 1) {
        if (exponent & 1)
            value *= base;
        base *= base;
    }
    return value;
}