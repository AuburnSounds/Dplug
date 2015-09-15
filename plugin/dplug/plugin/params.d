/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 and later Auburn Sounds

Portions copyright other contributors, see each source file for more information

This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
1. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
module dplug.plugin.params;

import core.stdc.stdio;

import std.math;

import gfm.core;

import dplug.core;
import dplug.plugin.client;


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

    /// From a normalized double [0..1], set the parameter value.
    void setFromHost(double hostValue) nothrow @nogc
    {
        setNormalized(hostValue);
        notifyListeners();
    }

    /// Returns: A normalized double [0..1], represents the parameter value.
    double getForHost() nothrow @nogc
    {
        return getNormalized();
    }

    void toDisplayN(char* buffer, size_t numBytes) nothrow
    {
        toStringN(buffer, numBytes);
    }

    /// Adds a parameter listener.
    void addListener(IParameterListener listener)
    {
        _listeners ~= listener;
    }

    /// Removes a parameter listener.
    void removeListener(IParameterListener listener)
    {
        static auto removeElement(IParameterListener[] haystack, IParameterListener needle)
        {
            import std.algorithm;
            auto index = haystack.countUntil(needle);
            return (index != -1) ? haystack.remove(index) : haystack;
        }
        _listeners = removeElement(_listeners, listener);
    }

    /// Warns the host that a parameter will be edited.
    void beginParamEdit()
    {
        _client.hostCommand().beginParamEdit(_index);
    }

    /// Warns the host that a parameter has finished being edited.
    void endParamEdit()
    {
        _client.hostCommand().endParamEdit(_index);
    }

    /// Returns: A normalized double, representing the default parameter value.
    abstract double getNormalizedDefault() nothrow @nogc;

    ~this()
    {
        if (_initialized)
        {
            debug ensureNotInGC("Parameter");
            _valueMutex.destroy();
            _initialized = false;
        }
    }

protected:

    this(Client client, int index, string name, string label)
    {
        _client = client;
        _name = name;
        _label = label;
        _index = index;
        _valueMutex = new UncheckedMutex();
        _initialized = true;
    }

    /// From a normalized double, set the parameter value.
    /// No guarantee at all that getNormalized will return the same,
    /// because this value is rounded to fit.
    abstract void setNormalized(double hostValue) nothrow @nogc;

    /// Returns: A normalized double, representing the parameter value.
    abstract double getNormalized() nothrow @nogc;

    /// Display parameter (without label).
    abstract void toStringN(char* buffer, size_t numBytes) nothrow;

    void notifyListeners() nothrow @nogc
    {
        foreach(listener; _listeners)
            listener.onParameterChanged(this);
    }

private:
    Client _client; /// backlink to parameter holder
    int _index;
    string _name;
    string _label;
    IParameterListener[] _listeners;

    UncheckedMutex _valueMutex;

    bool _initialized; // destructor flag
}

/// Parameter listeners are called whenever a parameter is changed from the host POV.
/// Intended making GUI controls call `setDirty()` and move with automation.
interface IParameterListener
{
    void onParameterChanged(Parameter sender) nothrow @nogc;
}


/// A boolean parameter
class BoolParameter : Parameter
{
public:
    this(Client client, int index, string name, string label, bool defaultValue)
    {
        super(client, index, name, label);
        _value = defaultValue;
        _defaultValue = defaultValue;
    }

    override void setNormalized(double hostValue) nothrow @nogc
    {
        _valueMutex.lock();
        if (hostValue < 0.5)
            _value = false;
        else
            _value = true;
        _valueMutex.unlock();
    }

    override double getNormalized() nothrow @nogc
    {
        _valueMutex.lock();
        double result = _value ? 1.0 : 0.0;
        _valueMutex.unlock();
        return result;
    }

    override double getNormalizedDefault() nothrow @nogc
    {
        return _defaultValue ? 1.0 : 0.0;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow @nogc
    {
        bool v;
        _valueMutex.lock();
        v = _value;
        _valueMutex.unlock();

        if (v)
            snprintf(buffer, numBytes, "true");
        else
            snprintf(buffer, numBytes, "false");
    }

    void setFromGUI(bool value)
    {
        _valueMutex.lock();
        _value = value;
        _valueMutex.unlock();

        // Important
        // There is a race here on _value, because spinlocks aren't reentrant we had to move this line
        // out of the mutex.
        // That said, the potential for harm seems reduced (receiving a setParameter between _value assignment and getNormalized).

        double normalized = getNormalized();

        _client.hostCommand().paramAutomate(_index, normalized);
        notifyListeners();
    }

    bool value() nothrow @nogc
    {
        _valueMutex.lock();
        scope(exit) _valueMutex.unlock();
        return _value;
    }

    bool defaultValue() pure const nothrow @nogc
    {
        return _defaultValue;
    }

private:
    bool _value;
    bool _defaultValue;
}

/// An integer parameter
class IntParameter : Parameter
{
public:
    this(Client client, int index, string name, string label, int min = 0, int max = 1, int defaultValue = 0)
    {
        super(client, index, name, label);
        _name = name;
        _value = _defaultValue = clamp!int(defaultValue, min, max);
        _min = min;
        _max = max;
    }

    override void setNormalized(double hostValue)
    {
        int rounded = cast(int)lround( _min + (_max - _min) * hostValue );

        _valueMutex.lock();
        _value = clamp!int(rounded, _min, _max);
        _valueMutex.unlock();
    }

    override double getNormalized() nothrow @nogc
    {
        int v;
        _valueMutex.lock();
        v = _value;
        _valueMutex.unlock();

        double normalized = clamp!double( (cast(double)v - _min) / (_max - _min), 0.0, 1.0);
        return normalized;
    }

    override double getNormalizedDefault() nothrow @nogc
    {
        double normalized = clamp!double( (_defaultValue - _min) / (_max - _min), 0.0, 1.0);
        return normalized;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow @nogc
    {
        int v;
        _valueMutex.lock();
        v = _value;
        _valueMutex.unlock();
        snprintf(buffer, numBytes, "%d", v);
    }

    int value() nothrow @nogc
    {
        _valueMutex.lock();
        scope(exit) _valueMutex.unlock();
        return _value;
    }

private:
    int _value;
    int _min;
    int _max;
    int _defaultValue;
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

/// A float parameter
/// This is an abstract class, mapping from normalized to parmeter values is left to the user.
class FloatParameter : Parameter
{
public:
    this(Client client, int index, string name, string label, double min, double max, double defaultValue)
    {
        super(client, index, name, label);
        assert(defaultValue >= min && defaultValue <= max);
        _defaultValue = defaultValue;
        _name = name;
        _value = _defaultValue;
        _min = min;
        _max = max;
    }

    final double value() nothrow @nogc
    {
        _valueMutex.lock();
        scope(exit) _valueMutex.unlock();
        return _value;
    }

    final double minValue() pure const nothrow @nogc
    {
        return _min;
    }

    final double maxValue() pure const nothrow @nogc
    {
        return _max;
    }

    final double defaultValue() pure const nothrow @nogc
    {
        return _defaultValue;
    }

    final void setFromGUINormalized(double normalizedValue)
    {
        assert(normalizedValue >= 0 && normalizedValue <= 1);
        setFromGUI(fromNormalized(normalizedValue));
    }

    final void setFromGUI(double value)
    {
        if (value < _min)
            value = _min;
        if (value > _max)
            value = _max;

        double normalized;

        _valueMutex.lock();
        _value = value;
        _valueMutex.unlock();

        // Important
        // There is a race here on _value, because spinlocks aren't reentrant we had to move this line
        // out of the mutex.
        // That said, the potential for harm seems reduced (receiving a setParameter between _value assignment and getNormalized).

        normalized = getNormalized();

        _client.hostCommand().paramAutomate(_index, normalized);
        notifyListeners();
    }

    override void setNormalized(double hostValue) nothrow @nogc
    {
        double v = fromNormalized(hostValue);
        _valueMutex.lock();
        _value = v;
        _valueMutex.unlock();
    }

    override double getNormalized() nothrow @nogc
    {
        return toNormalized(value());
    }

    override double getNormalizedDefault() nothrow @nogc
    {
        return toNormalized(_defaultValue);
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow @nogc
    {
        snprintf(buffer, numBytes, "%2.2f", value());
    }

    /// Override it to specify mapping from parameter values to normalized [0..1]
    abstract double toNormalized(double value) nothrow @nogc;

    /// Override it to specify mapping from normalized [0..1] to parameter value
    abstract double fromNormalized(double value) nothrow @nogc;

private:
    double _value;
    double _min;
    double _max;
    double _defaultValue;
}

/// Linear-mapped float parameter
class LinearFloatParameter : FloatParameter
{
    this(Client client, int index, string name, string label, float min, float max, float defaultValue)
    {
        super(client, index, name, label, min, max, defaultValue);
    }

    override double toNormalized(double value) nothrow @nogc
    {
        return clamp!double( (value - _min) / (_max - _min), 0.0, 1.0);
    }

    override double fromNormalized(double normalizedValue) nothrow @nogc
    {
        return clamp!double(_min + (_max - _min) * normalizedValue, _min, _max);
    }
}

/// Log-mapped float parameter
class LogFloatParameter : FloatParameter
{
    this(Client client, int index, string name, string label, double min, double max, double defaultValue, double shape)
    {
        super(client, index, name, label, min, max, defaultValue);
        _shape = shape;
    }

    override double toNormalized(double value) nothrow @nogc
    {
        double result = clamp!double( (value - _min) / (_max - _min), 0.0, 1.0) ^^ (1 / _shape);
        assert(result >= 0 && result <= 1);
        return result;
    }

    override double fromNormalized(double normalizedValue) nothrow @nogc
    {
        double v = _min + (normalizedValue ^^ _shape) * (_max - _min);
        return clamp!double(v, _min, _max);
    }

private:
    double _shape;
}

/// A parameter with [-inf to value] dB log mapping
class GainParameter : FloatParameter
{
    this(Client client, int index, string name, double max, double defaultValue)
    {
        super(client, index, name, "dB", -double.infinity, max, defaultValue);
    }

    override double toNormalized(double value) nothrow @nogc
    {
        if (value == -double.infinity)
            return 0.0f;

        double maxAmplitude = deciBelToFloat(_max);
        double result = ( deciBelToFloat(value) / maxAmplitude ) ^^ (1 / POW);
        assert(isFinite(result));
        return result;
    }

    override double fromNormalized(double normalizedValue) nothrow @nogc
    {
        if (normalizedValue == 0)
            return -double.infinity;

        return floatToDeciBel(  (normalizedValue ^^ POW) * deciBelToFloat(_max));
    }

private:
    double _shape;
    enum double POW = 2.0;
}
