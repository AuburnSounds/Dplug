module dplug.plugin.params;

import std.math;

import core.stdc.stdio;

class Parameter
{
protected:
    this(string name, string label)
    {
        _name = name;
        _label = label;
    }

public:

    string name() pure const nothrow @nogc
    {
        return _name;
    }

    string label() pure const nothrow @nogc
    {
        return _label;    
    }

    // From a normalized float, set the parameter value.
    abstract void setFromHost(float hostValue) nothrow;

    // Returns: A normalized float, represents the parameter value.
    abstract float getForHost() nothrow;

    // Display parameter (without label)
    abstract void toStringN(char* buffer, size_t numBytes) const nothrow;

private:
    string _name;
    string _label;
}


/// A boolean parameter
class BoolParameter : Parameter
{
public:
    this(string name, bool defaultValue = false)
    {
        super(name, "");
        _value = defaultValue;
    }

    override void setFromHost(float hostValue)
    {
        if (hostValue < 0.5f)
            _value = false;
        else
            _value = true;
    }

    override float getForHost() nothrow
    {
        return _value ? 1.0f : 0.0f;
    }

    override void toStringN(char* buffer, size_t numBytes) const nothrow
    {
        if (_value)
            snprintf(buffer, numBytes, "true");
        else
            snprintf(buffer, numBytes, "false");
    }

    bool get() pure const nothrow @nogc
    {
        return _value;
    }

private:
    bool _value;
}

/// A float parameter
class FloatParameter : Parameter
{
public:
    this(string name, string label, float min = 0.0f, float max = 1.0f, float defaultValue = 0.5f)
    {
        super(name, label);
        _name = name;
        _value = clamp!float(defaultValue, min, max);
        _min = min;
        _max = max;
    }

    override void setFromHost(float hostValue)
    {
        _value = clamp!float(_min + (_max - _min) * hostValue, _min, _max);
    }

    override float getForHost() nothrow
    {
        float normalized = clamp!float( (_value - _min) / (_max - _min), 0.0f, 1.0f);        
        return normalized;
    }

    override void toStringN(char* buffer, size_t numBytes) const nothrow
    {
        snprintf(buffer, numBytes, "%2.2f", _value);
    }

    float get() pure const nothrow @nogc
    {
        return _value;
    }

private:
    float _value;
    float _min;
    float _max;
}

/// An integer parameter
class IntParameter : Parameter
{
public:
    this(string name, string label, int min = 0, int max = 1, int defaultValue = 0)
    {
        super(name, label);
        _name = name;
        _value = clamp!int(defaultValue, min, max);
        _min = min;
        _max = max;
    }

    override void setFromHost(float hostValue)
    {
        int rounded = cast(int)lround( _min + (_max - _min) * hostValue );
        _value = clamp!int(rounded, _min, _max);
    }

    override float getForHost() nothrow
    {
        float normalized = clamp!float( (cast(float)_value - _min) / (_max - _min), 0.0f, 1.0f);        
        return normalized;
    }

    override void toStringN(char* buffer, size_t numBytes) const nothrow
    {
        snprintf(buffer, numBytes, "%d", _value);
    }

    int get() pure const nothrow @nogc
    {
        return _value;
    }

private:
    int _value;
    int _min;
    int _max;
}

private
{
    T clamp(T)(T x, T min, T max) pure nothrow @nogc
    {
        if (x < min)
            return min;
        else if (x > max)
            return max;
        else
            return x;
    }
}