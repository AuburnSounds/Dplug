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
struct String
{
public:
nothrow @nogc:

    this(const(char)[] s)
    {
        this ~= s;
    }

    ~this()
    {
    }

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


