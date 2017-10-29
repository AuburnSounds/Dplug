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
/**
    Definitions of plug-in `Parameter`, and its many variants.
*/
module dplug.client.params;

import core.atomic;
import core.stdc.stdio;
import core.stdc.string;

import std.math;
import std.algorithm.comparison;
import std.string;
import std.conv;

import dplug.core.math;
import dplug.core.sync;
import dplug.core.nogc;
import dplug.core.alignedbuffer;
import dplug.client.client;


/// Plugin parameter.
/// Implement the Observer pattern for UI support.
/// Note: Recursive mutexes are needed here because `getNormalized()`
/// could need locking an already taken mutex.
class Parameter
{
public:
nothrow:
@nogc:

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

    void toDisplayN(char* buffer, size_t numBytes) nothrow @nogc
    {
        toStringN(buffer, numBytes);
    }

    /// Adds a parameter listener.
    void addListener(IParameterListener listener) nothrow @nogc
    {
        _listeners.pushBack(listener);
    }

    /// Removes a parameter listener.
    void removeListener(IParameterListener listener) nothrow @nogc
    {
        int index = _listeners.indexOf(listener);
        if (index != -1)
            _listeners.removeAndReplaceByLastElement(index);
    }

    /// Warns the host that a parameter will be edited.
    /// Should only ever be called from the UI thread.
    void beginParamEdit() nothrow @nogc
    {
        debug _editCount += 1;
        _client.hostCommand().beginParamEdit(_index);
        foreach(listener; _listeners)
            listener.onBeginParameterEdit(this);
    }

    /// Warns the host that a parameter has finished being edited.
    /// Should only ever be called from the UI thread.
    void endParamEdit() nothrow @nogc
    {
        _client.hostCommand().endParamEdit(_index);
        foreach(listener; _listeners)
            listener.onEndParameterEdit(this);
        debug _editCount -= 1;
    }

    /// Returns: A normalized double, representing the parameter value.
    abstract double getNormalized() nothrow @nogc;

    /// Returns: A normalized double, representing the default parameter value.
    abstract double getNormalizedDefault() nothrow @nogc;

    /// Returns: A string associated with the normalized normalized.
    abstract void stringFromNormalizedValue(double normalizedValue, char* buffer, size_t len) nothrow @nogc;

    /// Returns: A normalized normalized associated with the string.
    /// Can throw Exceptions.
    abstract bool normalizedValueFromString(string valueString, out double result) nothrow @nogc;

    ~this()
    {
        _valueMutex.destroy();
        debug assert(_editCount == 0);
    }

protected:

    this(int index, string name, string label) nothrow @nogc
    {
        _client = null;
        _name = name;
        _label = label;
        _index = index;
        _valueMutex = makeMutex();
        _listeners = makeVec!IParameterListener();
    }

    /// From a normalized double, set the parameter value.
    /// No guarantee at all that getNormalized will return the same,
    /// because this value is rounded to fit.
    abstract void setNormalized(double hostValue) nothrow @nogc;

    /// Display parameter (without label).
    abstract void toStringN(char* buffer, size_t numBytes) nothrow @nogc;

    void notifyListeners() nothrow @nogc
    {
        foreach(listener; _listeners)
            listener.onParameterChanged(this);
    }

    void checkBeingEdited() nothrow @nogc
    {
        // If you fail here, you have changed the value of a Parameter from the UI
        // without enclosing within a pair of `beginParamEdit()`/`endParamEdit()`.
        // This will cause some hosts like Apple Logic not to record automation.
        //
        // When setting a Parameter from an UI widget, it's important to call `beginParamEdit()`
        // and `endParamEdit()` too.
        debug assert(_editCount > 0);
    }

package:

    /// Parameters are owned by a client, this is used to make them refer back to it.
    void setClientReference(Client client) nothrow @nogc
    {
        _client = client;
    }

private:

    /// weak reference to parameter holder, set after parameter creation
    Client _client;

    int _index;
    string _name;
    string _label;
    Vec!IParameterListener _listeners;

    // Current number of calls into `beginParamEdit()`/`endParamEdit()` pair.
    // Only checked in debug mode.
    debug int _editCount = 0;

    UncheckedMutex _valueMutex;
}

/// Parameter listeners are called whenever a parameter is changed from the host POV.
/// Intended making GUI controls call `setDirty()` and move with automation.
interface IParameterListener
{
nothrow @nogc:

    /// Called when a parameter value was changed
    /// You'll probably want to call `setDirtyWhole()` or `setDirty()` in it
    /// to make the graphics respond to host changing a parameter.
    void onParameterChanged(Parameter sender);

    /// Called when a parameter value start being changed due to an UI element
    void onBeginParameterEdit(Parameter sender);

    /// Called when a parameter value stops being changed
    void onEndParameterEdit(Parameter sender);
}


/// A boolean parameter
class BoolParameter : Parameter
{
public:
    this(int index, string name, bool defaultValue) nothrow @nogc
    {
        super(index, name, "");
        _value = defaultValue;
        _defaultValue = defaultValue;
    }

    override void setNormalized(double hostValue)
    {
        _valueMutex.lock();
        bool newValue = (hostValue >= 0.5);
        atomicStore(_value, newValue);
        _valueMutex.unlock();
    }

    override double getNormalized() 
    {
        return value() ? 1.0 : 0.0;
    }

    override double getNormalizedDefault() 
    {
        return _defaultValue ? 1.0 : 0.0;
    }

    override void toStringN(char* buffer, size_t numBytes)
    {
        bool v = value();

        if (v)
            snprintf(buffer, numBytes, "yes");
        else
            snprintf(buffer, numBytes, "no");
    }

    /// Returns: A string associated with the normalized normalized.
    override void stringFromNormalizedValue(double normalizedValue, char* buffer, size_t len)
    {
        bool value = (normalizedValue >= 0.5);
        if (value)
            snprintf(buffer, len, "yes");
        else
            snprintf(buffer, len, "no");
    }

    /// Returns: A normalized normalized associated with the string.
    override bool normalizedValueFromString(string valueString, out double result)
    {
        if (valueString == "yes")
        {
            result = 1;
            return true;
        }
        else if (valueString == "no")
        {
            result = 0;
            return true;
        }
        else
            return false;
    }

    /// Toggles the parameter value from the UI thread.
    final void toggleFromGUI() nothrow @nogc
    {
        setFromGUI(!value());
    }

    /// Sets the parameter value from the UI thread.
    final void setFromGUI(bool newValue) nothrow @nogc
    {
        checkBeingEdited();
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
        v = atomicLoad!(MemoryOrder.raw)(_value); // already sequenced by mutex locks
        _valueMutex.unlock();
        return v;
    }

    /// Same as value but doesn't use locking, and doesn't use ordering.
    /// Which make it a better fit for the audio thread.
    final bool valueAtomic() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(_value);
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
class IntegerParameter : Parameter
{
public:
    this(int index, string name, string label, int min = 0, int max = 1, int defaultValue = 0) nothrow @nogc
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

    override double getNormalized()
    {
        int v = value();
        double normalized = toNormalized(value());
        return normalized;
    }

    override double getNormalizedDefault()
    {
        double normalized = toNormalized(_defaultValue);
        return normalized;
    }

    override void toStringN(char* buffer, size_t numBytes)
    {
        int v =  value();
        snprintf(buffer, numBytes, "%d", v);
    }

    override void stringFromNormalizedValue(double normalizedValue, char* buffer, size_t len)
    {
        int denorm = fromNormalized(normalizedValue);
        snprintf(buffer, len, "%d", denorm);
    }

    override bool normalizedValueFromString(string valueString, out double result)
    {
        if (valueString.length > 63)
            return false;

        // Because the input string is not zero-terminated
        char[64] buf;
        snprintf(buf.ptr, buf.length, "%.*s", valueString.length, valueString.ptr);

        int denorm;
        if (1 == sscanf(buf.ptr, "%d", denorm))
        {
            result = toNormalized(denorm);
            return true;
        }
        else
            return false;
    }

    /// Gets the current parameter value.
    final int value() nothrow @nogc
    {
        int v = void;
        _valueMutex.lock();
        v = atomicLoad!(MemoryOrder.raw)(_value); // already sequenced by mutex locks
        _valueMutex.unlock();
        return v;
    }

    /// Same as value but doesn't use locking, and doesn't use ordering.
    /// Which make it a better fit for the audio thread.
    final int valueAtomic() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(_value);
    }

    final void setFromGUI(int value) nothrow @nogc
    {
        checkBeingEdited();
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

    final void setFromGUINormalized(double normalizedValue) nothrow @nogc
    {
        assert(normalizedValue >= 0 && normalizedValue <= 1);
        setFromGUI(fromNormalized(normalizedValue));
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
        if (mapped >= 0)
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
    this(int index, string name, const(string[]) possibleValues, int defaultValue = 0) nothrow @nogc
    {
        super(index, name, "", 0, cast(int)(possibleValues.length) - 1, defaultValue);

        _possibleValues = possibleValues;
    }

    override void toStringN(char* buffer, size_t numBytes)
    {
        int v = value();
        int toCopy = max(0, min( cast(int)(numBytes) - 1, cast(int)(_possibleValues[v].length)));
        memcpy(buffer, _possibleValues[v].ptr, toCopy);
        // add terminal zero
        if (numBytes > 0)
            buffer[toCopy] = '\0';
    }

    override void stringFromNormalizedValue(double normalizedValue, char* buffer, size_t len)
    {
        const(char[]) valueLabel = _possibleValues[ fromNormalized(normalizedValue) ];
        snprintf(buffer, len, "%.*s", valueLabel.length, valueLabel.ptr);
    }

    override bool normalizedValueFromString(string valueString, out double result)
    {
        foreach(int i; 0..cast(int)(_possibleValues.length))
            if (_possibleValues[i] == valueString)
            {
                result = toNormalized(i);
                return true;
            }

        return false;
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
    this(int index, string name, string label, double min, double max, double defaultValue) nothrow @nogc
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
        v = atomicLoad!(MemoryOrder.raw)(_value); // already sequenced by mutex locks
        _valueMutex.unlock();
        return v;
    }

    /// Same as value but doesn't use locking, and doesn't use ordering.
    /// Which make it a better fit for the audio thread.
    final double valueAtomic() nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.raw)(_value);
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

    final void setFromGUINormalized(double normalizedValue) nothrow @nogc
    {
        assert(normalizedValue >= 0 && normalizedValue <= 1);
        setFromGUI(fromNormalized(normalizedValue));
    }

    /// Sets the number of decimal digits after the dot to be displayed.
    final void setDecimalPrecision(int digits) nothrow @nogc
    {
        assert(digits >= 0);
        assert(digits <= 9);
        _formatString[3] = cast(char)('0' + digits);
    }

    final void setFromGUI(double value) nothrow @nogc
    {
        checkBeingEdited();
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

    override void setNormalized(double hostValue)
    {
        double v = fromNormalized(hostValue);
        _valueMutex.lock();
        atomicStore(_value, v);
        _valueMutex.unlock();
    }

    override double getNormalized()
    {
        return toNormalized(value());
    }

    override double getNormalizedDefault() 
    {
        return toNormalized(_defaultValue);
    }

    override void toStringN(char* buffer, size_t numBytes)
    {
        snprintf(buffer, numBytes, _formatString.ptr, value());
    }

    override void stringFromNormalizedValue(double normalizedValue, char* buffer, size_t len)
    {
        double denorm = fromNormalized(normalizedValue);
        snprintf(buffer, len, _formatString.ptr, denorm);
    }

    override bool normalizedValueFromString(string valueString, out double result)
    {
        if (valueString.length > 63)
            return false;

        // Because the input string is not zero-terminated
        char[64] buf;
        snprintf(buf.ptr, buf.length, "%.*s", valueString.length, valueString.ptr);

        int denorm;
        if (1 == sscanf(buf.ptr, "%f", denorm))
        {
            result = toNormalized(denorm);
            return true;
        }
        else
            return false;
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

    // format string for string conversion, is overwritten by `setDecimalPrecision`.
    char[6] _formatString = "%2.2f"; 
}

/// Linear-mapped float parameter (eg: dry/wet)
class LinearFloatParameter : FloatParameter
{
    this(int index, string name, string label, float min, float max, float defaultValue) nothrow @nogc
    {
        super(index, name, label, min, max, defaultValue);
    }

    override double toNormalized(double value)
    {
        return clampValue!double( (value - _min) / (_max - _min), 0.0, 1.0);
    }

    override double fromNormalized(double normalizedValue)
    {
        return clampValue!double(_min + (_max - _min) * normalizedValue, _min, _max);
    }
}

/// Float parameter following an exponential type of mapping (eg: cutoff frequency)
class LogFloatParameter : FloatParameter
{
    this(int index, string name, string label, double min, double max, double defaultValue) nothrow @nogc
    {
        assert(min > 0 && max > 0);
        super(index, name, label, min, max, defaultValue);
    }

    override double toNormalized(double value)
    {
        double result = log(value / _min) / log(_max / _min);
        if (result < 0)
            result = 0;
        if (result > 1)
            result = 1;
        return result;
    }

    override double fromNormalized(double normalizedValue)
    {
        return _min * exp(normalizedValue * log(_max / _min));
    }
}

/// A parameter with [-inf to value] dB log mapping
class GainParameter : FloatParameter
{
    this(int index, string name, double max, double defaultValue, double shape = 2.0) nothrow @nogc
    {
        super(index, name, "dB", -double.infinity, max, defaultValue);
        _shape = shape;
        setDecimalPrecision(1);
    }

    override double toNormalized(double value)
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

    override double fromNormalized(double normalizedValue)
    {
        return floatToDeciBel(  (normalizedValue ^^ _shape) * deciBelToFloat(_max));
    }

private:
    double _shape;
}

/// Float parameter following a x^N type mapping (eg: something that doesn't fit in the other categories)
class PowFloatParameter : FloatParameter
{
    this(int index, string name, string label, double min, double max, double defaultValue, double shape) nothrow @nogc
    {
        super(index, name, label, min, max, defaultValue);
        _shape = shape;
    }

    override double toNormalized(double value)
    {
        double result = clampValue!double( (value - _min) / (_max - _min), 0.0, 1.0) ^^ (1 / _shape);
        assert(result >= 0 && result <= 1);
        return result;
    }

    override double fromNormalized(double normalizedValue)
    {
        double v = _min + (normalizedValue ^^ _shape) * (_max - _min);
        return clampValue!double(v, _min, _max);
    }

private:
    double _shape;
}
