/**
The widget you must inherit from for a PBR background UI (though it isn't mandatory).

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.pbrbackgroundgui;

import dplug.math.box;
import dplug.core.nogc;
import dplug.core.file;

// Note: this dependency exist because Key is defined in dplug:window
import dplug.window.window;

import dplug.gui.graphics;
import dplug.gui.element;
import dplug.gui.compositor;
import dplug.gui.legacypbr;
public import dplug.gui.sizeconstraints;

import gamut;


// `decompressImagesLazily` cause JPEG and PNG to be decompressed on the fly on resize, instead 
// of ahead of time and staying in memory.
// This wins 17mb of RAM on Panagement.
// However, this also disable live reload of images for UI development. Hence, it is disabled for debug builds, in order
// to reload background with the RETURN key.
debug {}
else
{
    version = decompressImagesLazily;
}


// `cacheDecodedImagesInQOIX` assumes the images won't change, and that we can cache the decoded
// images in QOIX in order to speed-up subsequent decodes.
version(decompressImagesLazily)
{
    version = cacheDecodedImagesInQOIX;
}

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
        this(makeSizeConstraintsFixed(width, height));
    }

    this(SizeConstraints sizeConstraints)
    {
        super(sizeConstraints, flagPBR | flagAnimated);

        _diffuseResized = mallocNew!(OwnedImage!RGBA);
        _materialResized = mallocNew!(OwnedImage!RGBA);
        _depthResized = mallocNew!(OwnedImage!L16);

        version(decompressImagesLazily)
        {}
        else
        {
            loadBackgroundImagesFromStaticData();
        }

        auto skyboxData = cast(ubyte[])(import(skyboxPath));
        loadSkybox(skyboxData);
    }    

    ~this()
    {
        version(cacheDecodedImagesInQOIX)
            freeCachedImages();
        freeBackgroundImages();
        _diffuseResized.destroyFree();
        _materialResized.destroyFree();
        _depthResized.destroyFree();
    }

    // Development purposes. 
    // In debug mode, pressing ENTER reload the backgrounds
    debug
    {
        override bool onKeyDown(Key key)
        {
            if (super.onKeyDown(key))
                return true;

            version(decompressImagesLazily)
            {
            }
            else
            {
                if (key == Key.enter)
                {
                    reloadImagesAtRuntime();
                    return true;
                }
            }

            return false;
        }
    }

    override void onDrawPBR(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        // Resize resource to match _position
        {
            int W = position.width;
            int H = position.height;
            ImageResizer resizer;
            
            if (_forceResizeUpdate || _diffuseResized.w != W || _diffuseResized.h != H)
            {
                // Decompress images lazily for this size

                version (decompressImagesLazily)
                {
                    assert(_diffuse is null);
                    loadBackgroundImagesFromStaticData();
                }
                _diffuseResized.size(W, H);
                _materialResized.size(W, H);
                _depthResized.size(W, H);
                resizer.resizeImageDiffuse(_diffuse.toRef, _diffuseResized.toRef);
                resizer.resizeImageMaterial(_material.toRef, _materialResized.toRef);
                resizer.resizeImageDepth(_depth.toRef, _depthResized.toRef);
                _forceResizeUpdate = false;

                version (decompressImagesLazily)
                {
                    freeBackgroundImages();
                    assert(_diffuse is null);
                }
            }
        }

        // Just blit backgrounds into dirtyRects.
        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuseIn = _diffuseResized.toRef().cropImageRef(dirtyRect);
            auto croppedDiffuseOut = diffuseMap.cropImageRef(dirtyRect);

            auto croppedDepthIn = _depthResized.toRef().cropImageRef(dirtyRect);
            auto croppedDepthOut = depthMap.cropImageRef(dirtyRect);

            auto croppedMaterialIn = _materialResized.toRef().cropImageRef(dirtyRect);
            auto croppedMaterialOut = materialMap.cropImageRef(dirtyRect);

            croppedDiffuseIn.blitTo(croppedDiffuseOut);
            croppedDepthIn.blitTo(croppedDepthOut);
            croppedMaterialIn.blitTo(croppedMaterialOut);
        }
    }

    override void reflow()
    {
    }

private:

    final void loadBackgroundImagesFromStaticData()
    {
        auto basecolorData = cast(ubyte[])(import(baseColorPath));
        auto emissiveData = cast(ubyte[])(import(emissivePath));
        auto materialData = cast(ubyte[])(import(materialPath));
        auto depthData = cast(ubyte[])(import(depthPath));
        loadBackgroundImages(basecolorData, emissiveData, materialData, depthData);
    }

    // CTFE used here so we are allowed to use ~
    static immutable string baseColorPathAbs = absoluteGfxDirectory ~ baseColorPath;
    static immutable string emissivePathAbs = absoluteGfxDirectory ~ emissivePath;
    static immutable string materialPathAbs = absoluteGfxDirectory ~ materialPath;
    static immutable string depthPathAbs = absoluteGfxDirectory ~ depthPath;
    static immutable string skyboxPathAbs = absoluteGfxDirectory ~ skyboxPath;

    OwnedImage!RGBA _diffuse;
    OwnedImage!RGBA _material;
    OwnedImage!L16 _depth;

    version(cacheDecodedImagesInQOIX)
    {
        ubyte[] _cachedDiffuse;
        ubyte[] _cachedMaterial;
        ubyte[] _cachedDepth;
    }

    OwnedImage!RGBA _diffuseResized;
    OwnedImage!RGBA _materialResized;
    OwnedImage!L16 _depthResized;

    /// Where pixel data is taken in the image, expressed in _background coordinates.
    box2i _sourceRect;

    /// Where it is deposited. Same size than _sourceRect. Expressed in _position coordinates.
    box2i _destRect;

    /// Offset from source to dest.
    vec2i _offset;

    /// Force resize of source image in order to display changes while editing files.
    bool _forceResizeUpdate;

    void freeBackgroundImages()
    {
        if (_diffuse)
        {
            _diffuse.destroyFree();
            _diffuse = null;
        }

        if (_depth)
        {
            _depth.destroyFree();
            _depth = null;
        }

        if (_material)
        {
            _material.destroyFree();
            _material = null;
        }
    }

    version(decompressImagesLazily)
    {
    }
    else
    {
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
                freeBackgroundImages();
                loadBackgroundImages(basecolorData, emissiveData, materialData, depthData);
                loadSkybox(skyboxData);
                _forceResizeUpdate = true;
                setDirtyWhole();
            }
            else
            {
                // Note: if you fail here, the absolute path you provided in your gui.d was incorrect.
                // The background files cannot be loaded at runtime, and you have to fix your pathes.
                assert(false);
            }

            // Release copy of file contents
            freeSlice(basecolorData);
            freeSlice(emissiveData);
            freeSlice(materialData);
            freeSlice(depthData);
            freeSlice(skyboxData);
        }
    }

    void loadBackgroundImages(ubyte[] basecolorData, ubyte[] emissiveData,
                              ubyte[] materialData, ubyte[] depthData)
    {
        version(cacheDecodedImagesInQOIX)
        {
            if (hasCachedImages())
            {
                // load from cache instead on 2nd load

                version(Dplug_ProfileUI) context.profiler.category("image").begin("load cached Diffuse ");
                _diffuse = loadOwnedImage(_cachedDiffuse);
                version(Dplug_ProfileUI) context.profiler.end;

                version(Dplug_ProfileUI) context.profiler.begin("load cached background");
                _material = loadOwnedImage(_cachedMaterial);
                version(Dplug_ProfileUI) context.profiler.end;

                version(Dplug_ProfileUI) context.profiler.begin("load cached background");
                _depth = loadOwnedImageDepth(_cachedDepth);
                version(Dplug_ProfileUI) context.profiler.end;
                return;
            }
        }

        version(Dplug_ProfileUI) context.profiler.category("image").begin("load Diffuse background");
        _diffuse = loadImageSeparateAlpha(basecolorData, emissiveData);        
        version(Dplug_ProfileUI) context.profiler.end;

        version(Dplug_ProfileUI) context.profiler.begin("load Material background");
        _material = loadOwnedImage(materialData);
        version(Dplug_ProfileUI) context.profiler.end;

        version(Dplug_ProfileUI) context.profiler.begin("load Depth background");
        _depth = loadOwnedImageDepth(depthData);
        version(Dplug_ProfileUI) context.profiler.end;

        version(cacheDecodedImagesInQOIX)
        {
            // On first decode, re-encodes these decoded images into a easier representation.
            cacheBackgroundImages();
        }
    }

    version(cacheDecodedImagesInQOIX)
    {
        bool hasCachedImages()
        {
            return _cachedDiffuse !is null;
        }

        void freeCachedImages()
        {
            if (hasCachedImages())
            {
                freeEncodedImage(_cachedDiffuse);
                freeEncodedImage(_cachedMaterial);
                freeEncodedImage(_cachedDepth);
                _cachedDiffuse = null;
                _cachedMaterial = null;
                _cachedDepth = null;
            }
        }

        void cacheBackgroundImages()
        {
            Image image;
            image.createViewFromImageRef!RGBA(_diffuse.toRef);
            _cachedDiffuse = image.saveToMemory(ImageFormat.QOIX);
            image.createViewFromImageRef!RGBA(_material.toRef);
            _cachedMaterial = image.saveToMemory(ImageFormat.QOIX);
            image.createViewFromImageRef!L16(_depth.toRef);
            _cachedDepth = image.saveToMemory(ImageFormat.QOIX);
        }
    }

    void loadSkybox(ubyte[] skyboxData)
    {        
        // Search for a pass of type PassSkyboxReflections
        if (auto mpc = cast(MultipassCompositor) compositor())
        {
            foreach(pass; mpc.passes())
            {
                if (auto skyreflPass = cast(PassSkyboxReflections)pass)
                {
                    version(Dplug_ProfileUI) context.profiler.category("image").begin("load Skybox");
                    OwnedImage!RGBA skybox = loadOwnedImage(skyboxData);
                    skyreflPass.setSkybox(skybox);
                    version(Dplug_ProfileUI) context.profiler.end;
                }
            }
        }
    }
}

