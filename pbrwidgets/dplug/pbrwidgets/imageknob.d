/**
A PBR knob with texture.

Copyright: Guillaume Piolat 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.pbrwidgets.imageknob;

import std.math;

import gfm.math.vector;
import gfm.math.box;

import dplug.core.nogc;
import dplug.gui.context;
import dplug.pbrwidgets.knob;
import dplug.graphics.mipmap;
import dplug.client.params;
import dplug.graphics.color;
import dplug.graphics.image;
import dplug.graphics.draw;
import dplug.graphics.drawex;

nothrow:
@nogc:

// TODO: adapt on size, use mipmapping for reducing size.
//       KnobImage will need to be something else (several Mipmap?)

/// Type of image being used for Knob graphics.
/// It's actually a one level deep Mipmap (ie. a flat image with sampling capabilities).
/// Use it an opaque type: its definition can change.
alias KnobImage = Mipmap!RGBA;

/// Loads a knob image and rearrange channels to be fit to pass to `UIImageKnob`.
///
/// The input format of such an image is an an arrangement of squares:
///
///         h              h           h            h         h
///   +------------+------------+------------+------------+-----------+
///   |            |            |            |            |           |
///   |  alpha     |  basecolor |   depth    |  material  |  emissive |
/// h |  grayscale |     RGB    |  grayscale |    RMS     | grayscale |
///   |  (R used)  |            |(sum of RGB)|            | (R used)  |
///   |            |            |            |            |           |
///   +------------+------------+------------+------------+-----------+
///
///
/// This format is extended so that:
/// - the emissive component is copied into the diffuse channel to form a full RGBA quad,
/// - same for material with the physical channel, which is assumed to be always "full physical"
///
/// Recommended format: PNG, for example a 230x46 24-bit image.
///
/// Warning: the returned `KnobImage` should be destroyed by the caller with `destroyFree`.
KnobImage loadKnobImage(in void[] data)
{
    OwnedImage!RGBA image = loadOwnedImage(data);

    // Expected dimension is 5H x H
    assert(image.w == image.h * 5);

    int h = image.h;
    
    for (int y = 0; y < h; ++y)
    {
        RGBA[] line = image.scanline(y);

        RGBA[] basecolor = line[h..2*h];
        RGBA[] material = line[3*h..4*h];
        RGBA[] emissive = line[4*h..5*h];

        for (int x = 0; x < h; ++x)
        {
            // Put emissive red channel into the alpha channel of base color
            basecolor[x].a = emissive[x].r;

            // Fills unused with 255
            material[x].a = 255;
        }
    }   

    return mallocNew!(Mipmap!RGBA)(0, image);
}


/// UIKnob which replace the knob part by a rotated PBR image.
class UIImageKnob : UIKnob
{
public:
nothrow:
@nogc:

    /// `knobImage` should have been loaded with `loadKnobImage`.
    /// Warning: `knobImage` must outlive the knob, it is borrowed.
    this(UIContext context, KnobImage knobImage, FloatParameter parameter)
    {
        super(context, parameter);
        _knobImage = knobImage;
    }

    override void drawKnob(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        float radius = getRadius();
        vec2f center = getCenter();
        float valueAngle = getValueAngle() + PI_2;
        float cosa = cos(valueAngle);
        float sina = sin(valueAngle);

        int h = _knobImage.height;

        vec2f rotate(vec2f v) pure nothrow @nogc
        {
            return vec2f(v.x * cosa + v.y * sina, v.y * cosa - v.x * sina);
        }

        foreach(dirtyRect; dirtyRects)
        {
            auto cDiffuse = diffuseMap.crop(dirtyRect);
            auto cMaterial = materialMap.crop(dirtyRect);
            auto cDepth = depthMap.crop(dirtyRect);

            // Basically we'll find a coordinate in the knob image for each pixel in the dirtyRect 

            // source center 
            vec2f sourceCenter = vec2f(h*0.5f, h*0.5f);

            for (int y = 0; y < dirtyRect.height; ++y)
            {
                RGBA* outDiffuse = cDiffuse.scanline(y).ptr;
                L16* outDepth = cDepth.scanline(y).ptr;
                RGBA* outMaterial = cMaterial.scanline(y).ptr;

                for (int x = 0; x < dirtyRect.width; ++x)
                {
                    vec2f destPos = vec2f(x + dirtyRect.min.x, y + dirtyRect.min.y);
                    vec2f sourcePos = sourceCenter + rotate(destPos - center);

                    // If the point is outside the knobimage, it is considered to have an alpha of zero
                    float fAlpha = 0.0f;
                    if ( (sourcePos.x >= 0.5f) && (sourcePos.x < (h - 0.5f))
                     &&  (sourcePos.y >=  0.5f) && (sourcePos.y < (h - 0.5f)) )
                    {
                        fAlpha = _knobImage.linearSample(0, sourcePos.x, sourcePos.y).r;

                        if (fAlpha > 0)
                        {
                            vec4f fDiffuse = _knobImage.linearSample(0, sourcePos.x + h, sourcePos.y); 
                            vec4f fDepth = _knobImage.linearSample(0, sourcePos.x + h*2, sourcePos.y); 
                            vec4f fMaterial = _knobImage.linearSample(0, sourcePos.x + h*3, sourcePos.y);

                            ubyte alpha = cast(ubyte)(0.5f + fAlpha);
                            ubyte R = cast(ubyte)(0.5f + fDiffuse.r);
                            ubyte G = cast(ubyte)(0.5f + fDiffuse.g);
                            ubyte B = cast(ubyte)(0.5f + fDiffuse.b);
                            ubyte E = cast(ubyte)(0.5f + fDiffuse.a);

                            ubyte Ro = cast(ubyte)(0.5f + fMaterial.r);
                            ubyte M = cast(ubyte)(0.5f + fMaterial.g);
                            ubyte S = cast(ubyte)(0.5f + fMaterial.b);
                            ubyte X = cast(ubyte)(0.5f + fMaterial.a);

                            ushort depth = cast(ushort)(0.5f + 257 * (fDepth.r + fDepth.g + fDepth.b) / 3);

                            RGBA diffuse = RGBA(R, G, B, E);
                            RGBA material = RGBA(Ro, M, S, X);

                            outDiffuse[x] = blendColor( diffuse, outDiffuse[x], alpha);
                            outMaterial[x] = blendColor( material, outMaterial[x], alpha);

                            int interpolatedDepth = depth * alpha + outDepth[x].l * (255 - alpha);
                            outDepth[x] = L16(cast(ushort)( (interpolatedDepth + 128) / 255));
                        }
                    }
                }
            }
        }
    }

    KnobImage _knobImage; // borrowed image of the knob
}

