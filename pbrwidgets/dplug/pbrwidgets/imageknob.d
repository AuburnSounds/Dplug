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

import gamut;
// Note about gamut: would be way easier to use if there was a way to copy a single channel from another image,
// to fill a single channel with 255, to resize from an image to another, to easily crop a rectangle.
// FUTURE: ABDME_8 shall disappear.
nothrow:
@nogc:

enum KnobImageType
{
    /// Legacy KnobImage format.
    ABDME_8, 

    /// New KnobImage format.
    BADAMAEEE_16
}

/// Type of image being used for Knob graphics.
/// It used to be a one level deep Mipmap (ie. a flat image with sampling capabilities).
/// It is now a regular `OwnedImage` since it is resized in `reflow()`.
/// Use it an opaque type: its definition can change.
class KnobImage
{
nothrow @nogc:
    /// Type of KnobImage.
    KnobImageType type;    

    /// A gamut image, must be RGBA, can be 8-bit or 16-bit.
    Image image;

    bool isLegacy()
    {
        return type == KnobImageType.ABDME_8;
    }
}

/// Loads a knob image and rearrange channels to be fit to pass to `UIImageKnob`.
/// Warning: the returned `KnobImage` should be destroyed by the caller with `destroyFree`.
/// Note: internal resizing does not preserve aspect ratio exactly for 
///       approximate scaled rectangles.
///
/// # ABDME_8 format (legacy 8-bit depth knobs)
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
/// This format is extended so that:
/// - the emissive component is copied into the diffuse channel to form a full RGBA quad,
/// - same for material with the physical channel, which is assumed to be always "full physical"
///
/// Recommended format: PNG, for example a 230x46 24-bit image.
/// Note that such an image is formatted and resized in `reflow` before use.
///
///
/// # BADAMAEEE_16 format (new 16-bit depth + more alpha channels)
///
///           h           h            h                h
///   +------------+------------+------------+------------------------+
///   |            |            |            |                        |
///   |  basecolor |   depth    |  material  | emissive           (R) |
/// h |    RGB     | (G used)   |    RMS     | + emissive hovered (G) |
///   |     +      |     +      |     +      | + emissive dragged (B) |
///   |   alpha    |   alpha    |   alpha    | (no alpha)             |
///   +------------+------------+------------+------------------------+
///
/// Recommended format: QOIX, for example a 512x128 16-bit QOIX image.
/// Note that such an image is formatted and resized in `reflow` before use.
///
/// 8-bit images are considered ABDME_8, and 16-bit images are considered BADAMAEEE_16.
KnobImage loadKnobImage(in void[] data)
{
    // If the input image is 8-bit, this is assumed to be in ABDME_8 format.
    // Else this is assumed to be in BADAMAEEE_16 format.
    KnobImage res = mallocNew!KnobImage;
    res.image.loadFromMemory(data, LOAD_RGB | LOAD_ALPHA); // Force RGB and Alpha channel.
    if (res.image.isError)
    {
        return null;
    }

    if (res.image.isFP32())
        res.image.convertTo16Bit();

    res.type = res.image.is8Bit() ? KnobImageType.ABDME_8 : KnobImageType.BADAMAEEE_16;

    if (res.type == KnobImageType.ABDME_8)
    {
        assert(res.image.type == PixelType.rgba8);

        // Expected dimension is 5H x H
        assert(res.image.width == res.image.height * 5);

        int h = res.image.height;
    
        for (int y = 0; y < h; ++y)
        {
            RGBA[] line = cast(RGBA[]) res.image.scanline(y);

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
    }
    else
    {
        assert(res.image.type == PixelType.rgba16);

        // Expected dimension is 4H x H
        assert(res.image.width == res.image.height * 4);

        // No preprocessing in this case.
    }

    return res;
}


/// UIKnob which replace the knob part by a rotated PBR image.
class UIImageKnob : UIKnob
{
public:
nothrow:
@nogc:

    /// If `true`, diffuse data is blended in the diffuse map using alpha information.
    /// If `false`, diffuse is left untouched.
    @ScriptProperty bool drawToDiffuse = true;

    /// If `true`, depth data is blended in the depth map using alpha information.
    /// If `false`, depth is left untouched.
    @ScriptProperty bool drawToDepth = true;

    /// If `true`, material data is blended in the material map using alpha information.
    /// If `false`, material is left untouched.
    @ScriptProperty bool drawToMaterial = true;

    /// Amount of static emissive energy to the Emissive channel.
    @ScriptProperty ubyte emissive = 0;

    /// Amount of static emissive energy to add when mouse is over, but not dragging.
    @ScriptProperty ubyte emissiveHovered = 0;

    /// Amount of static emissive energy to add when mouse is over, but not dragging.
    @ScriptProperty ubyte emissiveDragged = 0;

    /// `knobImage` should have been loaded with `loadKnobImage`.
    /// Warning: `knobImage` must outlive the knob, it is borrowed.
    this(UIContext context, KnobImage knobImage, Parameter parameter)
    {
        super(context, parameter);
        _knobImage = knobImage;

        _tempBuf = mallocNew!(OwnedImage!L16);
        _tempBufRGBA = mallocNew!(OwnedImage!RGBA);

        
        if (knobImage.isLegacy())
        {
            _alphaTexture = mallocNew!(Mipmap!L16);
        }
        else
        {
            _alphaTextureDiffuse = mallocNew!(Mipmap!L16);
            _alphaTextureMaterial = mallocNew!(Mipmap!L16);
            _alphaTextureDepth = mallocNew!(Mipmap!L16);
        }
        _depthTexture = mallocNew!(Mipmap!L16);
        _diffuseTexture = mallocNew!(Mipmap!RGBA);
        _materialTexture = mallocNew!(Mipmap!RGBA);
    }

    ~this()
    {
        _tempBuf.destroyFree();
        _tempBufRGBA.destroyFree();
        _alphaTexture.destroyFree();
        _alphaTextureDiffuse.destroyFree();
        _alphaTextureMaterial.destroyFree();
        _alphaTextureDepth.destroyFree();
        _depthTexture.destroyFree();
        _diffuseTexture.destroyFree();
        _materialTexture.destroyFree();
    }

    override void reflow()
    {
        int numTiles = _knobImage.type == KnobImageType.ABDME_8 ? 5 : 4;

        // This has been checked before in `loadKnobImage`.
        assert(_knobImage.image.width % numTiles == 0);
        int SH = _knobImage.image.width / numTiles;
        assert(_knobImage.image.height == SH);

        // Things are resized towards DW x DH textures.
        int DW = position.width;
        int DH = position.height; 

        _tempBuf.size(SH, SH);
        _tempBufRGBA.size(SH, SH);

        enum numMipLevels = 1;

        if (_knobImage.isLegacy())
            _alphaTexture.size(numMipLevels, DW, DH);
        else
        {
            _alphaTextureDiffuse.size(numMipLevels, DW, DH);
            _alphaTextureMaterial.size(numMipLevels, DW, DH);
            _alphaTextureDepth.size(numMipLevels, DW, DH);
        }
        _depthTexture.size(numMipLevels, DW, DH);
        _diffuseTexture.size(numMipLevels, DW, DH);
        _materialTexture.size(numMipLevels, DW, DH);

        auto resizer = context.globalImageResizer;

        // 1. Fill the alpha textures.
        if (_knobImage.isLegacy())
        {
            // Extends alpha to 16-bit, resize it to destination size in _alphaTexture.
            ImageRef!L16 tempAlpha = _tempBuf.toRef();
            ImageRef!L16 destAlpha = _alphaTexture.levels[0].toRef;
            for (int y = 0; y < SH; ++y)
            {
                ubyte* scan = cast(ubyte*)(_knobImage.image.scanptr(y));
                for (int x = 0; x < SH; ++x)
                {
                    ushort alpha16 = scan[4*x] * 257; // take red channel as alpha
                    tempAlpha[x, y] = L16(alpha16);
                }
            }
            resizer.resizeImageGeneric(tempAlpha, destAlpha);
        }
        else
        {
            ImageRef!L16 tempAlpha = _tempBuf.toRef();

            // Take alpha from a rgba16 image, with a source offset.
            void convertAndResizeAlpha(ImageRef!L16 dest, 
                                       ref const(Image) src, 
                                       int srcXoffset)
            {
                for (int y = 0; y < SH; ++y)
                {
                    ushort* scan = cast(ushort*)(src.scanptr(y)) + srcXoffset*4; 
                    for (int x = 0; x < SH; ++x)
                    {
                        tempAlpha[x, y] = L16(scan[4*x+3]);
                    }
                }
                resizer.resizeImageGeneric(tempAlpha, dest);
            }
            convertAndResizeAlpha(_alphaTextureDiffuse.levels[0].toRef,  _knobImage.image, 0);
            convertAndResizeAlpha(_alphaTextureDepth.levels[0].toRef,    _knobImage.image, SH);
            convertAndResizeAlpha(_alphaTextureMaterial.levels[0].toRef, _knobImage.image, SH*2);
        }

        // 2. Fill the depth texture.        
        {
            ImageRef!L16 tempDepth = _tempBuf.toRef();
            ImageRef!L16 destDepth = _depthTexture.levels[0].toRef;
            for (int y = 0; y < SH; ++y)
            {
                L16* outScan = tempDepth.scanline(y).ptr;

                if (_knobImage.isLegacy())
                {
                    ubyte* scan = cast(ubyte*)(_knobImage.image.scanptr(y)) + SH * 4 * 2; // take depth rectangle

                    // Extends depth to 16-bit, resize it to destination size in _depthTexture.
                    for (int x = 0; x < SH; ++x)
                    {
                        ushort depth = cast(ushort)(0.5f + (257 * (scan[4*x] + scan[4*x+1] + scan[4*x+2]) / 3.0f));
                        outScan[x] = L16(depth);
                    }                   
                }
                else
                {   
                    // Depth is already 16-bit, take green channel.
                    ushort* scan = cast(ushort*)(_knobImage.image.scanptr(y)) + SH*4; // take depth rectangle
                    for (int x = 0; x < SH; ++x)
                    {
                        ushort sample = scan[x*4 + 1]; // Copy green channel
                        outScan[x] = L16(sample);
                    }
                }
            }

            // Note: different resampling kernal for depth, to smooth it. 
            //       Slightly more serene to look at.
            resizer.resizeImageDepth(tempDepth, destDepth); 
        }

        void prepareDiffuseMaterialTexture(int offsetX, ImageRef!RGBA outResizedRGBAImage)
        {
            for (int y = 0; y < SH; ++y)
            {
                if (_knobImage.isLegacy())
                {                
                    RGBA* scan = cast(RGBA*)(_knobImage.image.scanptr(y)) + SH*offsetX;
                    for (int x = 0; x < SH; ++x)
                    {
                        _tempBufRGBA[x, y] = scan[x];
                    }
                }
                else
                {
                    ushort* scan = cast(ushort*)(_knobImage.image.scanptr(y)) + 4*SH*offsetX;
                    for (int x = 0; x < SH; ++x)
                    {
                        // From 16-bit to 8-bit                    
                        RGBA rgba;
                        rgba.r = cast(ubyte)(0.5f + scan[4*x+0] * 0.00389105058f);
                        rgba.g = cast(ubyte)(0.5f + scan[4*x+1] * 0.00389105058f);
                        rgba.b = cast(ubyte)(0.5f + scan[4*x+2] * 0.00389105058f);
                        rgba.a = cast(ubyte)(0.5f + scan[4*x+3] * 0.00389105058f); 

                        // Note: put whatever as last channel, alpha is separated anyway
                        _tempBufRGBA[x, y] = rgba;
                    }             
                }
            }
            resizer.resizeImageDiffuse(_tempBufRGBA.toRef, outResizedRGBAImage);
        }

        // 3. Prepare the diffuse texture.
        // Resize diffuse+emissive in _diffuseTexture. Note that emissive channel was fed before.
        // Or, in non-legcay, emissive channel will contain garbage.
        int diffuseRect = _knobImage.isLegacy() ? 1 : 0;
        prepareDiffuseMaterialTexture(diffuseRect, _diffuseTexture.levels[0].toRef);

        // 4. Similarly, prepare material in _materialTexture.
        // 4th channel contain garbage.
        int materialRect = _knobImage.isLegacy() ? 3 : 2;
        prepareDiffuseMaterialTexture(materialRect, _materialTexture.levels[0].toRef);
    }

    override void drawKnob(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        float radius = getRadius();
        vec2f center = getCenter();
        float valueAngle = getValueAngle() + PI_2;
        float cosa = cos(valueAngle);
        float sina = sin(valueAngle);

        int W = position.width;
        int H = position.height; 

        // Note: slightly incorrect, since our resize in reflow doesn't exactly preserve aspect-ratio
        vec2f rotate(vec2f v) pure nothrow @nogc
        {
            return vec2f(v.x * cosa + v.y * sina, 
                         v.y * cosa - v.x * sina);
        }

        int emissiveOffset = emissive;
        if (isDragged)
            emissiveOffset = emissiveDragged;
        else if (isMouseOver)
            emissiveOffset = emissiveHovered;

        foreach(dirtyRect; dirtyRects)
        {
            ImageRef!RGBA cDiffuse  = diffuseMap.cropImageRef(dirtyRect);
            ImageRef!RGBA cMaterial = materialMap.cropImageRef(dirtyRect);
            ImageRef!L16 cDepth     = depthMap.cropImageRef(dirtyRect);

            // Basically we'll find a coordinate in the knob image for each pixel in the dirtyRect 

            // source center 
            vec2f sourceCenter = vec2f(W*0.5f, H*0.5f);

            bool legacy = _knobImage.isLegacy();

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
                    float fAlphaDiffuse  = 0.0f;
                    float fAlphaDepth    = 0.0f;
                    float fAlphaMaterial = 0.0f;

                    if ( (sourcePos.x >= 0.5f) && (sourcePos.x < (H - 0.5f))
                     &&  (sourcePos.y >=  0.5f) && (sourcePos.y < (H - 0.5f)) )
                    {
                        // PERF: sample a single RGBA L16 mipmap once in non-legacy mode

                        
                        if (legacy)
                        {
                            fAlphaDiffuse = _alphaTexture.linearSample(0, sourcePos.x, sourcePos.y);
                            fAlphaDepth = fAlphaDiffuse;
                            fAlphaMaterial = fAlphaDiffuse;
                        }
                        else
                        {
                            fAlphaDiffuse  = _alphaTextureDiffuse.linearSample(0, sourcePos.x, sourcePos.y);
                            fAlphaDepth    = _alphaTextureDepth.linearSample(0, sourcePos.x, sourcePos.y);
                            fAlphaMaterial = _alphaTextureMaterial.linearSample(0, sourcePos.x, sourcePos.y);
                        }

                        if (fAlphaDiffuse > 0)
                        {
                            ubyte alpha = cast(ubyte)(0.5f + fAlphaDiffuse / 257.0f);

                            if (drawToDiffuse)
                            {
                                vec4f fDiffuse  =  _diffuseTexture.linearSample(0, sourcePos.x, sourcePos.y);
                                ubyte R = cast(ubyte)(0.5f + fDiffuse.r);
                                ubyte G = cast(ubyte)(0.5f + fDiffuse.g);
                                ubyte B = cast(ubyte)(0.5f + fDiffuse.b);
                                int E = cast(ubyte)(0.5f + fDiffuse.a + emissiveOffset);
                                if (E < 0) E = 0; 
                                if (E > 255) E = 255;

                                if (!legacy)
                                    E = 0;

                                // TODO: non-legacy emissive?

                                RGBA diffuse = RGBA(R, G, B, cast(ubyte)E);
                                outDiffuse[x] = blendColor( diffuse, outDiffuse[x], alpha);
                            }
                        }

                        
                        if (fAlphaMaterial > 0)
                        {
                            ubyte alpha = cast(ubyte)(0.5f + fAlphaMaterial / 257.0f);

                            if (drawToMaterial)
                            {
                                vec4f fMaterial = _materialTexture.linearSample(0, sourcePos.x, sourcePos.y);
                                ubyte Ro = cast(ubyte)(0.5f + fMaterial.r);
                                ubyte M = cast(ubyte)(0.5f + fMaterial.g);
                                ubyte S = cast(ubyte)(0.5f + fMaterial.b);
                                ubyte X = cast(ubyte)(0.5f + fMaterial.a);
                                RGBA material = RGBA(Ro, M, S, X);
                                outMaterial[x] = blendColor( material, outMaterial[x], alpha);
                            }
                        }

                        if (fAlphaDepth > 0)
                        {
                            if (drawToDepth)
                            {
                                fAlphaDepth *= 0.00001525902f; // 1 / 65535
                                float fDepth    =    _depthTexture.linearSample(0, sourcePos.x, sourcePos.y);
                                float interpDepth = fDepth * fAlphaDepth + outDepth[x].l * (1.0f - fAlphaDepth);
                                outDepth[x] = L16(cast(ushort)(0.5f + interpDepth) );
                            }
                        }
                    }
                }
            }
        }
    }

    KnobImage _knobImage; // borrowed image of the knob

    OwnedImage!L16 _tempBuf; // used for augmenting bitdepth of alpha and depth
    OwnedImage!RGBA _tempBufRGBA; // used for lessening bitdepth of material and diffuse

    // <Only used in BADAMAEEE_16 format>
    Mipmap!L16 _alphaTextureDiffuse;   // owned 1-level image of alpha
    Mipmap!L16 _alphaTextureMaterial;  // owned 1-level image of alpha
    Mipmap!L16 _alphaTextureDepth;    // owned 1-level image of alpha
    // </Only used in BADAMAEEE_16 format>

    // <Only used in ABDME_8 format>
    Mipmap!L16 _alphaTexture;         // owned 1-level image of alpha
    // </Only used in ABDME_8 format>

    Mipmap!L16 _depthTexture; // owned 1-level image of depth
    Mipmap!RGBA _diffuseTexture; // owned 1-level image of diffuse+emissive RGBE
    Mipmap!RGBA _materialTexture; // owned 1-level image of material
}

