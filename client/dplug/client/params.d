/*
Cockos WDL License

Copyright (C) 2005 - 2015 Cockos Incorporated
Copyright (C) 2015 and later Auburn Sounds

Portions copyright other contributors, see each source file for more
information.
This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose, including
commercial applications, and to alter it and redistribute it freely, subject to
the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim 
   that you wrote the original software. If you use this software in a product, 
   an acknowledgment in the product documentation would be appreciated but is 
   not required.
1. Altered source versions must be plainly marked as such, and must not be 
   misrepresented as being the original software.
1. This notice may not be removed or altered from any source distribution.
*/
/**
    Definitions of plug-in `Parameter`, and its many variants.
*/
module dplug.client.params;

import core.atomic;
import core.stdc.stdio;
import core.stdc.string;

import std.math: isNaN, log, exp, isFinite;

import dplug.core.math;
import dplug.core.sync;
import dplug.core.nogc;
import dplug.core.vec;
import dplug.core.string;
import dplug.client.client;

/// Parameter listeners are called whenever:
/// - a parameter is changed, 
/// - a parameter starts/stops being edited,
/// - a parameter starts/stops being hovered by mouse
///
/// Most common use case is for UI controls repaints (the `setDirtyXXX` calls)
interface IParameterListener
{
nothrow:
@nogc:

    /// A parameter value was changed, from the UI or the host (automation).
    ///
    /// Suggestion: Maybe call `setDirtyWhole()`/`setDirty()` in it to request
    ///             a graphic repaint.
    ///
    /// WARNING: this WILL be called from any thread, including the audio 
    ///          thread.
    void onParameterChanged(Parameter sender);

    /// A parameter value _starts_ being changed due to an UI element.
    void onBeginParameterEdit(Parameter sender);

    /// Called when a parameter value _stops_ being changed.
    void onEndParameterEdit(Parameter sender);

    /// Called when a widget that can changes this parameter is mouseover, and wants to signal
    /// that to the listeners.
    ///
    /// `onBeginParameterHover`/`onEndParameterHover` is called by widgets from an UI thread 
    /// (typically on `onMouseEnter`/`onMouseLeave`) when the mouse has entered a widget that 
    /// could change its parameter.
    ///
    /// It is useful be display the parameter value or related tooltips elsewhere in the UI,
    /// in another widget.
    ///
    /// To dispatch such messages to listeners, see `Parameter.
    ///
    /// Not all widgets will want to signal this though, for example a widget that handles plenty
    /// of Parameters will not want to signal them all the time.
    ///
    /// If `onBeginParameterHover` was ever called, then the same widget should also call 
    /// `onEndParameterHover` when sensible.
    void onBeginParameterHover(Parameter sender);
    ///ditto
    void onEndParameterHover(Parameter sender);
}



/// Plugin parameter.
/// Implement the Observer pattern for UI support.
/// Note: Recursive mutexes are needed here because `getNormalized()`
/// could need locking an already taken mutex.
///
/// Listener patter:
///     Every `Parameter` maintain a list of `IParameterListener`.
///     This is typically used by UI elements to update with parameters 
///     changes from all 
///     kinds of sources (UI itself, host automation...).
///     But they are not necessarily UI elements.
///
/// FUTURE: easier to make widget if every `Parameter` has a 
///         `setFromGUINormalized` call.
class Parameter
{
public:
nothrow:
@nogc:

    /// Adds a parameter listener.
    void addListener(IParameterListener listener)
    {
        _listeners.pushBack(listener);
    }

    /// Removes a parameter listener.
    void removeListener(IParameterListener listener)
    {
        int index = _listeners.indexOf(listener);
        if (index != -1)
            _listeners.removeAndReplaceByLastElement(index);
    }

    /// Returns: Parameters name. Displayed when the plug-in has no UI.
    string name() pure const
    {
        return _name;
    }

    /// Returns: Parameters unit label.
    string label() pure const
    {
        return _label;
    }

    /// Output name as a zero-terminated C string, truncate if needed.
    final void toNameN(char* p, int bufLength) const nothrow @nogc
    {
        snprintf(p, bufLength, "%.*s", cast(int)(_name.length), _name.ptr);
    }

    /// Output label as a zero-terminated C string, truncate if needed.
    final void toLabelN(char* p, int bufLength) const nothrow @nogc
    {
        snprintf(p, bufLength, "%.*s", cast(int)(_label.length), _label.ptr);
    }

    /// Returns: Index of parameter in the parameter list.
    int index() pure const
    {
        return _index;
    }

    /// Returns: Whether parameter is automatable.
    bool isAutomatable() pure const
    {
        return _isAutomatable;
    }

    /// Makes parameter non-automatable.
    Parameter nonAutomatable()
    {
        _isAutomatable = false;
        return this;
    }

    /// From a normalized double [0..1], set the parameter value.
    /// This is a Dplug internal call, not for plug-in code.
    void setFromHost(double hostValue)
    {
        // If edited by a widget, REFUSE host changes, since they could be
        // "in the past" and we know we want newer values anyway.
        if (isEdited())
            return; 

        setNormalized(hostValue);
        notifyListeners();
    }

    /// Returns: A normalized double [0..1], represents parameter value.
    /// This is a Dplug internal call, not for plug-in code.
    double getForHost()
    {
        return getNormalized();
    }

    /// Output a string representation of a `Parameter`.
    void toDisplayN(char* buffer, size_t numBytes)
    {
        toStringN(buffer, numBytes);
    }

    /// Warns the host that a parameter will be edited.
    /// Should only ever be called from the UI thread.
    void beginParamEdit()
    {
        atomicOp!"+="(_editCount, 1);
        _client.hostCommand().beginParamEdit(_index);
        foreach(listener; _listeners)
            listener.onBeginParameterEdit(this);
    }

    /// Warns the host that a parameter has finished being edited.
    /// Should only ever be called from the UI thread.
    void endParamEdit()
    {
        _client.hostCommand().endParamEdit(_index);
        foreach(listener; _listeners)
            listener.onEndParameterEdit(this);
        atomicOp!"-="(_editCount, 1);
    }

    /// Warns the listeners that a parameter is being hovered in the UI.
    /// Should only ever be called from the UI thread.
    ///
    /// This doesn't communicate anything to the host.
    ///
    /// Note: Widgets are not forced to signal this if they do not want other
    /// widgets to display a parameter value.
    void beginParamHover()
    {
        debug _hoverCount += 1;
        foreach(listener; _listeners)
            listener.onBeginParameterHover(this);
    }

    /// Warns the listeners that a parameter has finished being hovered in the UI.
    /// Should only ever be called from the UI thread.
    /// This doesn't communicate anything to the host.
    ///
    /// Note: Widgets are not forced to signal this if they do not want other
    /// widgets to display a parameter value. 
    /// 
    /// Warning: calls to `beginParamHover`/`endParamHover` must be balanced.
    void endParamHover()
    {
        foreach(listener; _listeners)
            listener.onEndParameterHover(this);
        debug _hoverCount -= 1;
    }

    /// Returns: A normalized double, representing the parameter value.
    abstract double getNormalized();

    /// Returns: A normalized double, representing the default parameter value.
    abstract double getNormalizedDefault();

    /// Returns: A string associated with the normalized value.
    abstract void stringFromNormalizedValue(double normalizedValue, 
                                            char* buffer, 
                                            size_t len);

    /// Returns: A normalized value associated with the string.
    abstract bool normalizedValueFromString(const(char)[] valueString, out double result);

    /// Returns: `true` if the parameters has only discrete values, `false` if continuous.
    abstract bool isDiscrete();

    ~this()
    {
        _valueMutex.destroy();

        // If you fail here, it means your calls to beginParamEdit and endParamEdit 
        // were not balanced correctly.
        debug assert(atomicLoad(_editCount) == 0);

        // If you fail here, it means your calls to beginParamHover and endParamHover
        // were not balanced correctly.
        debug assert(_hoverCount == 0);
    }

protected:

    this(int index, string name, string label)
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
    abstract void setNormalized(double hostValue);

    /// Display parameter (without label). This always adds a terminal zero within `numBytes`.
    abstract void toStringN(char* buffer, size_t numBytes);

    final void notifyListeners()
    {
        foreach(listener; _listeners)
            listener.onParameterChanged(this);
    }

    final void checkBeingEdited()
    {
        // If you fail here, you have changed the value of a Parameter from the UI
        // without enclosing within a pair of `beginParamEdit()`/`endParamEdit()`.
        // This will cause some hosts like Apple Logic not to record automation.
        //
        // When setting a Parameter from an UI widget, it's important to call `beginParamEdit()`
        // and `endParamEdit()` too.
        debug assert(isEdited());
    }

    final bool isEdited()
    {
        return atomicLoad(_editCount) > 0;
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
    /// Parameter is automatable by default.
    bool _isAutomatable = true;

    /// The list of active `IParameterListener` to receive parameter changes.
    Vec!IParameterListener _listeners;

    // Current number of calls into `beginParamEdit()`/`endParamEdit()` pair.
    // Only checked in debug mode.
    shared(int) _editCount = 0; // if > 0, the UI is editing this parameter

    // Current number of calls into `beginParamHover()`/`endParamHover()` pair.
    // Only checked in debug mode.
    debug int _hoverCount = 0;

    UncheckedMutex _valueMutex;
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
    override bool normalizedValueFromString(const(char)[] valueString, out double result)
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

    override bool isDiscrete() 
    {
        return true;
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

    /// Sets the value of the parameter from UI, using a normalized value.
    /// Note: If `normValue` is < 0.5, this is set to false.
    ///       If `normValue` is >= 0.5, this is set to true.
    final void setFromGUINormalized(double normValue) nothrow @nogc
    {
        assert(!isNaN(normValue));
        bool val = (normValue >= 0.5);
        setFromGUI(val);
    }

    /// Get current value.
    final bool value() nothrow @nogc
    {
        bool v = void;
        _valueMutex.lock();
        v = atomicLoad!(MemoryOrder.raw)(_value); // already sequenced by mutex locks
        _valueMutex.unlock();
        return v;
    }

    /// Get current value but doesn't use locking, using the `raw` memory order.
    /// Which might make it a better fit for the audio thread.
    /// The various `readParam!T` functions use that.²
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
        int clamped = defaultValue;
        if (clamped < min) 
            clamped = min;
        if (clamped > max) 
            clamped = max;
        _value = clamped;
        _defaultValue = clamped;
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

    override bool normalizedValueFromString(const(char)[] valueString, out double result)
    {
        if (valueString.length > 127)
            return false;

        // Because the input string is not zero-terminated
        char[128] buf;
        snprintf(buf.ptr, buf.length, "%.*s", cast(int)(valueString.length), valueString.ptr);

        bool err = false;
        int denorm = convertStringToInteger(buf.ptr, false, &err);
        if (err)
            return false;

        result = toNormalized(denorm);
        return true;
    }

    override bool isDiscrete() 
    {
        return true;
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

    /// Sets the parameter value from the UI thread.
    /// If the parameter is outside [min .. max] inclusive, then it is
    /// clamped. This is not an error to do so.
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

    /// Sets the value of the parameter from UI, using a normalized value.
    /// Note: If `normValue` is not inside [0.0 .. 1.0], then it is clamped.
    ///       This is not an error.
    final void setFromGUINormalized(double normValue) nothrow @nogc
    {
        assert(!isNaN(normValue));
        if (normValue < 0.0) normValue = 0.0;
        if (normValue > 1.0) normValue = 1.0;
        setFromGUI(fromNormalized(normValue));
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

    final int fromNormalized(double normalizedValue) nothrow @nogc
    {
        double mapped = _min + (_max - _min) * normalizedValue;

        // BUG slightly incorrect rounding, but lround is crashing
        int rounded;
        if (mapped >= 0)
            rounded = cast(int)(0.5f + mapped);
        else
            rounded = cast(int)(-0.5f + mapped);

        if (rounded < _min) 
            rounded = _min;
        if (rounded > _max)
            rounded = _max;
        return rounded;
    }

    final double toNormalized(int value) nothrow @nogc
    {
        double v = (cast(double)value - _min) / (_max - _min);
        if (v < 0.0)
            v = 0.0;
        if (v > 1.0)
            v = 1.0;
        return v;
    }

private:
    shared(int) _value;
    int _min;
    int _max;
    int _defaultValue;
}

class EnumParameter : IntegerParameter
{
public:
    this(int index, string name, const(string[]) possibleValues, int defaultValue = 0) nothrow @nogc
    {
        super(index, name, "", 0, cast(int)(possibleValues.length) - 1, defaultValue);

        // Duplicate all strings internally to avoid disappearing strings.
        _possibleValues.resize(possibleValues.length);
        foreach(size_t n, string label; possibleValues)
        {
            _possibleValues[n] = mallocDupZ(label);
        }
    }

    ~this()
    {
        foreach(size_t n, const(char)[] label; _possibleValues[])
        {
            freeSlice(cast(char[]) label); // const_cast
        }
    }

    override void toStringN(char* buffer, size_t numBytes)
    {
        int v = value();
        int toCopy = cast(int)(_possibleValues[v].length);
        int avail = cast(int)(numBytes) - 1;
        if (toCopy > avail)
            toCopy = avail;
        if (toCopy < 0)
            toCopy = 0;
        memcpy(buffer, _possibleValues[v].ptr, toCopy); // memcpy OK
        // add terminal zero
        if (numBytes > 0)
            buffer[toCopy] = '\0';
    }

    override void stringFromNormalizedValue(double normalizedValue, char* buffer, size_t len)
    {
        const(char[]) valueLabel = _possibleValues[ fromNormalized(normalizedValue) ];
        snprintf(buffer, len, "%.*s", cast(int)(valueLabel.length), valueLabel.ptr);
    }

    override bool normalizedValueFromString(const(char)[] valueString, out double result)
    {
        foreach(int i; 0..cast(int)(_possibleValues.length))
            if (_possibleValues[i] == valueString)
            {
                result = toNormalized(i);
                return true;
            }

        return false;
    }

    final const(char)[] getValueString(int n) nothrow @nogc
    {
        return _possibleValues[n];
    }

private:
    Vec!(char[]) _possibleValues;
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
        // What to do: get back to your `buildParameters` function and give a default 
        // in range of [min..max].
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

    /// Sets the value of the parameter from UI, using a normalized value.
    /// Note: If `normValue` is not inside [0.0 .. 1.0], then it is clamped.
    ///       This is not an error.
    final void setFromGUINormalized(double normValue) nothrow @nogc
    {
        assert(!isNaN(normValue));
        if (normValue < 0.0) normValue = 0.0;
        if (normValue > 1.0) normValue = 1.0;
        setFromGUI(fromNormalized(normValue));
    }

    /// Sets the number of decimal digits after the dot to be displayed.
    final void setDecimalPrecision(int digits) nothrow @nogc
    {
        assert(digits >= 0);
        assert(digits <= 9);
        _formatString[3] = cast(char)('0' + digits);
    }

    /// Helper for `setDecimalPrecision` that returns this, help when in parameter creation.
    final FloatParameter withDecimalPrecision(int digits) nothrow @nogc
    {
        setDecimalPrecision(digits);
        return this;
    }

    /// Sets the value of the parameter from UI, using a normalized value.
    /// Note: If `value` is not inside [min .. max], then it is clamped.
    ///       This is not an error.
    /// See_also: `setFromGUINormalized`
    final void setFromGUI(double value) nothrow @nogc
    {
        assert(!isNaN(value));

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

        // DigitalMars's snprintf doesn't always add a terminal zero
        version(DigitalMars)
            if (numBytes > 0)
            {
                buffer[numBytes-1] = '\0';
            }
    }

    override void stringFromNormalizedValue(double normalizedValue, char* buffer, size_t len)
    {
        double denorm = fromNormalized(normalizedValue);
        snprintf(buffer, len, _formatString.ptr, denorm);
    }

    override bool normalizedValueFromString(const(char)[] valueString, out double result)
    {
        if (valueString.length > 127) // ??? TODO doesn't bode well with VST3 constraints
            return false;

        // Because the input string is not necessarily zero-terminated
        char[128] buf;
        snprintf(buf.ptr, buf.length, "%.*s", cast(int)(valueString.length), valueString.ptr);

        bool err = false;
        double denorm = convertStringToDouble(buf.ptr, false, &err);
        if (err)
            return false; // didn't parse a double
        result = toNormalized(denorm);
        return true;
    }

    override bool isDiscrete() 
    {
        return false; // continous
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
        double v = (value - _min) / (_max - _min);
        if (v < 0.0)
            v = 0.0;
        if (v > 1.0)
            v = 1.0;
        return v;
    }

    override double fromNormalized(double normalizedValue)
    {
        double v = _min + (_max - _min) * normalizedValue;
        if (v < _min)
            v = _min;
        if (v > _max)
            v = _max;
        return v;
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
        double maxAmplitude = convertDecibelToLinearGain(_max);
        double result = ( convertDecibelToLinearGain(value) / maxAmplitude ) ^^ (1 / _shape);
        if (result < 0)
            result = 0;
        if (result > 1)
            result = 1;
        assert(isFinite(result));
        return result;
    }

    override double fromNormalized(double normalizedValue)
    {
        return convertLinearGainToDecibel(  (normalizedValue ^^ _shape) * convertDecibelToLinearGain(_max));
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
        double v = (value - _min) / (_max - _min);
        if (v < 0.0)
            v = 0.0;
        if (v > 1.0)
            v = 1.0;
        v = v ^^ (1 / _shape);

        // Note: It's not entirely impossible to imagine a particular way that 1 would be exceeded, since pow
        // is implemented with an exp approximation and a log approximation.
        // TODO: produce ill case in isolation to see
        assert(v >= 0 && v <= 1); // will still assert on NaN
        return v;
    }

    override double fromNormalized(double normalizedValue)
    {
        double v = _min + (normalizedValue ^^ _shape) * (_max - _min);
         if (v < _min)
            v = _min;
        if (v > _max)
            v = _max;
        return v;
    }

private:
    double _shape;
}
