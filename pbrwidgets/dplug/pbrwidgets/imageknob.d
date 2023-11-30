/**
A PBR knob with texture.

Copyright: Guillaume Piolat 2019.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.pbrwidgets.imageknob;

import std.math: PI_2, cos, sin;

import inteli.smmintrin;

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

// Removing this is NOT READY.
// See: https://github.com/AuburnSounds/Dplug/issues/791
// TODO put high-quality mipmaps in KnobImage, interpolate those.
version = KnobImage_resizedInternal;

enum KnobImageType
{
    /// Legacy KnobImage format.
    ABDME_8, 

    /// New KnobImage format.
    BADAMA_16
}

enum KnobInterpolationType
{
    linear, 
    cubic
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
/// # BADAMA_16 format (new 16-bit depth + more alpha channels)
///
///           h           h            h      
///   +------------+------------+------------+
///   |            |            |            |
///   |  basecolor |   depth    |  material  |
/// h |    RGB     | (G used)   |    RMS     |
///   |     +      |     +      |     +      |
///   |   alpha    |   alpha    |   alpha    |
///   +------------+------------+------------+
///
/// Recommended format: QOIX, for example a 512x128 16-bit QOIX image.
/// Note that such an image is formatted and resized in `reflow` before use.
///
/// 8-bit images are considered ABDME_8, and 16-bit images are considered BADAMA_16.
KnobImage loadKnobImage(in void[] data)
{
    // If the input image is 8-bit, this is assumed to be in ABDME_8 format.
    // Else this is assumed to be in BADAMA_16 format.
    KnobImage res = mallocNew!KnobImage;
    res.image.loadFromMemory(data, LOAD_RGB | LOAD_ALPHA); // Force RGB and Alpha channel.
    if (res.image.isError)
    {
        return null;
    }

    if (res.image.isFP32())
        res.image.convertTo16Bit();

    res.type = res.image.is8Bit() ? KnobImageType.ABDME_8 : KnobImageType.BADAMA_16;

    int h = res.image.height;

    if (res.type == KnobImageType.ABDME_8)
    {
        assert(res.image.type == PixelType.rgba8);

        // Expected dimension is 5H x H
        assert(res.image.width == res.image.height * 5);

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

        // Expected dimension is 3H x H
        assert(res.image.width == res.image.height * 3);

        // The whole image is alpha-premultiplied.
        for (int y = 0; y < h; ++y)
        {
            ushort[] scan = cast(ushort[]) res.image.scanline(y);
            for (int x = 0; x < 3*h; ++x)
            {
                uint R = scan[4*x+0];
                uint G = scan[4*x+1];
                uint B = scan[4*x+2];
                uint A = scan[4*x+3];
                R = (R * A + 32768) / 65535;
                G = (G * A + 32768) / 65535;
                B = (B * A + 32768) / 65535;
                scan[4 * x + 0] = cast(ushort)R;
                scan[4 * x + 1] = cast(ushort)G;
                scan[4 * x + 2] = cast(ushort)B;
                scan[4 * x + 3] = cast(ushort)A;
            }
        }
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

    /// Only used in non-legacy mode (BADAMA_16 format). The texture is oversampled on resize, so that rotated image is sharper.
    /// This costs more CPU and memory, for better visual results.
    /// But this is also dangerous and not always better! Try it on a big screen preferably.
    @ScriptProperty float oversampleTexture = 1.0f;

    /// Texture interpolaton used, only for non-legacy mode (BADAMA_16 format). Try it on a big screen preferably.
    @ScriptProperty KnobInterpolationType diffuseInterpolation = KnobInterpolationType.linear;

    ///ditto
    @ScriptProperty KnobInterpolationType depthInterpolation = KnobInterpolationType.linear;

    ///ditto
    @ScriptProperty KnobInterpolationType materialInterpolation = KnobInterpolationType.linear;

    /// `knobImage` should have been loaded with `loadKnobImage`.
    /// Warning: `knobImage` must outlive the knob, it is borrowed.
    this(UIContext context, KnobImage knobImage, Parameter parameter)
    {
        super(context, parameter);
        _knobImage = knobImage;
        
        if (knobImage.isLegacy())
        {
            _tempBuf = mallocNew!(OwnedImage!L16);
            _tempBufRGBA = mallocNew!(OwnedImage!RGBA);
            _alphaTexture = mallocNew!(Mipmap!L16);
            _depthTexture = mallocNew!(Mipmap!L16);
            _diffuseTexture = mallocNew!(Mipmap!RGBA);
            _materialTexture = mallocNew!(Mipmap!RGBA);
        }
        else
        {
            version(KnobImage_resizedInternal)
            {
                _resizedImage = mallocNew!(Mipmap!RGBA16);
            }
        }
    }

    ~this()
    {
        version(KnobImage_resizedInternal)
            _resizedImage.destroyFree();
        _tempBuf.destroyFree();
        _tempBufRGBA.destroyFree();
        _alphaTexture.destroyFree();
        _depthTexture.destroyFree();
        _diffuseTexture.destroyFree();
        _materialTexture.destroyFree();
    }


    enum numMipLevels = 1;

    override void reflow()
    {
        int numTiles = _knobImage.type == KnobImageType.ABDME_8 ? 5 : 3;

        // This has been checked before in `loadKnobImage`.
        assert(_knobImage.image.width % numTiles == 0);
        int SH = _knobImage.image.width / numTiles;
        assert(_knobImage.image.height == SH);

        auto resizer = context.globalImageResizer;

       
        if (_knobImage.isLegacy())
        {
            // Things are resized towards DW x DH textures.
            int DW = position.width;
            int DH = position.height; 

            _tempBuf.size(SH, SH);
            _tempBufRGBA.size(SH, SH);
            _alphaTexture.size(numMipLevels, DW, DH);
            _depthTexture.size(numMipLevels, DW, DH);
            _diffuseTexture.size(numMipLevels, DW, DH);
            _materialTexture.size(numMipLevels, DW, DH);

            // 1. Fill the alpha textures.
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
       
            // 2. Fill the depth texture.
            {
                ImageRef!L16 tempDepth = _tempBuf.toRef();
                ImageRef!L16 destDepth = _depthTexture.levels[0].toRef;
                for (int y = 0; y < SH; ++y)
                {
                    L16* outScan = tempDepth.scanline(y).ptr;

                    ubyte* scan = cast(ubyte*)(_knobImage.image.scanptr(y)) + SH * 4 * 2; // take depth rectangle

                    // Extends depth to 16-bit, resize it to destination size in _depthTexture.
                    for (int x = 0; x < SH; ++x)
                    {
                        ushort depth = cast(ushort)(0.5f + (257 * (scan[4*x] + scan[4*x+1] + scan[4*x+2]) / 3.0f));
                        outScan[x] = L16(depth);
                    }
                }

                // Note: different resampling kernal for depth, to smooth it. 
                //       Slightly more serene to look at.
                resizer.resizeImageDepth(tempDepth, destDepth); 
            }

            // 3. Prepare the diffuse texture.
            // Resize diffuse+emissive in _diffuseTexture. Note that emissive channel was fed before.


            void prepareDiffuseMaterialTexture(int offsetX, ImageRef!RGBA outResizedRGBAImage)
            {
                for (int y = 0; y < SH; ++y)
                {              
                    RGBA* scan = cast(RGBA*)(_knobImage.image.scanptr(y)) + SH*offsetX;
                    for (int x = 0; x < SH; ++x)
                    {
                        _tempBufRGBA[x, y] = scan[x]; // PERF: use the input image directly?
                    }
                }
                resizer.resizeImageDiffuse(_tempBufRGBA.toRef, outResizedRGBAImage);
            }

            int diffuseRect = _knobImage.isLegacy() ? 1 : 0;
            prepareDiffuseMaterialTexture(diffuseRect, _diffuseTexture.levels[0].toRef);

            // 4. Similarly, prepare material in _materialTexture.
            // 4th channel contain garbage.
            int materialRect = _knobImage.isLegacy() ? 3 : 2;
            prepareDiffuseMaterialTexture(materialRect, _materialTexture.levels[0].toRef);
        }
        else
        {
            version(KnobImage_resizedInternal)
            {
                lazyResizeBADAMA16(resizer);
            }
        }
    }

    version(KnobImage_resizedInternal)
    {

        void lazyResizeBADAMA16(ImageResizer* resizer)
        {
            // TODO: might as well keep the source pixel ratio
            int textureWidth = cast(int)(0.5f + oversampleTexture * position.width);
            int textureHeight = cast(int)(0.5f + oversampleTexture * position.height);

            // resize needed?
            if (textureWidth != _textureWidth || textureHeight != _textureHeight)
            {
                ImageResizer spareResizer; // if global resize not available, use one on stack.

                if (resizer is null)
                {
                    resizer = &spareResizer;
                }

                _textureWidth = textureWidth;
                _textureHeight = textureHeight;

                int numTiles = 3;
                int DW = _textureWidth;
                int DH = _textureHeight;
                int SH = _knobImage.image.width / numTiles;

                _resizedImage.size(numMipLevels, DW*numTiles, DH);

                ImageRef!RGBA16 input = _knobImage.image.getImageRef!RGBA16();
                ImageRef!RGBA16 resized = _resizedImage.levels[0].toRef;

                // Resize each of the 3 subrect independently, to avoid strange pixel offset polluting

                // Resize the premultiplied images to _resizedImage.
                resizer.resizeImageDiffuseWithAlphaPremul(input.cropImageRef(rectangle(0, 0, SH, SH)), 
                                                          resized.cropImageRef(rectangle(0, 0, DW, DH)));
                resizer.resizeImageDepthWithAlphaPremul(input.cropImageRef(rectangle(SH, 0, SH, SH)), 
                                                        resized.cropImageRef(rectangle(DW, 0, DW, DH)));
                resizer.resizeImageMaterialWithAlphaPremul(input.cropImageRef(rectangle(SH*2, 0, SH, SH)), 
                                                           resized.cropImageRef(rectangle(DW*2, 0, DW, DH)));
            }
        }
    }

    override void drawKnob(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        bool legacy = _knobImage.isLegacy();

        // This is just to enable scripting of `oversampleTe5xture`.
        if (!legacy)
        {
            version(KnobImage_resizedInternal)
                lazyResizeBADAMA16(null);
        }

        float radius = getRadius();
        vec2f center = getCenter();
        float valueAngle = getValueAngle() + PI_2;
        float cosa = cos(valueAngle);
        float sina = sin(valueAngle);



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

            enum float renormDepth = 1.0 / 65535.0f;
            for (int y = 0; y < dirtyRect.height; ++y)
            {


                RGBA* outDiffuse = cDiffuse.scanline(y).ptr;
                L16* outDepth = cDepth.scanline(y).ptr;
                RGBA* outMaterial = cMaterial.scanline(y).ptr;

                if (legacy)
                {
                    // source center 
                    int W = position.width;
                    int H = position.height; 
                    vec2f sourceCenter = vec2f(W*0.5f, H*0.5f);

                    for (int x = 0; x < dirtyRect.width; ++x)
                    {
                        vec2f destPos = vec2f(x + dirtyRect.min.x, y + dirtyRect.min.y);
                        vec2f sourcePos = sourceCenter + rotate(destPos - center);

                        // Legacy textures have 

                        // If the point is outside the knobimage, it is considered to have an alpha of zero
                        float fAlpha = 0.0f;

                        if ( (sourcePos.x >= 0.5f) && (sourcePos.x < (H - 0.5f))
                         &&  (sourcePos.y >=  0.5f) && (sourcePos.y < (H - 0.5f)) )
                        {
                            // PERF: sample a single RGBA L16 mipmap once in non-legacy mode

                            fAlpha = _alphaTexture.linearSample(0, sourcePos.x, sourcePos.y);

                            if (fAlpha > 0)
                            {
                                ubyte alpha = cast(ubyte)(0.5f + fAlpha / 257.0f);

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

                                if (drawToDepth)
                                {
                                    float fAlphaDepth = fAlpha;
                                    fAlphaDepth *= 0.00001525902f; // 1 / 65535
                                    float fDepth    =    _depthTexture.linearSample(0, sourcePos.x, sourcePos.y);
                                    float interpDepth = fDepth * fAlphaDepth + outDepth[x].l * (1.0f - fAlphaDepth);
                                    outDepth[x] = L16(cast(ushort)(0.5f + interpDepth) );
                                }
                            }
                        }
                    }
                }
                else
                {
                    version(KnobImage_resizedInternal)
                    {
                        int DW = _textureWidth;
                        int DH = _textureHeight;

                        vec2f sourceCenter = vec2f(DW*0.5f, DH*0.5f);


                        // non-legacy drawing builds upon the fact the texture will be alpha-premul
                        for (int x = 0; x < dirtyRect.width; ++x)
                        {
                            vec2f destPos = vec2f(x + dirtyRect.min.x, y + dirtyRect.min.y);

                            vec2f sourcePos = sourceCenter + rotate(destPos - center) * oversampleTexture;


                            if ( (sourcePos.x >= 0.5f) && (sourcePos.x < (DW - 0.5f))
                                    &&  (sourcePos.y >=  0.5f) && (sourcePos.y < (DH - 0.5f)) )
                            {
                                // Get the alpha-premultiplied samples in a single texture.

                                if (drawToDiffuse)
                                {
                                    vec4f fDiffuse;
                                    if (diffuseInterpolation == KnobInterpolationType.linear)
                                        fDiffuse = _resizedImage.linearSample(0, sourcePos.x, sourcePos.y);
                                    else
                                        fDiffuse = _resizedImage.cubicSample(0, sourcePos.x, sourcePos.y);
                                    if (fDiffuse.a > 0)
                                    {
                                        // Convert from 16-bit to 8-bit
                                        ubyte R = cast(ubyte)(0.5f + fDiffuse.r / 257.0f);
                                        ubyte G = cast(ubyte)(0.5f + fDiffuse.g / 257.0f);
                                        ubyte B = cast(ubyte)(0.5f + fDiffuse.b / 257.0f);
                                        ubyte A = cast(ubyte)(0.5f + fDiffuse.a / 257.0f);
                                        int E = (emissiveOffset * A) / 255; // Need to premultiply Emissive by Alpha
                                        RGBA diffuse = RGBA(R, G, B, cast(ubyte)E);
                                        outDiffuse[x] = blendColorPremul( diffuse, outDiffuse[x], A);
                                    }
                                }

                                if (drawToMaterial)
                                {
                                    vec4f fMaterial;
                                    if (materialInterpolation == KnobInterpolationType.linear)
                                        fMaterial = _resizedImage.linearSample(0, sourcePos.x + DW*2, sourcePos.y);
                                    else
                                        fMaterial = _resizedImage.cubicSample(0, sourcePos.x + DW*2, sourcePos.y);

                                    if (fMaterial.a > 0)
                                    {
                                        // Convert from 16-bit to 8-bit
                                        ubyte R = cast(ubyte)(0.5f + fMaterial.r / 257.0f);
                                        ubyte G = cast(ubyte)(0.5f + fMaterial.g / 257.0f);
                                        ubyte B = cast(ubyte)(0.5f + fMaterial.b / 257.0f);
                                        ubyte A = cast(ubyte)(0.5f + fMaterial.a / 257.0f);
                                        RGBA material = RGBA(R, G, B, 0); // clear last channel, means nothing currently
                                        outMaterial[x] = blendColorPremul( material, outMaterial[x], A);
                                    }
                                }

                            
                                if (drawToDepth)
                                {
                                    vec4f fDepth;
                                    if (depthInterpolation == KnobInterpolationType.linear)
                                        fDepth = _resizedImage.linearSample(0, sourcePos.x + DW, sourcePos.y);
                                    else
                                        fDepth = _resizedImage.cubicSample(0, sourcePos.x + DW, sourcePos.y);

                                    if (fDepth.a > 0)
                                    {
                                        // Keep it in 16-bit
                                        float fAlphaDepth = fDepth.a * 0.00001525902f; // 1 / 65535
                                        float depthHere = outDepth[x].l; //error = 32244

                                        // As specified, only green is considered as depth value, though you will likely
                                        // want to raw your depth in grey.
                                        float interpDepth = fDepth.g + depthHere * (1.0f - fAlphaDepth); // error = 65543.016

                                        // Note: here it's perfectly possible for interpDepth to overshoot above 65535 because of roundings.
                                        // if alpha is near 1.0f, and fDepth.g is rounded up, then the result may overshoot.
                                        // eg: 65532 (ie. white with 0.99957263 alpha) added to (1 - 0.99957263) * 32242.0f
                                        if (interpDepth > 65535.0f)
                                        {
                                            interpDepth = 65535.0f;
                                        }
                                        assert(interpDepth >= 0 && interpDepth <= 65535.49);
                                        outDepth[x] = L16(cast(ushort)(0.5f + interpDepth) );
                                    }
                                }
                            }
                        }
                    }
                    else
                    {
                        // New draw mode for BADAMA_16, interpolates KnobImage directly linearly.
                        // This is the future.

                        // Size of input texture.
                        int DH = _knobImage.image.height;
                        int DW = DH;

                        int W = position.width;
                        int H = position.height;  

                        vec2f sourceCenter = vec2f(DW*0.5f, DH*0.5f);
                        vec2f widgetCenter = vec2f(W*0.5f, H*0.5f);

                        float scaleFactor = DH / cast(float)H;


                        // non-legacy drawing builds upon the fact the texture will be alpha-premul
                        for (int x = 0; x < dirtyRect.width; ++x)
                        {
                            vec2f destPos = vec2f(x + dirtyRect.min.x, y + dirtyRect.min.y);
                            vec2f sourcePos = sourceCenter + rotate(destPos - widgetCenter) * scaleFactor;

                            // Can we sample the texture?
                            if ( (sourcePos.x >= 0.5f) && (sourcePos.x < (DW - 0.5f))
                                 &&  (sourcePos.y >=  0.5f) && (sourcePos.y < (DH - 0.5f)) )
                            {
                                // Get the alpha-premultiplied samples in a single texture.

                                if (drawToDiffuse)
                                {
                                    vec4f fDiffuse = cubicSampleRGBA16(_knobImage.image, sourcePos.x, sourcePos.y);

                                    if (fDiffuse.a > 0)
                                    {
                                        // Convert from 16-bit to 8-bit
                                        ubyte R = cast(ubyte)(0.5f + fDiffuse.r / 257.0f);
                                        ubyte G = cast(ubyte)(0.5f + fDiffuse.g / 257.0f);
                                        ubyte B = cast(ubyte)(0.5f + fDiffuse.b / 257.0f);
                                        ubyte A = cast(ubyte)(0.5f + fDiffuse.a / 257.0f);
                                        int E = (emissiveOffset * A) / 255; // Need to premultiply Emissive by Alpha
                                        RGBA diffuse = RGBA(R, G, B, cast(ubyte)E);
                                        outDiffuse[x] = blendColorPremul( diffuse, outDiffuse[x], A);
                                    }
                                }

                                if (drawToMaterial)
                                {
                                    vec4f fMaterial;
                                    fMaterial = cubicSampleRGBA16(_knobImage.image, sourcePos.x + DW*2, sourcePos.y);
                                    if (fMaterial.a > 0)
                                    {
                                        // Convert from 16-bit to 8-bit
                                        ubyte R = cast(ubyte)(0.5f + fMaterial.r / 257.0f);
                                        ubyte G = cast(ubyte)(0.5f + fMaterial.g / 257.0f);
                                        ubyte B = cast(ubyte)(0.5f + fMaterial.b / 257.0f);
                                        ubyte A = cast(ubyte)(0.5f + fMaterial.a / 257.0f);
                                        RGBA material = RGBA(R, G, B, 0); // clear last channel, means nothing currently
                                        outMaterial[x] = blendColorPremul( material, outMaterial[x], A);
                                    }
                                }


                                if (drawToDepth)
                                {
                                    vec4f fDepth;
                                    fDepth = cubicSampleRGBA16(_knobImage.image, sourcePos.x + DW, sourcePos.y);

                                    if (fDepth.a > 0)
                                    {
                                        // Keep it in 16-bit
                                        float fAlphaDepth = fDepth.a * 0.00001525902f; // 1 / 65535
                                        float depthHere = outDepth[x].l; //error = 32244

                                        // As specified, only green is considered as depth value, though you will likely
                                        // want to raw your depth in grey.
                                        float interpDepth = fDepth.g + depthHere * (1.0f - fAlphaDepth); // error = 65543.016

                                        // Note: here it's perfectly possible for interpDepth to overshoot above 65535 because of roundings.
                                        // if alpha is near 1.0f, and fDepth.g is rounded up, then the result may overshoot.
                                        // eg: 65532 (ie. white with 0.99957263 alpha) added to (1 - 0.99957263) * 32242.0f
                                        if (interpDepth > 65535.0f)
                                        {
                                            interpDepth = 65535.0f;
                                        }
                                        assert(interpDepth >= 0 && interpDepth <= 65535.49);
                                        outDepth[x] = L16(cast(ushort)(0.5f + interpDepth) );
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    KnobImage _knobImage; // borrowed image of the knob

    // Note: mipmaps are used here, only for the linear sampling ability!

    // <Only used in BADAMA_16 format>
    version(KnobImage_resizedInternal)
    {
        Mipmap!RGBA16 _resizedImage;
        int _textureWidth = -1;  // texture size is: 3*_textureWidth, _textureHeight with _textureWidth == _textureHeight being equal.
        int _textureHeight = -1;
    }
    // </Only used in BADAMA_16 format>

    // <Only used in ABDME_8 format>
    Mipmap!L16 _alphaTexture;         // owned 1-level image of alpha
    OwnedImage!L16 _tempBuf; // used for augmenting bitdepth of alpha and depth
    OwnedImage!RGBA _tempBufRGBA; // used for lessening bitdepth of material and diffuse
    Mipmap!L16 _depthTexture; // owned 1-level image of depth
    Mipmap!RGBA _diffuseTexture; // owned 1-level image of diffuse+emissive RGBE
    Mipmap!RGBA _materialTexture; // owned 1-level image of material
    // </Only used in ABDME_8 format>

}

private:

// Interpolation in a 1-level mipmap (at level 0), with RGBA16 premultiplied samples.
// This is for imageKnob interpolation.
vec4f linearSampleRGBA16(ref Image image, float x, float y) nothrow @nogc
{
    assert(image.type() == PixelType.rgba16);
    alias COLOR = RGBA16;

    x = x - 0.5f;
    y = y - 0.5f;

    if (x < 0)
        x = 0;
    if (y < 0)
        y = 0;

    __m128 floatCoords = _mm_setr_ps(x, y, 0, 0);
    __m128i truncatedCoord = _mm_cvttps_epi32(floatCoords);
    int ix = truncatedCoord.array[0];
    int iy = truncatedCoord.array[1];

    // Get fractional part
    float fx = x - ix;
    float fy = y - iy;

    const int maxX = image.width() - 1;
    const int maxY = image.height() - 1;
    if (ix > maxX)
        ix = maxX;
    if (iy > maxY)
        iy = maxY;

    int ixp1 = ix + 1;
    int iyp1 = iy + 1;
    if (ixp1 > maxX)
        ixp1 = maxX;
    if (iyp1 > maxY)
        iyp1 = maxY;  

    float fxm1 = 1 - fx;
    float fym1 = 1 - fy;

    COLOR* L0 = cast(COLOR*) image.scanptr(iy);
    COLOR* L1 = cast(COLOR*) image.scanptr(iyp1);

    COLOR A = L0[ix];
    COLOR B = L0[ixp1];
    COLOR C = L1[ix];
    COLOR D = L1[ixp1];

    vec4f vA = vec4f(A.r, A.g, A.b, A.a);
    vec4f vB = vec4f(B.r, B.g, B.b, B.a);
    vec4f vC = vec4f(C.r, C.g, C.b, C.a);
    vec4f vD = vec4f(D.r, D.g, D.b, D.a);

    vec4f up = vA * fxm1 + vB * fx;
    vec4f down = vC * fxm1 + vD * fx;
    vec4f result = up * fym1 + down * fy;
    return result;
}

vec4f cubicSampleRGBA16(ref Image image, float x, float y) nothrow @nogc
{
    assert(image.type() == PixelType.rgba16);
    alias COLOR = RGBA16;

    x = x - 0.5f;
    y = y - 0.5f;

    __m128 mm0123 = _mm_setr_ps(-1, 0, 1, 2);
    __m128i x_indices = _mm_cvttps_epi32( _mm_set1_ps(x) + mm0123);
    __m128i y_indices = _mm_cvttps_epi32( _mm_set1_ps(y) + mm0123);
    __m128i zero = _mm_setzero_si128();
    x_indices = _mm_max_epi32(x_indices, zero);
    y_indices = _mm_max_epi32(y_indices, zero);
    x_indices = _mm_min_epi32(x_indices, _mm_set1_epi32(image.width()-1));
    y_indices = _mm_min_epi32(y_indices, _mm_set1_epi32(image.height()-1));

    int i0 = x_indices.array[0];
    int i1 = x_indices.array[1];
    int i2 = x_indices.array[2];
    int i3 = x_indices.array[3];

    // fractional part
    float a = x + 1.0f;
    float b = y + 1.0f;
    a = a - cast(int)(a);
    b = b - cast(int)(b);
    assert(a >= -0.01 && a <= 1.01);
    assert(b >= -0.01 && b <= 1.01);

    COLOR*[4] L = void;
    L[0] = cast(COLOR*) image.scanptr(y_indices.array[0]);
    L[1] = cast(COLOR*) image.scanptr(y_indices.array[1]);
    L[2] = cast(COLOR*) image.scanptr(y_indices.array[2]);
    L[3] = cast(COLOR*) image.scanptr(y_indices.array[3]);

  
    {
        // actually optimized ok by LDC
        static vec4f clamp_0_to_65535(vec4f a)
        {
            if (a[0] < 0) a[0] = 0;
            if (a[1] < 0) a[1] = 0;
            if (a[2] < 0) a[2] = 0;
            if (a[3] < 0) a[3] = 0;
            if (a[0] > 65535) a[0] = 65535;
            if (a[1] > 65535) a[1] = 65535;
            if (a[2] > 65535) a[2] = 65535;
            if (a[3] > 65535) a[3] = 65535;
            return a;
        }

        static cubicInterp(float t, vec4f x0, vec4f x1, vec4f x2, vec4f x3) pure nothrow @nogc
        {
            // PERF: doesn't sound that great???
            return x1 
                + t * ((-0.5f * x0) + (0.5f * x2))
                + t * t * (x0 - (2.5f * x1) + (2.0f * x2) - (0.5f * x3))
                + t * t * t * ((-0.5f * x0) + (1.5f * x1) - (1.5f * x2) + 0.5f * x3);
        }
        vec4f[4] R = void;
        for (int row = 0; row < 4; ++row)
        {
            COLOR* pRow = L[row];
            COLOR ri0jn = pRow[i0];
            COLOR ri1jn = pRow[i1];
            COLOR ri2jn = pRow[i2];
            COLOR ri3jn = pRow[i3];
            vec4f A = vec4f(ri0jn.r, ri0jn.g, ri0jn.b, ri0jn.a);
            vec4f B = vec4f(ri1jn.r, ri1jn.g, ri1jn.b, ri1jn.a);
            vec4f C = vec4f(ri2jn.r, ri2jn.g, ri2jn.b, ri2jn.a);
            vec4f D = vec4f(ri3jn.r, ri3jn.g, ri3jn.b, ri3jn.a);
            R[row] = cubicInterp(a, A, B, C, D);
        }
        return clamp_0_to_65535(cubicInterp(b, R[0], R[1], R[2], R[3]));
    }
}