/**
* Copyright: Copyright Auburn Sounds 2015-2017.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.pbrbackgroundgui;

import gfm.math.box;
import dplug.core.nogc;
import dplug.core.file;
import dplug.graphics.color;
import dplug.graphics.image;
import dplug.graphics.view;
import dplug.graphics.drawex;
import dplug.window.window;
import dplug.gui.graphics;

/// PBRBackgroundGUI provides a PBR background loaded from PNG or JPEG images.
/// It's very practical while in development because it let's you reload the six
/// images used with the press of ENTER.
/// The path of each of these images (given as a template parameter) must be
/// in your "stringImportPaths" settings.
class PBRBackgroundGUI(string baseColorPath, 
                       string emissivePath, 
                       string materialPath,
                       string physicalPath,
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
        super(width, height);
        auto basecolorData = cast(ubyte[])(import(baseColorPath));
        auto emissiveData = cast(ubyte[])(import(emissivePath));        
        auto materialData = cast(ubyte[])(import(materialPath));
        auto physicalData = cast(ubyte[])(import(physicalPath));
        auto depthData = cast(ubyte[])(import(depthPath));
        auto skyboxData = cast(ubyte[])(import(skyboxPath));
        loadImages(basecolorData, emissiveData, materialData, physicalData, depthData, skyboxData);
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
        _position = availableSpace;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        // Just blit backgrounds into dirtyRects.
        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuseIn = _diffuse.crop(dirtyRect);
            auto croppedDiffuseOut = diffuseMap.crop(dirtyRect);

            auto croppedDepthIn = _depth.crop(dirtyRect);
            auto croppedDepthOut = depthMap.crop(dirtyRect);

            auto croppedMaterialIn = _material.crop(dirtyRect);
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
    static immutable string physicalPathAbs = absoluteGfxDirectory ~ physicalPath;
    static immutable string depthPathAbs = absoluteGfxDirectory ~ depthPath;
    static immutable string skyboxPathAbs = absoluteGfxDirectory ~ skyboxPath;


    OwnedImage!RGBA _diffuse;
    OwnedImage!RGBA _material;
    OwnedImage!L16 _depth;

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
        ubyte[] physicalData = readFile(physicalPathAbs);
        ubyte[] depthData = readFile(depthPathAbs);
        ubyte[] skyboxData = readFile(skyboxPathAbs);

        if (basecolorData && emissiveData && materialData
            && physicalData && depthData && skyboxData) // all valid?
        {
            // Reload images from disk and update the UI
            freeImages();
            loadImages(basecolorData, emissiveData, materialData, physicalData, depthData, skyboxData);
            setDirtyWhole();
        }

        // Release copy of file contents
        freeSlice(basecolorData);
        freeSlice(emissiveData);
        freeSlice(materialData);
        freeSlice(physicalData);
        freeSlice(depthData);
        freeSlice(skyboxData);
    }

    void loadImages(ubyte[] basecolorData, ubyte[] emissiveData,
                    ubyte[] materialData, ubyte[] physicalData,
                    ubyte[] depthData, ubyte[] skyboxData)
    {
        _diffuse = loadImageSeparateAlpha(basecolorData, emissiveData);
        _material = loadImageSeparateAlpha(materialData, physicalData);
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

        OwnedImage!RGBA skybox = loadOwnedImage(skyboxData);
        context.setSkybox(skybox);
    }
}