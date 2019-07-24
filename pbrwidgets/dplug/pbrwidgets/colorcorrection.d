/**
Color-correction post-effect.
This is a widget intended to correct colors before display, at the Raw level.

Copyright: Guillaume Piolat 2018.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.pbrwidgets.colorcorrection;


import gfm.math.matrix;

import dplug.core.math;
import dplug.gui.element;

/// FlatBackgroundGUI provides a background that is loaded from a PNG or JPEG
/// image. The string for backgroundPath should be in "stringImportPaths"
/// specified in dub.json
class UIColorCorrection : UIElement
{
public:
nothrow:
@nogc:

    this(UIContext context)
    {
        super(context, flagRaw);

        _tableArea.reallocBuffer(256 * 3, 32);
        _redTransferTable = _tableArea.ptr;
        _greenTransferTable = _tableArea.ptr + 256;
        _blueTransferTable = _tableArea.ptr + 512;

        // Set identity tables
        foreach(i; 0..256)
        {
            _redTransferTable[i] = cast(ubyte)i;
            _greenTransferTable[i] = cast(ubyte)i;
            _blueTransferTable[i] = cast(ubyte)i;
        }
    }

    ~this()
    {
        _tableArea.reallocBuffer(0, 32);
    }

    /// Calling this setup color correction table, with the well
    /// known lift-gamma-gain formula.
    void setLiftGammaGainContrast(float lift = 0.0f, float gamma = 1.0f, float gain = 1.0f, float contrast = 0.0f)
    {
        setLiftGammaGainContrastRGB(lift, gamma, gain, contrast,
                                    lift, gamma, gain, contrast,
                                    lift, gamma, gain, contrast);
    }

    /// Calling this setup color correction table, with the well
    /// known lift-gamma-gain formula, per channel.
    void setLiftGammaGainRGB(float rLift = 0.0f, float rGamma = 1.0f, float rGain = 1.0f,
                             float gLift = 0.0f, float gGamma = 1.0f, float gGain = 1.0f,
                             float bLift = 0.0f, float bGamma = 1.0f, float bGain = 1.0f)
    {
        setLiftGammaGainContrastRGB(rLift, rGamma, rGain, 0.0f,
                                    gLift, gGamma, gGain, 0.0f,
                                    bLift, bGamma, bGain, 0.0f);
    }

    /// Calling this setup color correction table, with the less
    /// known lift-gamma-gain formula + contrast addition, per channel.
    void setLiftGammaGainContrastRGB(
                                     float rLift = 0.0f, float rGamma = 1.0f, float rGain = 1.0f, float rContrast = 0.0f,
                                     float gLift = 0.0f, float gGamma = 1.0f, float gGain = 1.0f, float gContrast = 0.0f,
                                     float bLift = 0.0f, float bGamma = 1.0f, float bGain = 1.0f, float bContrast = 0.0f)
    {
        static float safePow(float a, float b) nothrow @nogc
        {
            if (a < 0)
                a = 0;
            if (a > 1)
                a = 1;
            return a ^^ b;
        }

        for (int b = 0; b < 256; ++b)
        {
            float inp = b / 255.0f;
            float outR = rGain*(inp + rLift*(1-inp));
            float outG = gGain*(inp + gLift*(1-inp));
            float outB = bGain*(inp + bLift*(1-inp));

            outR = safePow(outR, 1.0f / rGamma );
            outG = safePow(outG, 1.0f / gGamma );
            outB = safePow(outB, 1.0f / bGamma );

            if (outR < 0)
                outR = 0;
            if (outG < 0)
                outG = 0;
            if (outB < 0)
                outB = 0;
            if (outR > 1)
                outR = 1;
            if (outG > 1)
                outG = 1;
            if (outB > 1)
                outB = 1;

            outR = lerp!float(outR, smoothStep!float(0, 1, outR), rContrast);
            outG = lerp!float(outG, smoothStep!float(0, 1, outG), gContrast);
            outB = lerp!float(outB, smoothStep!float(0, 1, outB), bContrast);

            _redTransferTable[b] = cast(ubyte)(0.5f + outR * 255.0f);
            _greenTransferTable[b] = cast(ubyte)(0.5f + outG * 255.0f);
            _blueTransferTable[b] = cast(ubyte)(0.5f + outB * 255.0f);
        }
        setDirtyWhole();
    }

    /// ditto
    void setLiftGammaGainContrastRGB(mat3x4f liftGammaGainContrast)
    {
        auto m = liftGammaGainContrast;
        setLiftGammaGainContrastRGB(m.c[0][0], m.c[0][1], m.c[0][2], m.c[0][3],
                                    m.c[1][0], m.c[1][1], m.c[1][2], m.c[1][3],
                                    m.c[2][0], m.c[2][1], m.c[2][2], m.c[2][3]);
    }
    
    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        foreach(dirtyRect; dirtyRects)
        {
            rawMap.cropImageRef(dirtyRect).applyColorCorrection(_redTransferTable);
        }
    }

    override bool contains(int x, int y)
    {
        // HACK: this is just a way to avoid taking mouseOver.
        // As this widget is often a top widget, 
        // this avoids capturing mouse instead 
        // of all below widgets.
        return false; 
    }


private:
    ubyte[] _tableArea = null;
    ubyte* _redTransferTable = null;
    ubyte* _greenTransferTable = null;
    ubyte* _blueTransferTable = null;
}

// Apply color correction and convert RGBA8 to BGRA8
void applyColorCorrection(ImageRef!RGBA image, const(ubyte*) rgbTable) pure nothrow @nogc
{
    int w = image.w;
    int h = image.h;
    for (int j = 0; j < h; ++j)
    {
        ubyte* scan = cast(ubyte*)image.scanline(j).ptr;
        for (int i = 0; i < w; ++i)
        {
            ubyte r = scan[4*i];
            ubyte g = scan[4*i+1];
            ubyte b = scan[4*i+2];
            scan[4*i]   = rgbTable[r];
            scan[4*i+1] = rgbTable[g+256];
            scan[4*i+2] = rgbTable[b+512];
        }
    }
}