/**
A PBR knob with texture.

Copyright: Guillaume Piolat 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.pbrwidgets.imageknob;

import std.math;

import dplug.math.vector;
import dplug.math.box;

import dplug.core.nogc;
import dplug.gui.element;
import dplug.pbrwidgets.knob;
import dplug.client.params;

nothrow:
@nogc:


/// Type of image being used for Knob graphics.
/// It used to be a one level deep Mipmap (ie. a flat image with sampling capabilities).
/// It is now a regular `OwnedImage` since it is resized in `reflow()`.
/// Use it an opaque type: its definition can change.
alias KnobImage = OwnedImage!RGBA;

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
/// Note that such an image is formatted and resized in `reflow` before use.
///
/// Warning: the returned `KnobImage` should be destroyed by the caller with `destroyFree`.
/// Note: internal resizing does not preserve aspect ratio exactly for 
///       approximate scaled rectangles.
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
    return image;
}


/// UIKnob which replace the knob part by a rotated PBR image.
class UIImageKnob : UIKnob
{
public:
nothrow:
@nogc:

    /// If `true`, diffuse data is blended in the diffuse map using alpha information.
    /// If `false`, diffuse is left untouched.
    bool drawToDiffuse = true;

    /// If `true`, depth data is blended in the depth map using alpha information.
    /// If `false`, depth is left untouched.
    bool drawToDepth = true;

    /// If `true`, material data is blended in the material map using alpha information.
    /// If `false`, material is left untouched.
    bool drawToMaterial = true;

    /// `knobImage` should have been loaded with `loadKnobImage`.
    /// Warning: `knobImage` must outlive the knob, it is borrowed.
    this(UIContext context, KnobImage knobImage, FloatParameter parameter)
    {
        super(context, parameter);
        _knobImage = knobImage;

        _tempBuf = mallocNew!(OwnedImage!L16);
        _alphaTexture = mallocNew!(Mipmap!L16);
        _depthTexture = mallocNew!(Mipmap!L16);
        _diffuseTexture = mallocNew!(Mipmap!RGBA);
        _materialTexture = mallocNew!(Mipmap!RGBA);
    }

    ~this()
    {
        _tempBuf.destroyFree();
        _alphaTexture.destroyFree();
        _depthTexture.destroyFree();
        _diffuseTexture.destroyFree();
        _materialTexture.destroyFree();
    }

    override void reflow()
    {
        int numTiles = 5;

        // Limitation: the source _knobImage should be multiple of numTiles pixels.
        assert(_knobImage.w % numTiles == 0);
        int SH = _knobImage.w / numTiles;
        assert(_knobImage.h == SH); // Input image dimension should be: (numTiles x SH, SH)

        // Things are resized towards DW x DH textures.
        int DW = position.width;
        int DH = position.height; 
        //assert(DW == DH); // For now.

        _tempBuf.size(SH, SH);

        enum numMipLevels = 1;
        _alphaTexture.size(numMipLevels, DW, DH);
        _depthTexture.size(numMipLevels, DW, DH);
        _diffuseTexture.size(numMipLevels, DW, DH);
        _materialTexture.size(numMipLevels, DW, DH);

        auto resizer = context.globalImageResizer;

        // 1. Extends alpha to 16-bit, resize it to destination size in _alphaTexture.
        {
            ImageRef!RGBA srcAlpha =  _knobImage.toRef.cropImageRef(rectangle(0, 0, SH, SH));
            ImageRef!L16 tempAlpha = _tempBuf.toRef();
            ImageRef!L16 destAlpha = _alphaTexture.levels[0].toRef;
            for (int y = 0; y < SH; ++y)
            {
                for (int x = 0; x < SH; ++x)
                {
                    RGBA sample = srcAlpha[x, y];
                    ushort alpha16 = sample.r * 257;
                    tempAlpha[x, y] = L16(alpha16);
                }
            }
            resizer.resizeImageGeneric(tempAlpha, destAlpha);
        }

        // 2. Extends depth to 16-bit, resize it to destination size in _depthTexture.
        {
            ImageRef!RGBA srcDepth =  _knobImage.toRef.cropImageRef(rectangle(2*SH, 0, SH, SH));
            ImageRef!L16 tempDepth = _tempBuf.toRef();
            ImageRef!L16 destDepth = _depthTexture.levels[0].toRef;
            for (int y = 0; y < SH; ++y)
            {
                for (int x = 0; x < SH; ++x)
                {
                    RGBA sample = srcDepth[x, y];
                    ushort depth = cast(ushort)(0.5f + (257 * (sample.r + sample.g + sample.b) / 3.0f));
                    tempDepth[x, y] = L16(depth);
                }
            }

            // Note: different resampling kernal for depth, to smooth it. 
            //       Slightly more serene to look at.
            resizer.resizeImageDepth(tempDepth, destDepth); 
        }

        // 3. Resize diffuse+emissive in _diffuseTexture.
        {
            ImageRef!RGBA srcDiffuse =  _knobImage.toRef.cropImageRef(rectangle(SH, 0, SH, SH));
            ImageRef!RGBA destDiffuse = _diffuseTexture.levels[0].toRef;
            resizer.resizeImageDiffuse(srcDiffuse, destDiffuse);
        }

        // 4. Resize material in _materialTexture.
        {
            ImageRef!RGBA srcMaterial =  _knobImage.toRef.cropImageRef(rectangle(3*SH, 0, SH, SH));
            ImageRef!RGBA destMaterial = _materialTexture.levels[0].toRef;
            resizer.resizeImageMaterial(srcMaterial, destMaterial);
        }
    }


    override void drawKnob(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        float radius = getRadius();
        vec2f center = getCenter();
        float valueAngle = getValueAngle() + PI_2;
        float cosa = cos(valueAngle);
        float sina = sin(valueAngle);

        int w = _alphaTexture.width;
        int h = _alphaTexture.height;

        // Note: slightly incorrect, since our resize in reflow doesn't exactly preserve aspect-ratio
        vec2f rotate(vec2f v) pure nothrow @nogc
        {
            return vec2f(v.x * cosa + v.y * sina, 
                         v.y * cosa - v.x * sina);
        }

        foreach(dirtyRect; dirtyRects)
        {
            ImageRef!RGBA cDiffuse  = diffuseMap.cropImageRef(dirtyRect);
            ImageRef!RGBA cMaterial = materialMap.cropImageRef(dirtyRect);
            ImageRef!L16 cDepth     = depthMap.cropImageRef(dirtyRect);

            // Basically we'll find a coordinate in the knob image for each pixel in the dirtyRect 

            // source center 
            vec2f sourceCenter = vec2f(w*0.5f, h*0.5f);

            enum float renormDepth = 1.0 / 65535.0f;
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
                        fAlpha = _alphaTexture.linearSample(0, sourcePos.x, sourcePos.y);

                        if (fAlpha > 0)
                        {
                            vec4f fDiffuse  =  _diffuseTexture.linearSample(0, sourcePos.x, sourcePos.y); 
                            float fDepth    =    _depthTexture.linearSample(0, sourcePos.x, sourcePos.y); 
                            vec4f fMaterial = _materialTexture.linearSample(0, sourcePos.x, sourcePos.y);

                            ubyte alpha = cast(ubyte)(0.5f + fAlpha / 257.0f);
                            ubyte R = cast(ubyte)(0.5f + fDiffuse.r);
                            ubyte G = cast(ubyte)(0.5f + fDiffuse.g);
                            ubyte B = cast(ubyte)(0.5f + fDiffuse.b);
                            ubyte E = cast(ubyte)(0.5f + fDiffuse.a);

                            ubyte Ro = cast(ubyte)(0.5f + fMaterial.r);
                            ubyte M = cast(ubyte)(0.5f + fMaterial.g);
                            ubyte S = cast(ubyte)(0.5f + fMaterial.b);
                            ubyte X = cast(ubyte)(0.5f + fMaterial.a);

                            ushort depth = cast(ushort)(0.5f + fDepth);

                            RGBA diffuse = RGBA(R, G, B, E);
                            RGBA material = RGBA(Ro, M, S, X);

                            if (drawToDiffuse)
                                outDiffuse[x] = blendColor( diffuse, outDiffuse[x], alpha);
                            if (drawToMaterial)
                                outMaterial[x] = blendColor( material, outMaterial[x], alpha);

                            if (drawToDepth)
                            {
                                int interpolatedDepth = depth * alpha + outDepth[x].l * (255 - alpha);
                                outDepth[x] = L16(cast(ushort)( (interpolatedDepth + 128) / 255));
                            }
                        }
                    }
                }
            }
        }
    }

    KnobImage _knobImage; // borrowed image of the knob

    OwnedImage!L16 _tempBuf; // used for augmenting bitdepth of alpha and depth
    Mipmap!L16 _alphaTexture; // owned 1-level image of alpha
    Mipmap!L16 _depthTexture; // owned 1-level image of depth
    Mipmap!RGBA _diffuseTexture; // owned 1-level image of diffuse+emissive RGBE
    Mipmap!RGBA _materialTexture; // owned 1-level image of material
}

