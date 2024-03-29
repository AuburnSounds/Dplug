/**
Structure to describe D classes with properties dynamically, to avoid generating Wren code ahead of time. Also saves some D code for properties.

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.wren.describe;

import core.stdc.stdlib: malloc, free;
import dplug.core.vec;

nothrow @nogc:

// For the usage of WrenSupport, describe D classes in a way that can be generated at compile-time. 

/// Note: WrenSupport must be able to generate the module, foreign classes, and foreign methods from this description.
class ScriptExportClass
{
nothrow @nogc:
public:

    this(TypeInfo_Class classInfo)
    {
        _concreteClassInfo = classInfo;

        // build wren identifier
        string fullName = concreteClassInfo.name;
        int LEN = cast(int)fullName.length;

        // try to find rightmost '.'
        string strippedName = fullName;
        for(int n = LEN - 1; n >= 0; --n)
        {
            if (fullName[n] == '.')
            {
                strippedName = fullName[n+1..$];
                break;
            }
        }

        _wrenClassName = convertDStringToCString(strippedName);
    }

    ~this()
    {
        free(_wrenClassName);
    }

    /// The full D identifier of the class, with module identifiers.
    /// eg: dplug.pbkwidgets.knob.UIKnob
    string fullClassName()
    {
        return concreteClassInfo.name;
    }

    /// Its .classinfo
    TypeInfo_Class concreteClassInfo()
    {
        return _concreteClassInfo;
    }

    ScriptPropertyDesc[] properties()
    {
        return _properties[];
    }

    /// The identifier of the class in Wren code. It is stripped from module identifiers.
    /// Zero-terminated.
    /// eg: "UIKnob"
    const(char)* wrenClassNameZ()
    {
        return _wrenClassName;
    }

    void addProperty(ScriptPropertyDesc prop)
    {
        prop.nth = cast(int)_properties.length;
        _properties ~= prop;
    }

private:

    char* _wrenClassName;

    /// Its .classinfo
    TypeInfo_Class _concreteClassInfo; // the D ClassInfo of the D class named by fullClassName()


    Vec!ScriptPropertyDesc _properties;
}

/// All possible types of properties.
enum ScriptPropertyType
{
    bool_,

    byte_,
    ubyte_,
    short_,
    ushort_,
    int_,
    uint_,

    float_,
    double_,

    // Color types from dplug:graphics
    RGBA,
}

struct ScriptPropertyDesc
{
nothrow @nogc:
public:
    // type enumeration
    ScriptPropertyType type;

    /// Byte offset in the class.
    int offset;

    /// Number of the property in the _properties array.
    int nth;

    /// The D identifier of the property.
    /// Not owned, has to be compile-time.
    string identifier;
    
    size_t sizeInInstance()
    {
        return SCRIPT_PROPERTY_SIZES[type];
    }

private:
}


private:

static immutable size_t[ScriptPropertyType.max+1] SCRIPT_PROPERTY_SIZES =
[ 1, 1, 1, 2, 2, 4, 4, 4, 8, 4];


/// Allocated a zero-terminated C string from a D string. A copy is always made, and has to be released with free.
char* convertDStringToCString(const(char)[] cstr) nothrow @nogc
{
    assert(cstr !is null);
    size_t len = cstr.length;
    char* copy = cast(char*) malloc(len + 1);
    copy[0..len] = cstr[0..len];
    copy[len] = '\0';
    return copy;
}