/**
* Home of `UIBufferedElement`, for non-opaque widgets.
*
* Copyright: Copyright Auburn Sounds 2015-2016.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.bufferedelement;

import dplug.core.nogc;
public import dplug.gui.element;

// Important values for opacity.
enum L8 opacityFullyOpaque = L8(255);
enum L8 opacityFullyTransparent = L8(0);


/// Extending the UIElement with an owned drawing buffer.
/// This is intended to have easier dirtyrect-compliant widgets.
/// Also caches expensive drawing, but it's not free at all.
///
/// No less than three additional opacity channels must be filled to be able to blend the widgets explicitly.
/// The semantic of the opacity channels are:
///   opacity left at 0 => pixel untouched
///   opacity > 0       => pixel is touched, blending will occur
class UIBufferedElementPBR : UIElement
{
public:
nothrow:
@nogc:

    this(UIContext context, uint flags)
    {
        super(context, flags);

        // It makes no sense to bufferize the PBR impact of an UIElement which would not draw there
        assert(drawsToPBR());

        _diffuseBuf = mallocNew!(OwnedImage!RGBA)();
        _depthBuf = mallocNew!(OwnedImage!L16)();
        _materialBuf = mallocNew!(OwnedImage!RGBA)();
        _diffuseOpacityBuf = mallocNew!(OwnedImage!L8)();
        _depthOpacityBuf = mallocNew!(OwnedImage!L8)();
        _materialOpacityBuf = mallocNew!(OwnedImage!L8)();
    }

    ~this()
    {
        _diffuseBuf.destroyFree();
        _depthBuf.destroyFree();
        _materialBuf.destroyFree();
        _diffuseOpacityBuf.destroyFree();
        _depthOpacityBuf.destroyFree();
        _materialOpacityBuf.destroyFree();
    }

    override void setDirty(box2i rect, UILayer layer = UILayer.guessFromFlags) nothrow @nogc 
    {
        super.setDirty(rect, layer);
        _mustBeRedrawn = true; // the content of the cached buffer will change, need to be redrawn
    }

    override void setDirtyWhole(UILayer layer = UILayer.guessFromFlags) nothrow @nogc 
    {
        super.setDirtyWhole(layer);
        _mustBeRedrawn = true; // the content of the cached buffer will change, need to be redrawn
    }

    final override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        // Did the element's size changed?
        int currentWidth = _diffuseBuf.w;
        int currentHeight = _diffuseBuf.h;
        int newWidth = _position.width;
        int newHeight = _position.height;
        bool sizeChanged = (currentWidth != newWidth) || (currentHeight != newHeight);
        if (sizeChanged)
        {
            // If the widget size changed, we must redraw it even if it was not dirtied
            _mustBeRedrawn = true;

            // Change size of buffers
            _diffuseBuf.size(newWidth, newHeight);
            _depthBuf.size(newWidth, newHeight);
            _materialBuf.size(newWidth, newHeight);

            _diffuseOpacityBuf.size(newWidth, newHeight);
            _depthOpacityBuf.size(newWidth, newHeight);
            _materialOpacityBuf.size(newWidth, newHeight);
        }

        if (_mustBeRedrawn)
        {
            // opacity buffer originally filled with zeroes
            _diffuseOpacityBuf.fillAll(opacityFullyTransparent);
            _depthOpacityBuf.fillAll(opacityFullyTransparent);
            _materialOpacityBuf.fillAll(opacityFullyTransparent);

            _diffuseBuf.fillAll(RGBA(128, 128, 128, 0));
            _depthBuf.fillAll(L16(defaultDepth));
            _materialBuf.fillAll(RGBA(defaultRoughness, defaultMetalnessMetal, defaultSpecular, 255));

            onDrawBufferedPBR(_diffuseBuf.toRef(), _depthBuf.toRef(), _materialBuf.toRef(), 
                              _diffuseOpacityBuf.toRef(),
                              _depthOpacityBuf.toRef(),
                              _materialOpacityBuf.toRef());

            // For debug purpose            
            //_diffuseOpacityBuf.fill(opacityFullyOpaque);
            //_depthOpacityBuf.fill(opacityFullyOpaque);
            //_materialOpacityBuf.fill(opacityFullyOpaque);

            _mustBeRedrawn = false;
        }

        // Blend cached render to given targets
        foreach(dirtyRect; dirtyRects)
        {
            auto sourceDiffuse = _diffuseBuf.toRef().cropImageRef(dirtyRect);
            auto sourceDepth = _depthBuf.toRef().cropImageRef(dirtyRect);
            auto sourceMaterial = _materialBuf.toRef().cropImageRef(dirtyRect);
            auto destDiffuse = diffuseMap.cropImageRef(dirtyRect);
            auto destDepth = depthMap.cropImageRef(dirtyRect);
            auto destMaterial = materialMap.cropImageRef(dirtyRect);

            sourceDiffuse.blendWithAlpha(destDiffuse, _diffuseOpacityBuf.toRef().cropImageRef(dirtyRect));
            sourceDepth.blendWithAlpha(destDepth, _depthOpacityBuf.toRef().cropImageRef(dirtyRect));
            sourceMaterial.blendWithAlpha(destMaterial, _materialOpacityBuf.toRef().cropImageRef(dirtyRect));
        }
    }

    /// Redraws the whole widget without consideration for drawing only in dirty rects.
    /// That is a lot of maps to fill. On the plus side, this happen quite infrequently.
    abstract void onDrawBufferedPBR(ImageRef!RGBA diffuseMap, 
                                    ImageRef!L16 depthMap, 
                                    ImageRef!RGBA materialMap, 
                                    ImageRef!L8 diffuseOpacity,
                                    ImageRef!L8 depthOpacity,
                                    ImageRef!L8 materialOpacity) nothrow @nogc;

private:
    OwnedImage!RGBA _diffuseBuf;
    OwnedImage!L16 _depthBuf;
    OwnedImage!RGBA _materialBuf;
    OwnedImage!L8 _diffuseOpacityBuf;
    OwnedImage!L8 _depthOpacityBuf;
    OwnedImage!L8 _materialOpacityBuf;
    bool _mustBeRedrawn;
}

///ditto
class UIBufferedElementRaw : UIElement
{
public:
nothrow:
@nogc:

    this(UIContext context, uint flags)
    {
        super(context, flags);

        // It makes no sense to bufferize the Raw impact of an UIElement which would not draw there
        assert(drawsToRaw());

        _rawBuf = mallocNew!(OwnedImage!RGBA)();
        _opacityBuf = mallocNew!(OwnedImage!L8)();
    }

    ~this()
    {
        _rawBuf.destroyFree();
        _opacityBuf.destroyFree();
    }

    /// Does not initialize buffers.
    /// `onDrawBufferedRaw` will be returned the same content, 
    /// unless the buffer size has changed.
    /// This is needed for widgets might want their own Raw 
    /// and Opacity buffer to stay unchanged, if their size
    /// didn't change. This is typically an optimization.
    void doNotClearBuffers()
    {
        _preClearBuffers = false;
    }

    override void setDirty(box2i rect, UILayer layer = UILayer.guessFromFlags)
    {
        super.setDirty(rect, layer);
        _mustBeRedrawn = true; // the content of the cached buffer will change, need to be redrawn
    }

    override void setDirtyWhole(UILayer layer = UILayer.guessFromFlags)
    {
        super.setDirtyWhole(layer);
        _mustBeRedrawn = true; // the content of the cached buffer will change, need to be redrawn
    }

    final override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        // Did the element's size changed?
        int currentWidth = _rawBuf.w;
        int currentHeight = _rawBuf.h;
        int newWidth = _position.width;
        int newHeight = _position.height;
        bool sizeChanged = (currentWidth != newWidth) || (currentHeight != newHeight);

        bool preClear = _preClearBuffers;
        if (sizeChanged)
        {
            // If the widget size changed, we must redraw it even if it was not dirtied
            _mustBeRedrawn = true;

            // Change size of buffers
            _opacityBuf.size(newWidth, newHeight);
            _rawBuf.size(newWidth, newHeight);

            preClear = true;
        }

        if (_mustBeRedrawn)
        {
            if (preClear)
            {
                // opacity buffer originally filled with zeroes
                _opacityBuf.fillAll(opacityFullyTransparent);

                // RGBA buffer originally filled with black
                _rawBuf.fillAll(RGBA(0, 0, 0, 255));
            }

            onDrawBufferedRaw(_rawBuf.toRef(), _opacityBuf.toRef());

            // For debug purpose
            //_opacityBuf.fillAll(opacityFullyOpaque);

            _mustBeRedrawn = false;
        }

        // Blend cached render to given targets
        foreach(dirtyRect; dirtyRects)
        {
            auto sourceRaw = _rawBuf.toRef().cropImageRef(dirtyRect);
            auto destRaw = rawMap.cropImageRef(dirtyRect);
            sourceRaw.blendWithAlpha(destRaw, _opacityBuf.toRef().cropImageRef(dirtyRect));
        }
    }

    /// Redraws the whole widget without consideration for drawing only in dirty rects.
    abstract void onDrawBufferedRaw(ImageRef!RGBA rawMap, ImageRef!L8 opacity);

private:
    OwnedImage!RGBA _rawBuf;
    OwnedImage!L8 _opacityBuf;
    bool _mustBeRedrawn;

    // Buffers are pre-cleared at every draw.
    // This allows to draw only non-transparent part, 
    // but can also be a CPU cost.
    // Default = true.
    bool _preClearBuffers = true;
}