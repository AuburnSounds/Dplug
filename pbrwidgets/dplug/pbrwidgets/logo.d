/**
Clickable Logo.

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.logo;

import std.math;
import dplug.gui.element;
import dplug.core.math;

class UILogo : UIElement
{
public:
nothrow:
@nogc:

    /// Change this to point to your website
    string targetURL = "http://example.com";
    float animationTimeConstant = 30.0f;
    ubyte defaultEmissive = 0; // emissive where the logo isn't

    // these are offset on top of defaultEmissive
    ubyte emissiveOn = 40;
    ubyte emissiveOff = 0;

    /// Note: once called, the logo now own the diffuse image, and will destroy it.
    this(UIContext context, OwnedImage!RGBA diffuseImage)
    {
        super(context, flagAnimated | flagPBR);
        _diffuseImage = diffuseImage;
        _animation = 0;
    }

    ~this()
    {
        _diffuseImage.destroyNoGC();
    }

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        float target = ( isDragged() || isMouseOver() ) ? 1 : 0;

        float newAnimation = lerp(_animation, target, 1.0 - exp(-dt * animationTimeConstant));

        if (abs(newAnimation - _animation) > 0.001f)
        {
            _animation = newAnimation;
            setDirtyWhole();
        }
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuseIn = _diffuseImage.crop(dirtyRect);
            auto croppedDiffuseOut = diffuseMap.crop(dirtyRect);

            int w = dirtyRect.width;
            int h = dirtyRect.height;

            ubyte emissive = cast(ubyte)(0.5f + lerp!float(emissiveOff, emissiveOn, _animation));

            for(int j = 0; j < h; ++j)
            {
                RGBA[] input = croppedDiffuseIn.scanline(j);
                RGBA[] output = croppedDiffuseOut.scanline(j);

                for(int i = 0; i < w; ++i)
                {
                    ubyte alpha = input[i].a;
                    RGBA color = RGBA.op!q{.blend(a, b, c)}(input[i], output[i], alpha);

                    // emissive has to be multiplied by alpha, and added to the default background emissive
                    color.a = cast(ubyte)( (128 + defaultEmissive * 256 + (emissive * color.a) ) >> 8);
                    output[i] = color;
                }
            }
        }
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        browseNoGC(targetURL);
        return true;
    }

private:
    float _animation;
    OwnedImage!RGBA _diffuseImage;
}
