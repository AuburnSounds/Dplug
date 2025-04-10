/**
    Implement a gradient object, that holds a LUT.
    Copyright: Chris Jones 2020.
    Copyright: Guillaume Piolat 2018-2025.
    License:   http://www.boost.org/LICENSE_1_0.txt
*/
module dplug.canvas.gradient;

import dplug.core.nogc;
import dplug.core.vec;
import dplug.canvas.misc;
import dplug.graphics.color;

/**
    Gradient class.

    Nothing here is a public API, it's only internal to
    dplug:canvas.    
    
    A gradient owns:

      - a list of colours and positions (known as stops)
        along a single dimension from 0 to 1.
        The colors are a 32-bit RGBA quadruplet.

      - a look-up table of colors (LUT)
        indexed by blitters.
    
    It has a lookup table for the rasterizer, built lazily
    (was originally always 256 samples).

    FUTURE: size of look-up is dynamically choosen
*/
class Gradient
{
public:
nothrow:
@nogc:

    static struct ColorStop
    {
        uint  color;
        float pos;
    }

    /**
        Add a color stop.
    */
    void addStop(float pos, uint color)
    {
        m_stops.pushBack(ColorStop(color,clip(pos,0.0,1.0)));
        m_isOpaque = m_isOpaque && ((color >>> 24) == 0xFF);
        m_changed = true;
    }

    /**
        Reset things, have zero color stop.
        Invalidate look-up.
    */
    void reset()
    {
        m_stops.clearContents();
        m_changed = true;
        m_isOpaque = true;
    }

    /**
        Returns: Numnber of color stops in this gradient. 
    */
    size_t length()
    {
        return m_stops.length;
    }

    /**
        Get look-up length.
        This is invalidated in cases the color stops are 
        redone with `.reset` or `.addStop`.
    */
    int lutLength()
    {
        if (m_changed) initLookup();
        return cast(int)m_lookup.length;
    }

    /**
        Returns: Complete LUT, of size `lutLength()`.
    */
    uint[] getLookup()
    {
        if (m_changed) initLookup();
        return m_lookup[0..$];
    }

    /**
        Returns: `true` if the color stops have changed,
        and LUT would be recomputed at next `.getLookup()`.
    */
    bool hasChanged()
    {
        return m_changed;
    }

    /**
        Returns: `true` if gradient fully opaque.
    */
    bool isOpaque()
    {
        return m_isOpaque;
    }
    
private:

    int computeLUTSize()
    {
        // PERF: hash of color stops would allow to keep
        // the same LUT size.

        // heuristic to choose LUT size
        enum MIN_LUT_SIZE = 32;

        // haven't seen a meaningful enhancement beyond 1024
        enum MAX_LUT_SIZE = 1024; 

        int lutSize = MIN_LUT_SIZE;

        if (m_stops.length <= 1)
            return MIN_LUT_SIZE;
        else
        {
            foreach(size_t i; 1.. m_stops.length)
            {
                float t0 = m_stops[i-1].pos;
                float t1 = m_stops[i].pos;
                float tdiff = abs_float(t0 - t1);
                if (tdiff < 0.0005)
                    continue; // unlikely to make a difference

                uint s0 = m_stops[i-1].color;
                uint s1 = m_stops[i].color;
                RGBA c0 = *cast(RGBA*)(&s0);
                RGBA c1 = *cast(RGBA*)(&s1);

                // What's the maximum difference between those stops?
                int dr = abs_int(c0.r - c1.r);
                int dg = abs_int(c0.g - c1.g);
                int db = abs_int(c0.b - c1.b);
                int da = abs_int(c0.a - c1.a);

                int maxD = dr;
                if (maxD < dg) maxD = dg;
                if (maxD < db) maxD = db;
                if (maxD < da) maxD = da;

                // Approximate number of items to get small
                // difference of one level
                // VISUAL: add a factor there and tune it
                // Higher than 1.0 doesn't seem to make a 
                // different for now, FUTURE: test it again after
                // other enhancements.
                float n = maxD / tdiff;

                int ni = cast(int)n;
                if (ni > MAX_LUT_SIZE)
                {
                    ni = MAX_LUT_SIZE;
                }

                if (lutSize < ni)
                    lutSize = ni;
            }
            return lutSize;
        }
    }
    

    void initLookup()
    {
        sortStopsInPlace(m_stops[]);

        int lutSize = computeLUTSize();
        m_lookup.resize(lutSize);

        // PERF: we can skip a LUT table initialization if the
        // stops and LUT size are carefully hashed.

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
            int idx = cast(int) (m_stops[0].pos*lutSize);

            int colorStop0 = m_stops[0].color;
            for (int n = 0; n < idx; ++n)
            {
                m_lookup[n] = colorStop0;
            }

            foreach(size_t i; 1.. m_stops.length)
            {
                int next = cast(int) (m_stops[i].pos*lutSize);

                foreach(int j; idx..next)
                {
                    // VISUAL: this computation compute a stop with only 8-bit operands
                    // makes a difference?

                    enum bool integerGradient = false;

                    static if (integerGradient)
                    {
                        uint a = (256*(j-idx))/(next-idx);
                        uint c0 = m_stops[i-1].color;
                        uint c1 = m_stops[i].color;
                        uint t0 = (c0 & 0xFF00FF)*(256-a) + (c1 & 0xFF00FF)*a;
                        uint t1 = ((c0 >> 8) & 0xFF00FF)*(256-a) + ((c1 >> 8) & 0xFF00FF)*a;
                        m_lookup[j] = ((t0 >> 8) & 0xFF00FF) | (t1 & 0xFF00FF00);
                    }
                    else
                    {
                        // FUTURE: useful?
                        // This new one, doesn't look nicer, disabled
                        uint s0 = m_stops[i-1].color;
                        uint s1 = m_stops[i].color;
                        RGBA c0 = *cast(RGBA*)(&s0);
                        RGBA c1 = *cast(RGBA*)(&s1);
                        float fa = cast(float)(j-idx)/(next-idx);
                        float r = c0.r * (1.0f - fa) + c1.r * fa;
                        float g = c0.g * (1.0f - fa) + c1.g * fa;
                        float b = c0.b * (1.0f - fa) + c1.b * fa;
                        float a = c0.a * (1.0f - fa) + c1.a * fa;
                        RGBA res;
                        res.r = cast(ubyte)(0.5f + r);
                        res.g = cast(ubyte)(0.5f + g);
                        res.b = cast(ubyte)(0.5f + b);
                        res.a = cast(ubyte)(0.5f + a);
                        m_lookup[j] = *cast(int*)(&res);
                    }
                }
                idx = next;
            }

            int colorStopLast = m_stops[$-1].color;
            for (int n = idx; n < lutSize; ++n)
            {
                m_lookup[n] = m_stops[$-1].color;
            }
        }
        m_changed = false;
    }

    Vec!ColorStop m_stops;
    Vec!uint m_lookup;
    bool m_changed = true;
    bool m_isOpaque = true;

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

    static float abs_float(float a) pure
    {
        return a < 0 ? -a : a;
    }

    static int abs_int(int a) pure
    {
        return a < 0 ? -a : a;
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