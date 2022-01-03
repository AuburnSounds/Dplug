/**
Structure to describe D classes with properties dynamically, to avoid generating Wren code ahead of time. Also saves some D code for properties.

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.wren.describe;

import dplug.core.vec;

nothrow @nogc:

// For the usage of WrenSupport, describe D classes in a way that can be generated at compile-time. 

/// Note: WrenSupport must be able to generate the module, foreign classes, and foreign methods from this description.
class ScriptExportClass
{
nothrow @nogc:
public:

    /// The D identifier of the class.
    /// Not owned, has to be compile-time.
    string className()
    {
        return classInfo.name;
    }

    /// Its .classinfo
    TypeInfo_Class classInfo;

    void addProperty(ScriptExportProperty prop)
    {
        _properties ~= prop;
    }

private:

    Vec!ScriptExportProperty _properties;

private:
}

/// All possible types of properties.
enum ScriptPropertyType
{
    ubyte_,
    ushort_,
    L16,
    string_,  // what is the ownership of strings when set through wren?
    float_,
    int_,
    bool_,
    RGBA
}


struct ScriptExportProperty
{
nothrow @nogc:
public:
    // type enumeration
    ScriptPropertyType type;

    int offset;

    /// The D identifier of the property.
    /// Not owned, has to be compile-time.
    string name;
    
    size_t sizeInInstance()
    {
        return propertySize(type);
    }

private:
}


private:

size_t propertySize(ScriptPropertyType type)
{
    final switch(type) with (ScriptPropertyType)
    {
        case ubyte_: return 1; 
        case ushort_: return 2;
        case L16: return 2;
        case string_: return (char[]).sizeof; 
        case float_: return 4;
        case int_:  return 4;
        case bool_: return 1;
        case RGBA:  return 4;
    }
}