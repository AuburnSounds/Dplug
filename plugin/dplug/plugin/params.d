module dplug.plugin.params;

import std.math;

import core.stdc.stdio;

import dplug.plugin.client;
import dplug.plugin.spinlock;

class Parameter
{
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
    void setFromHost(float hostValue) nothrow
    {
        _valueSpinlock.lock();
        scope(exit) _valueSpinlock.unlock();
        setNormalized(hostValue);
    }

    // Returns: A normalized float, represents the parameter value.
    float getForHost() nothrow
    {
        _valueSpinlock.lock();
        scope(exit) _valueSpinlock.unlock();
        return getNormalized();
    }

    void toDisplayN(char* buffer, size_t numBytes) nothrow
    {
        _valueSpinlock.lock();
        scope(exit) _valueSpinlock.unlock();
        toStringN(buffer, numBytes);
    }

protected:

    this(Client client, int index, string name, string label)
    {
        _client = client;
        _name = name;
        _label = label;
        _index = index;

        _valueSpinlock = Spinlock(false);
    }

    ~this()
    {
        close();
    }

    void close()
    {
        _valueSpinlock.close();
    }

    /// From a normalized float, set the parameter value.
    /// No guarantee at all that getNormalized will return the same,
    /// because this value is rounded to fit.
    abstract void setNormalized(float hostValue) nothrow;

    /// Returns: A normalized float, representing the parameter value.
    abstract float getNormalized() nothrow;

    /// Display parameter (without label).
    abstract void toStringN(char* buffer, size_t numBytes) nothrow;    

private:
    Client _client; /// backlink to parameter holder
    int _index;
    string _name;
    string _label;
    Spinlock _valueSpinlock; /// Spinlock that protects the value.
}


/// A boolean parameter
class BoolParameter : Parameter
{
public:
    this(Client client, int index, string name, bool defaultValue = false)
    {
        super(client, index, name, "");
        _value = defaultValue;
    }

    override void setNormalized(float hostValue)
    {
        if (hostValue < 0.5f)
            _value = false;
        else
            _value = true;
    }

    override float getNormalized() nothrow
    {
        return _value ? 1.0f : 0.0f;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow
    {
        if (_value)
            snprintf(buffer, numBytes, "true");
        else
            snprintf(buffer, numBytes, "false");
    }

private:
    bool _value;
}

/// A float parameter
class FloatParameter : Parameter
{
public:
    this(Client client, int index, string name, string label, float min = 0.0f, float max = 1.0f, float defaultValue = 0.5f)
    {
        super(client, index, name, label);
        assert(defaultValue >= min && defaultValue <= max);
        _defaultValue = defaultValue;
        _name = name;
        _value = _defaultValue;
        _min = min;
        _max = max;
    }

    void setFromGUI(float value)
    {
        if (value < _min)
            value = _min;
        if (value > _max)
            value = _max;

        {
            _valueSpinlock.lock();
            scope(exit) _valueSpinlock.unlock();
            _value = value;
        }
        // TODO: is there any race here?
        _client.hostCommand().paramAutomate(_index, getNormalized());
    }

    override void setNormalized(float hostValue)
    {
        _value = clamp!float(_min + (_max - _min) * hostValue, _min, _max);
    }

    override float getNormalized() nothrow
    {
        float normalized = clamp!float( (_value - _min) / (_max - _min), 0.0f, 1.0f);        
        return normalized;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow
    {
        snprintf(buffer, numBytes, "%2.2f", _value);
    }

    float value() pure const nothrow @nogc
    {
        return _value;
    }

    float minValue() pure const nothrow @nogc
    {
        return _min;
    }

    float maxValue() pure const nothrow @nogc
    {
        return _max;
    }

    float defaultValue() pure const nothrow @nogc
    {
        return _defaultValue;
    }

private:
    float _value;
    float _min;
    float _max;
    float _defaultValue;
}

/// An integer parameter
class IntParameter : Parameter
{
public:
    this(Client client, int index, string name, string label, int min = 0, int max = 1, int defaultValue = 0)
    {
        super(client, index, name, label);
        _name = name;
        _value = clamp!int(defaultValue, min, max);
        _min = min;
        _max = max;
    }

    override void setNormalized(float hostValue)
    {
        int rounded = cast(int)lround( _min + (_max - _min) * hostValue );
        _value = clamp!int(rounded, _min, _max);
    }

    override float getNormalized() nothrow
    {
        float normalized = clamp!float( (cast(float)_value - _min) / (_max - _min), 0.0f, 1.0f);        
        return normalized;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow
    {
        snprintf(buffer, numBytes, "%d", _value);
    }

    int value() pure const nothrow @nogc
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