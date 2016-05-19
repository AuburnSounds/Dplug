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
module dplug.client.params;

import core.atomic;
import core.stdc.stdio;
import core.stdc.string;

import std.math;
import std.algorithm;
import std.string;
import std.conv;

import gfm.core;

import dplug.core;
import dplug.client.client;


/// Plugin parameter.
/// Implement the Observer pattern for UI support.
/// Note: Recursive mutexes are needed here because `getNormalized()`
/// could need locking an already taken mutex.
class Parameter
{
public:

    /// Returns: Parameters name. Displayed when the plugin has no UI.
    string name() pure const nothrow @nogc
    {
        return _name;
    }

    /// Returns: Parameters unit label.
    string label() pure const nothrow @nogc
    {
        return _label;
    }

    /// Returns: Index of parameter in the parameter list.
    int index() pure const nothrow @nogc
    {
        return _index;
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
        foreach(listener; _listeners)
            listener.onBeginParameterEdit(this);
    }

    /// Warns the host that a parameter has finished being edited.
    void endParamEdit()
    {
        _client.hostCommand().endParamEdit(_index);
        foreach(listener; _listeners)
            listener.onEndParameterEdit(this);
    }

    /// Returns: A normalized double, representing the parameter value.
    abstract double getNormalized() nothrow @nogc;

    /// Returns: A normalized double, representing the default parameter value.
    abstract double getNormalizedDefault() nothrow @nogc;

    /// Returns: A string associated with the normalized normalized.
    abstract string stringFromNormalizedValue(double normalizedValue) nothrow;

    /// Returns: A normalized normalized associated with the string.
    /// Can throw Exceptions.
    abstract double normalizedValueFromString(string valueString);

    ~this()
    {
        debug ensureNotInGC("Parameter");
        _valueMutex.destroy();
    }

protected:

    this(int index, string name, string label)
    {
        _client = null;
        _name = name;
        _label = label;
        _index = index;
        _valueMutex = new UncheckedMutex();
    }

    /// From a normalized double, set the parameter value.
    /// No guarantee at all that getNormalized will return the same,
    /// because this value is rounded to fit.
    abstract void setNormalized(double hostValue) nothrow @nogc;

    /// Display parameter (without label).
    abstract void toStringN(char* buffer, size_t numBytes) nothrow;

    void notifyListeners() nothrow @nogc
    {
        foreach(listener; _listeners)
            listener.onParameterChanged(this);
    }

package:

    /// Parameters are owned by a client, this is used to make them refer back to it.
    void setClientReference(Client client)
    {
        _client = client;
    }

private:

    /// weak reference to parameter holder, set after parameter creation
    Client _client;

    int _index;
    string _name;
    string _label;
    IParameterListener[] _listeners;

    UncheckedMutex _valueMutex;

}

/// Parameter listeners are called whenever a parameter is changed from the host POV.
/// Intended making GUI controls call `setDirty()` and move with automation.
interface IParameterListener
{
    /// Called when a parameter value was changed
    void onParameterChanged(Parameter sender) nothrow @nogc;

    /// Called when a parameter value start being changed due to an UI element
    void onBeginParameterEdit(Parameter sender);

    /// Called when a parameter value stops being changed
    void onEndParameterEdit(Parameter sender);
}


/// A boolean parameter
class BoolParameter : Parameter
{
public:
    this(int index, string name, bool defaultValue)
    {
        super(index, name, "");
        _value = defaultValue;
        _defaultValue = defaultValue;
    }

    override void setNormalized(double hostValue) nothrow @nogc
    {
        _valueMutex.lock();
        bool newValue = (hostValue >= 0.5);
        atomicStore(_value, newValue);
        _valueMutex.unlock();
    }

    override double getNormalized() nothrow @nogc
    {
        return value() ? 1.0 : 0.0;
    }

    override double getNormalizedDefault() nothrow @nogc
    {
        return _defaultValue ? 1.0 : 0.0;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow @nogc
    {
        bool v = value();

        if (v)
            snprintf(buffer, numBytes, "yes");
        else
            snprintf(buffer, numBytes, "no");
    }

    /// Returns: A string associated with the normalized normalized.
    override string stringFromNormalizedValue(double normalizedValue) nothrow
    {
        bool value = (normalizedValue >= 0.5);
        return value ? "yes" : "no";
    }

    /// Returns: A normalized normalized associated with the string.
    override double normalizedValueFromString(string valueString)
    {
        if (valueString == "yes") return 1;
        if (valueString == "no") return 1;
        throw new Exception("Couln't parse parameter string");
    }

    final void setFromGUI(bool newValue)
    {
        _valueMutex.lock();
        atomicStore(_value, newValue);
        double normalized = getNormalized();
        _valueMutex.unlock();

        _client.hostCommand().paramAutomate(_index, normalized);
        notifyListeners();
    }

    /// Gets current value.
    final bool value() nothrow @nogc
    {
        bool v = void;
        _valueMutex.lock();
        v = atomicLoad(_value);
        _valueMutex.unlock();
        return v;
    }

    /// Same as value but doesn't use locking,
    /// which make it a better fit for the audio thread.
    final bool valueAtomic() nothrow @nogc
    {
        return atomicLoad(_value);
    }

    /// Returns: default value.
    final bool defaultValue() pure const nothrow @nogc
    {
        return _defaultValue;
    }

private:
    shared(bool) _value;
    bool _defaultValue;
}

/// An integer parameter
deprecated("Was renamed to IntegerParameter") alias IntParameter = IntegerParameter;
class IntegerParameter : Parameter
{
public:
    this(int index, string name, string label, int min = 0, int max = 1, int defaultValue = 0)
    {
        super(index, name, label);
        _name = name;
        _value = _defaultValue = clampValue!int(defaultValue, min, max);
        _min = min;
        _max = max;
    }

    override void setNormalized(double hostValue)
    {
        int newValue = fromNormalized(hostValue);
        _valueMutex.lock();
        atomicStore(_value, newValue);
        _valueMutex.unlock();
    }

    override double getNormalized() nothrow @nogc
    {
        int v = value();
        double normalized = toNormalized(value());
        return normalized;
    }

    override double getNormalizedDefault() nothrow @nogc
    {
        double normalized = toNormalized(_defaultValue);
        return normalized;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow @nogc
    {
        int v =  value();
        snprintf(buffer, numBytes, "%d", v);
    }

    override string stringFromNormalizedValue(double normalizedValue) nothrow
    {
        return to!string(fromNormalized(normalizedValue));
    }

    override double normalizedValueFromString(string valueString)
    {
        return toNormalized(to!int(valueString));
    }

    /// Gets the current parameter value.
    final int value() nothrow @nogc
    {
        int v = void;
        _valueMutex.lock();
        v = atomicLoad(_value);
        _valueMutex.unlock();
        return v;
    }

    /// Same as value but doesn't use locking,
    /// which make it a better fit for the audio thread.
    final int valueAtomic() nothrow @nogc
    {
        return atomicLoad(_value);
    }

    final void setFromGUI(int value)
    {
        if (value < _min)
            value = _min;
        if (value > _max)
            value = _max;

        _valueMutex.lock();
        atomicStore(_value, value);
        double normalized = getNormalized();
        _valueMutex.unlock();

        _client.hostCommand().paramAutomate(_index, normalized);
        notifyListeners();
    }

    /// Returns: minimum possible values.
    final int minValue() pure const nothrow @nogc
    {
        return _min;
    }

    /// Returns: maximum possible values.
    final int maxValue() pure const nothrow @nogc
    {
        return _max;
    }

    /// Returns: number of possible values.
    final int numValues() pure const nothrow @nogc
    {
        return 1 + _max - _min;
    }

    /// Returns: default value.
    final int defaultValue() pure const nothrow @nogc
    {
        return _defaultValue;
    }

private:
    shared(int) _value;
    int _min;
    int _max;
    int _defaultValue;

    final int fromNormalized(double normalizedValue) nothrow @nogc
    {
        double mapped = _min + (_max - _min) * normalizedValue;

        // slightly incorrect rounding, but lround is crashing
        int rounded = void;
        if (mapped)
            rounded = cast(int)(0.5f + mapped);
        else
            rounded = cast(int)(-0.5f + mapped);

        return clampValue!int(rounded, _min, _max);
    }

    final double toNormalized(int value) nothrow @nogc
    {
        return clampValue!double( (cast(double)value - _min) / (_max - _min), 0.0, 1.0);
    }
}

class EnumParameter : IntegerParameter
{
public:
    this(int index, string name, const(string[]) possibleValues, int defaultValue = 0)
    {
        super(index, name, "", 0, cast(int)(possibleValues.length) - 1, defaultValue);

        _possibleValues = possibleValues;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow @nogc
    {
        int v = value();
        int toCopy = max(0, min( cast(int)(numBytes) - 1, cast(int)(_possibleValues[v].length)));
        memcpy(buffer, _possibleValues[v].ptr, toCopy);
        // add terminal zero
        if (numBytes > 0)
            buffer[toCopy] = '\0';
    }

    override string stringFromNormalizedValue(double normalizedValue) nothrow
    {
        return _possibleValues[ fromNormalized(normalizedValue) ];
    }

    override double normalizedValueFromString(string valueString)
    {
        foreach(int i; 0..cast(int)(_possibleValues.length))
            if (_possibleValues[i] == valueString)
                return toNormalized(i);

        throw new Exception("Couldn't parse enum parameter value");
    }

    final string getValueString(int n) nothrow @nogc
    {
        return _possibleValues[n];
    }

private:
    const(string[]) _possibleValues;
}

private
{
    T clampValue(T)(T x, T min, T max) pure nothrow @nogc
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
    this(int index, string name, string label, double min, double max, double defaultValue)
    {
        super(index, name, label);

        // If you fail in this assertion, this means your default value is out of range.
        assert(defaultValue >= min && defaultValue <= max);

        _defaultValue = defaultValue;
        _name = name;
        _value = _defaultValue;
        _min = min;
        _max = max;
    }

    /// Gets current value.
    final double value() nothrow @nogc
    {
        double v = void;
        _valueMutex.lock();
        v = atomicLoad(_value);
        _valueMutex.unlock();
        return v;
    }

    /// Same as value but doesn't use locking,
    /// which make it a better fit for the audio thread.
    final double valueAtomic() nothrow @nogc
    {
        return atomicLoad(_value);
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

        _valueMutex.lock();
        atomicStore(_value, value);
        double normalized = getNormalized();
        _valueMutex.unlock();

        _client.hostCommand().paramAutomate(_index, normalized);
        notifyListeners();
    }

    override void setNormalized(double hostValue) nothrow @nogc
    {
        double v = fromNormalized(hostValue);
        _valueMutex.lock();
        atomicStore(_value, v);
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

    override string stringFromNormalizedValue(double normalizedValue) nothrow
    {
        try
        {
            return to!string(fromNormalized(normalizedValue));
        }
        catch(Exception e)
        {
            assert(false);
        }
    }

    override double normalizedValueFromString(string valueString)
    {
        return toNormalized(to!double(valueString));
    }

    /// Override it to specify mapping from parameter values to normalized [0..1]
    abstract double toNormalized(double value) nothrow @nogc;

    /// Override it to specify mapping from normalized [0..1] to parameter value
    abstract double fromNormalized(double value) nothrow @nogc;

private:
    shared(double) _value;
    double _min;
    double _max;
    double _defaultValue;
}

/// Linear-mapped float parameter (eg: dry/wet)
class LinearFloatParameter : FloatParameter
{
    this(int index, string name, string label, float min, float max, float defaultValue)
    {
        super(index, name, label, min, max, defaultValue);
    }

    override double toNormalized(double value) nothrow @nogc
    {
        return clampValue!double( (value - _min) / (_max - _min), 0.0, 1.0);
    }

    override double fromNormalized(double normalizedValue) nothrow @nogc
    {
        return clampValue!double(_min + (_max - _min) * normalizedValue, _min, _max);
    }
}

/// Float parameter following an exponential type of mapping (eg: cutoff frequency)
class LogFloatParameter : FloatParameter
{
    this(int index, string name, string label, double min, double max, double defaultValue)
    {
        assert(min > 0 && max > 0);
        super(index, name, label, min, max, defaultValue);
    }

    override double toNormalized(double value) nothrow @nogc
    {
        double result = log(value / _min) / log(_max / _min);
        if (result < 0)
            result = 0;
        if (result > 1)
            result = 1;
        return result;
    }

    override double fromNormalized(double normalizedValue) nothrow @nogc
    {
        return _min * exp(normalizedValue * log(_max / _min));
    }
}

/// A parameter with [-inf to value] dB log mapping
class GainParameter : FloatParameter
{
    this(int index, string name, double max, double defaultValue, double shape = 2.0)
    {
        super(index, name, "dB", -double.infinity, max, defaultValue);
        _shape = shape;
    }

    override void toStringN(char* buffer, size_t numBytes) nothrow @nogc
    {
        snprintf(buffer, numBytes, "%2.1f", value());
    }

    override double toNormalized(double value) nothrow @nogc
    {
        double maxAmplitude = deciBelToFloat(_max);
        double result = ( deciBelToFloat(value) / maxAmplitude ) ^^ (1 / _shape);
        if (result < 0)
            result = 0;
        if (result > 1)
            result = 1;
        assert(isFinite(result));
        return result;
    }

    override double fromNormalized(double normalizedValue) nothrow @nogc
    {
        return floatToDeciBel(  (normalizedValue ^^ _shape) * deciBelToFloat(_max));
    }

private:
    double _shape;
}

/// Float parameter following a x^N type mapping (eg: something that doesn't fit in the other categories)
class PowFloatParameter : FloatParameter
{
    this(int index, string name, string label, double min, double max, double defaultValue, double shape)
    {
        super(index, name, label, min, max, defaultValue);
        _shape = shape;
    }

    override double toNormalized(double value) nothrow @nogc
    {
        double result = clampValue!double( (value - _min) / (_max - _min), 0.0, 1.0) ^^ (1 / _shape);
        assert(result >= 0 && result <= 1);
        return result;
    }

    override double fromNormalized(double normalizedValue) nothrow @nogc
    {
        double v = _min + (normalizedValue ^^ _shape) * (_max - _min);
        return clampValue!double(v, _min, _max);
    }

private:
    double _shape;
}
