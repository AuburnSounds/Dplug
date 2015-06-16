/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.toolkit.bargraph;

import std.math;
import dplug.gui.toolkit.element;
//import dplug.gui.drawex;
import dplug.plugin.unchecked_sync;

// Vertical bargraphs made of LEDs
class UIBargraph : UIElement
{
public:

    struct LED
    {
        RGBA diffuse;
    }

    this(UIContext context, int numChannels, int redLeds = 3, int orangeLeds = 3, int yellowLeds = 3, int greenLeds = 9)
    {
        super(context);

        _values.length = numChannels;
        _values[] = 0;

        foreach (i; 0..redLeds)
            _leds ~= LED(RGBA(255, 32, 0, 255));

        foreach (i; 0..orangeLeds)
            _leds ~= LED(RGBA(255, 128, 64, 255));

        foreach (i; 0..yellowLeds)
            _leds ~= LED(RGBA(255, 255, 64, 255));

        foreach (i; 0..greenLeds)
            _leds ~= LED(RGBA(32, 255, 16, 255));

         _valueMutex = new UncheckedMutex();
    }

    override void close()
    {
        _valueMutex.close();        
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i dirtyRect)
    {
        depthMap.fill(RGBA(59, 200, 0, 0));
        diffuseMap.fill(RGBA(64, 64, 64, 0));      

        int numLeds = cast(int)_leds.length;
        int numChannels = cast(int)_values.length;
        int width = _position.width;
        int height = _position.height;
        float border = width * 0.06f;

        box2f available = box2f(border, border, width - border, height - border);

        float heightPerLed = available.height / cast(float)numLeds;
        float widthPerLed = available.width / cast(float)numChannels;

        float tolerance = 1.0f / numLeds;

        foreach(channel; 0..numChannels)
        {
            foreach(i; 0..numLeds)
            {
                float x0 = available.min.x + widthPerLed * (channel + 0.15f);
                float x1 = x0 + widthPerLed * 0.7f;
                float y0 = available.min.y + heightPerLed * (i + 0.1f);
                float y1 = y0 + heightPerLed * 0.8f;

                depthMap.aaFillRect(x0, y0, x1, y1, RGBA(60, 255, 0, 0));

                float ratio = 1 - i / cast(float)(numLeds - 1);


                ubyte shininess = cast(ubyte)(0.5f + 255.0f * (1 - smoothStep(_values[channel] - tolerance, _values[channel] + tolerance, ratio)));

           /*     if (ratio > _values[channel])
                    shininess = 0;
                else 
                    shininess = 255;*/

                RGBA color = _leds[i].diffuse;
                color.r = (color.r * 255 + shininess) / 512;
                color.g = (color.g * 255 + shininess) / 512;
                color.b = (color.b * 255 + shininess) / 512;
                color.a = shininess;
                diffuseMap.aaFillRect(x0, y0, x1, y1, color);

            }
        }
    }

    void setValues(float[] values) nothrow @nogc
    {
        {
            _valueMutex.lock();
            scope(exit) _valueMutex.unlock();
            assert(values.length == _values.length);
            _values[] = values[]; // slice copy
        }
        setDirty();
    }

protected:
    LED[] _leds;

    UncheckedMutex _valueMutex;
    float[] _values;
}
