/**
The widget you must inherit from for a PBR background UI (though it isn't mandatory).

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.pbrbackgroundgui;

import gfm.math.box;
import dplug.core.nogc;
import dplug.core.file;
import dplug.graphics.color;
import dplug.graphics.image;
import dplug.graphics.view;
import dplug.graphics.drawex;

// Note: this dependency exist because Key is defined in dplug:window
import dplug.window.window;

import dplug.gui.graphics;
import dplug.gui.element;
import dplug.gui.compositor;
import dplug.gui.legacypbr;

/// PBRBackgroundGUI provides a PBR background loaded from PNG or JPEG images.
/// It's very practical while in development because it let's you reload the six
/// images used with the press of ENTER.
/// The path of each of these images (given as a template parameter) must be
/// in your "stringImportPaths" settings.
class PBRBackgroundGUI(string baseColorPath, 
                       string emissivePath, 
                       string materialPath,
                       string depthPath,
                       string skyboxPath,
                       string absoluteGfxDirectory // for UI development only
                       ) : GUIGraphics
{
public:
nothrow:
@nogc:

    this(int width, int height)
    {
        super(width, height, flagPBR);
        auto basecolorData = cast(ubyte[])(import(baseColorPath));
        auto emissiveData = cast(ubyte[])(import(emissivePath));        
        auto materialData = cast(ubyte[])(import(materialPath));
        auto depthData = cast(ubyte[])(import(depthPath));
        auto skyboxData = cast(ubyte[])(import(skyboxPath));
        loadImages(basecolorData, emissiveData, materialData, depthData, skyboxData);
    } 

    ~this()
    {
        freeImages();
    }

    // Development purposes. 
    // In debug mode, pressing ENTER reload the backgrounds
    debug
    {
        override bool onKeyDown(Key key)
        {
            if (super.onKeyDown(key))
                return true;

            if (key == Key.enter)
            {
                reloadImagesAtRuntime();
                return true;
            }

            return false;
        }
    }

    override void reflow(box2i availableSpace)
    {
        bool reallocResizedImage = availableSpace.width != _position.width || availableSpace.height != _position.height;
        
        // Note: the position is entirely decorrelated from the size of _backgroundImage
        _position = availableSpace;

        
        if(reallocResizedImage)
        {
            _diffuseResized = mallocNew!(OwnedImage!RGBA)(_position.width, _position.height);
            _materialResized = mallocNew!(OwnedImage!RGBA)(_position.width, _position.height);
            _depthResized = mallocNew!(OwnedImage!L16)(_position.width, _position.height);

            resizeBilinear(_diffuse.toRef(), _diffuseResized.toRef());
            resizeBilinear(_material.toRef(), _materialResized.toRef());
            resizeBilinear(_depth.toRef(), _depthResized.toRef());

            setDirtyWhole();
        }
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        // Just blit backgrounds into dirtyRects.
        foreach(dirtyRect; dirtyRects)
        {

            auto croppedDiffuseIn = _diffuseResized.crop(dirtyRect);
            auto croppedDiffuseOut = diffuseMap.crop(dirtyRect);

            auto croppedDepthIn = _depthResized.crop(dirtyRect);
            auto croppedDepthOut = depthMap.crop(dirtyRect);

            auto croppedMaterialIn = _materialResized.crop(dirtyRect);
            auto croppedMaterialOut = materialMap.crop(dirtyRect);

            croppedDiffuseIn.blitTo(croppedDiffuseOut);
            croppedDepthIn.blitTo(croppedDepthOut);
            croppedMaterialIn.blitTo(croppedMaterialOut);
        }
    }

private:

    // CTFE used here so we are allowed to use ~
    static immutable string baseColorPathAbs = absoluteGfxDirectory ~ baseColorPath;
    static immutable string emissivePathAbs = absoluteGfxDirectory ~ emissivePath;
    static immutable string materialPathAbs = absoluteGfxDirectory ~ materialPath;
    static immutable string depthPathAbs = absoluteGfxDirectory ~ depthPath;
    static immutable string skyboxPathAbs = absoluteGfxDirectory ~ skyboxPath;


    OwnedImage!RGBA _diffuse;
    OwnedImage!RGBA _material;
    OwnedImage!L16 _depth;

    OwnedImage!RGBA _diffuseResized;
    OwnedImage!RGBA _materialResized;
    OwnedImage!L16 _depthResized;

    /// Where pixel data is taken in the image, expressed in _background coordinates.
    box2i _sourceRect;

    /// Where it is deposited. Same size than _sourceRect. Expressed in _position coordinates.
    box2i _destRect;

    /// Offset from source to dest.
    vec2i _offset;

    void freeImages()
    {
        if (_diffuse)
            _diffuse.destroyFree();
        if (_depth)
            _depth.destroyFree();
        if (_material)
            _material.destroyFree();
    }

    // Reloads images for UI development, avoid long compile round trips
    // This saves up hours.
    void reloadImagesAtRuntime()
    {
        // reading images with an absolute path since we don't know 
        // which is the current directory from the host
        ubyte[] basecolorData = readFile(baseColorPathAbs);
        ubyte[] emissiveData = readFile(emissivePathAbs);
        ubyte[] materialData = readFile(materialPathAbs);
        ubyte[] depthData = readFile(depthPathAbs);
        ubyte[] skyboxData = readFile(skyboxPathAbs);

        if (basecolorData && emissiveData && materialData
            && depthData && skyboxData) // all valid?
        {
            // Reload images from disk and update the UI
            freeImages();
            loadImages(basecolorData, emissiveData, materialData, depthData, skyboxData);
            setDirtyWhole();
        }

        // Release copy of file contents
        freeSlice(basecolorData);
        freeSlice(emissiveData);
        freeSlice(materialData);
        freeSlice(depthData);
        freeSlice(skyboxData);
    }

    void loadImages(ubyte[] basecolorData, ubyte[] emissiveData,
                    ubyte[] materialData, ubyte[] depthData, ubyte[] skyboxData)
    {
        _diffuse = loadImageSeparateAlpha(basecolorData, emissiveData);
        _material = loadOwnedImage(materialData);
        OwnedImage!RGBA depthRGBA = loadOwnedImage(depthData);
        scope(exit) depthRGBA.destroyFree();
        assert(_diffuse.w == _material.w);
        assert(_diffuse.h == _material.h);
        assert(_diffuse.w == depthRGBA.w);
        assert(_diffuse.h == depthRGBA.h);

        int width = depthRGBA.w;
        int height = depthRGBA.h;

        _depth = mallocNew!(OwnedImage!L16)(width, height);

        for (int j = 0; j < height; ++j)
        {
            RGBA[] inDepth = depthRGBA.scanline(j);
            L16[] outDepth = _depth.scanline(j);
            for (int i = 0; i < width; ++i)
            {
                RGBA v = inDepth[i];

                float d = 0.5f + 257 * (v.g + v.r + v.b) / 3;

                outDepth[i].l = cast(ushort)(d);
            }
        }


        // Search for a pass of type PassSkyboxReflections
        if (auto mpc = cast(MultipassCompositor) getCompositor())
        {
            foreach(pass; mpc.passes())
            {
                if (auto skyreflPass = cast(PassSkyboxReflections)pass)
                {
                    OwnedImage!RGBA skybox = loadOwnedImage(skyboxData);
                    skyreflPass.setSkybox(skybox);
                }
            }
        }
    }
}

