/**
* Implement the gradient class. dplug:canvas internals.
*
* Copyright: Copyright Chris Jones 2020.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.canvas.gradient;

import dplug.core.nogc;
import dplug.core.vec;
import dplug.canvas.misc;
import dplug.graphics.color;

/*
  Gradient class, 
  The gradient is defined as a list of colours and positions (known as stops) along
  a single dimension from 0 to 1. 
  It has a precomputed lookup table for the rasterizer, currently fixed at 256
  entries. Its a "just get it working for now" solution tbh
*/
class Gradient
{
nothrow:
@nogc:
    // colour is 32 bit ARGB, pos runs from 0..1 

    struct ColorStop
    {
        uint  color;
        float pos;
    }

    size_t length()
    {
        return m_stops.length;
    }

    bool hasChanged()
    {
        return m_changed;
    }

    void reset()
    {
        m_stops.clearContents();
        m_changed = true;
    }

    Gradient addStop(float pos, uint color)
    {
        m_stops.pushBack(ColorStop(color,clip(pos,0.0,1.0)));
        m_changed = true;
        return this;
    }

    uint[] getLookup()
    {
        if (m_changed) initLookup();
        return m_lookup[0..lookupLen];
    }

    int lutLength()
    {
        return lookupLen;
    }
    
private:
    
    // fixed size lookup for now, could probably have lookup tables cached
    // by the rasterizer rather than stuck in here/

    enum lookupLen = 256;

    void initLookup()
    {
        sortStopsInPlace(m_stops[]);

        if (m_stops.length == 0)
        {
            foreach(ref c; m_lookup) c = 0;
        }
        else if (m_stops.length == 1)
        {
            foreach(ref c; m_lookup) c = m_stops[0].color;
        }
        else
        {           
            int idx = cast(int) (m_stops[0].pos*lookupLen);
            m_lookup[0..idx] = m_stops[0].color;

            foreach(size_t i; 1.. m_stops.length)
            {
                int next = cast(int) (m_stops[i].pos*lookupLen);

                foreach(int j; idx..next)
                {
                    uint a = (256*(j-idx))/(next-idx);
                    uint c0 = m_stops[i-1].color;
                    uint c1 = m_stops[i].color;
                    uint t0 = (c0 & 0xFF00FF)*(256-a) + (c1 & 0xFF00FF)*a;
                    uint t1 = ((c0 >> 8) & 0xFF00FF)*(256-a) + ((c1 >> 8) & 0xFF00FF)*a;
                    m_lookup[j] = ((t0 >> 8) & 0xFF00FF) | (t1 & 0xFF00FF00);
                }
                idx = next;
            }
            m_lookup[idx..$] = m_stops[$-1].color;
        }
        m_changed = false;
    }

    Vec!ColorStop m_stops;
    uint[lookupLen] m_lookup;
    bool m_changed = true;

    static void sortStopsInPlace(ColorStop[] stops)
    {    
        size_t i = 1;
        while (i < stops.length)
        {
            size_t j = i;
            while (j > 0 && (stops[j-1].pos > stops[j].pos))
            {
                ColorStop tmp = stops[j-1];
                stops[j-1] = stops[j];
                stops[j] = tmp;
                j = j - 1;
            }
            i = i + 1;
        }
    }
}

unittest
{
    Gradient.ColorStop[3] stops = [Gradient.ColorStop(0xff0000, 1.0f),
                                   Gradient.ColorStop(0x00ff00, 0.4f),
                                   Gradient.ColorStop(0x0000ff, 0.0f)];
    Gradient.sortStopsInPlace(stops[]);
    assert(stops[0].pos == 0.0f);
    assert(stops[1].pos == 0.4f);
    assert(stops[2].pos == 1.0f);

    Gradient.sortStopsInPlace([]);
    Gradient.sortStopsInPlace(stops[0..1]);
}