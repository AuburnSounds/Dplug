/**
* PBR widget: bargraph.
*
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.bargraph;

import core.atomic;
import std.math;

import dplug.gui.element;
import dplug.core.sync;
import dplug.core.math;
import std.algorithm.comparison: clamp;

// Vertical bargraphs made of LEDs
class UIBargraph : UIElement
{
public:
nothrow:
@nogc:

    struct LED
    {
        RGBA diffuse;
    }

    /// Creates a new bargraph.
    /// [minValue .. maxValue] is the interval of values that will span [0..1] once remapped.
    this(UIContext context, int numChannels, float minValue, float maxValue,
         int redLeds = 0, int orangeLeds = 3, int yellowLeds = 0, int magentaLeds = 9)
    {
        super(context);

        _values = mallocSliceNoInit!float(numChannels);
        _values[] = 0;

        _minValue = minValue;
        _maxValue = maxValue;

        _leds = makeVec!LED();

        foreach (i; 0..redLeds)
            _leds.pushBack( LED(RGBA(255, 32, 0, 255)) );

        foreach (i; 0..orangeLeds)
            _leds.pushBack( LED(RGBA(255, 128, 64, 255)) );

        foreach (i; 0..yellowLeds)
            _leds.pushBack( LED(RGBA(255, 255, 64, 255)) );

        foreach (i; 0..magentaLeds)
            _leds.pushBack( LED(RGBA(226, 120, 249, 255)) );

         _valueMutex = makeMutex();
    }

    ~this()
    {
        _values.freeSlice();
    }


    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        int numLeds = cast(int)_leds.length;
        int numChannels = cast(int)_values.length;
        int width = _position.width;
        int height = _position.height;
        float border = width * 0.06f;

        box2f available = box2f(border, border, width - border, height - border);

        float heightPerLed = cast(float)(available.height) / cast(float)numLeds;
        float widthPerLed = cast(float)(available.width) / cast(float)numChannels;

        float tolerance = 1.0f / numLeds;

        foreach(channel; 0..numChannels)
        {
            float value = getValue(channel);
            float x0 = border + widthPerLed * (channel + 0.15f);
            float x1 = x0 + widthPerLed * 0.7f;

            foreach(i; 0..numLeds)
            {
                float y0 = border + heightPerLed * (i + 0.1f);
                float y1 = y0 + heightPerLed * 0.8f;

                depthMap.aaFillRectFloat!false(x0, y0, x1, y1, L16(16000));

                float ratio = 1 - i / cast(float)(numLeds - 1);

                ubyte shininess = cast(ubyte)(0.5f + 160.0f * (1 - smoothStep(value - tolerance, value, ratio)));

                RGBA color = _leds[i].diffuse;
                color.r = (color.r * (255 + shininess) + 255) / 510;
                color.g = (color.g * (255 + shininess) + 255) / 510;
                color.b = (color.b * (255 + shininess) + 255) / 510;
                color.a = shininess;
                diffuseMap.aaFillRectFloat!false(x0, y0, x1, y1, color);

                materialMap.aaFillRectFloat!false(x0, y0, x1, y1, RGBA(0, 128, 255, 255));

            }
        }
    }

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        bool wasChanged = cas(&_valuesUpdated, true, false);
        if (wasChanged)
        {
            setDirtyWhole();
        }
    }

    // To be called by audio thread. So this function cannot call setDirtyWhole directly.
    void setValues(const(float)[] values) nothrow @nogc
    {
        {
            _valueMutex.lock();
            assert(values.length == _values.length);

            // remap all values
            foreach(i; 0..values.length)
            {
                _values[i] = linmap!float(values[i], _minValue, _maxValue, 0, 1);
                _values[i] = clamp!float(_values[i], 0, 1);
            }
            _valueMutex.unlock();
        }
        atomicStore(_valuesUpdated, true);
    }

    float getValue(int channel) nothrow @nogc
    {
        float res = void;
        _valueMutex.lock();
        res = _values[channel];
        _valueMutex.unlock();
        return res;
    }

protected:

    Vec!LED _leds;

    UncheckedMutex _valueMutex;
    float[] _values;
    float _minValue;
    float _maxValue;

    shared(bool) _valuesUpdated = true;
}
