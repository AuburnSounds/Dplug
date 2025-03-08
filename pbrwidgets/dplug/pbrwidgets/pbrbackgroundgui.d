/**
    A widget to inherit to make a PBR UI.
    It manages the background content. Though using such background
    content is not strictly mandatory in the Dplug model.

    Copyright: Copyright Guillaume Piolat 2015-2025.
    License:   http://www.boost.org/LICENSE_1_0.txt
*/
module dplug.pbrwidgets.pbrbackgroundgui;

import dplug.math.box;
import dplug.core.nogc;
import dplug.core.file;
import dplug.core.thread;

// `Key` is defined in dplug:window, odd dependency
import dplug.window.window;

import dplug.gui.graphics;
import dplug.gui.element;
import dplug.gui.compositor;
import dplug.gui.legacypbr;
public import dplug.gui.sizeconstraints;

import gamut;

/** 
    PBRBackgroundGUI provides a PBR background loaded from images.
    It blits a background in diffuse, material, and depth channels.
   
    The path to each of these images (given as a template parameter) 
    must be in your "stringImportPaths" settings. 

    Live-reload
    ===========

    Reload images with ENTER and the use of the version identifier:
      "Dplug_EnterReloadBackgrounds" (See Wiki "More Options").
    The skybox isn't reloaded though.


    Note
    ====
    Removed the ability to not keep decompressed images in memory.
    It won about 17mb on Panagement 2, but was only worthwhile in 
    32-bit to save memory addressing space, and it resizing slower.

    For backgrounds you can use any of the codec supported in the
    "audio-plugin" configuration of the `gamut` package:
    QOI, QOIX, PNG, JPEG, SQZ.

*/
class PBRBackgroundGUI(string baseColorPath,
                       string emissivePath,
                       string materialPath,
                       string depthPath,
                       string skyboxPath,
                       string absoluteGfxDir // for development only!
                       ) : GUIGraphics
{
public:
nothrow:
@nogc:

    /** 
        Create the base UI widget with a fixed size constraint.
        This is legacy and for resizeable plug-ins you should prefer
        the below constructor.
    */
    this(int width, int height)
    {
        this(makeSizeConstraintsFixed(width, height));
    }

    /** 
        Create the base UI widget with a given size constraint.
    */
    this(SizeConstraints sizeConstraints)
    {
        super(sizeConstraints, flagPBR 
                             | flagAnimated 
                             | flagDrawAlonePBR);

        _diffuseResized = mallocNew!(OwnedImage!RGBA);
        _materialResized = mallocNew!(OwnedImage!RGBA);
        _depthResized = mallocNew!(OwnedImage!L16);

        loadBackgroundImagesFromStaticData(null);

        auto skyboxData = cast(ubyte[])(import(skyboxPath));
        loadSkybox(skyboxData);
    }

    ~this()
    {
        freeBackgroundImages();
        _diffuseResized.destroyFree();
        _materialResized.destroyFree();
        _depthResized.destroyFree();
    }

    // Development purposes.
    // If this version is enabled, you could press ENTER to
    // reload the backgrounds. Do not ship this!
    version(Dplug_EnterReloadBackgrounds)
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

    override void onDrawPBR(ImageRef!RGBA diffuseMap, 
                            ImageRef!L16 depthMap, 
                            ImageRef!RGBA materialMap, 
                            box2i[] dirtyRects)
    {
        // Resize resource to match _position
        // The background images are resized lazily to match
        // the position of the widget.
        {
            int W = position.width;
            int H = position.height;

            // if size changed, do the resize
            if (_forceResizeUpdate 
                || _diffuseResized.w != W 
                || _diffuseResized.h != H)
            {
                _diffuseResized.size(W, H);
                _materialResized.size(W, H);
                _depthResized.size(W, H);                
                context.globalThreadPool.parallelFor(3, &resizeFun);
                _forceResizeUpdate = false;
            }
        }

        // Just blit backgrounds into dirtyRects.
        foreach(r; dirtyRects)
        {
            auto diffuseIn = _diffuseResized.toRef().cropImageRef(r);
            auto diffuseOut = diffuseMap.cropImageRef(r);

            auto depthIn = _depthResized.toRef().cropImageRef(r);
            auto depthOut = depthMap.cropImageRef(r);

            auto materialIn = _materialResized.toRef().cropImageRef(r);
            auto materialOut = materialMap.cropImageRef(r);

            diffuseIn.blitTo(diffuseOut);
            depthIn.blitTo(depthOut);
            materialIn.blitTo(materialOut);
        }
    }

    override void reflow()
    {
    }

private:

    // is called by 3 different threads
    final void resizeFun(int i, int threadIndex) nothrow @nogc
    {
        ImageResizer resizer;
        if (i == 0)
        {
            version(Dplug_ProfileUI) 
                context.profiler.begin("resize Diffuse background");
            resizer.resizeImageDiffuse(_diffuse.toRef, 
                                       _diffuseResized.toRef);
            version(Dplug_ProfileUI) context.profiler.end;
        }
        if (i == 1)
        {
            version(Dplug_ProfileUI) 
                context.profiler.begin("resize Material background");
            resizer.resizeImageMaterial(_material.toRef, 
                                        _materialResized.toRef);
            version(Dplug_ProfileUI) context.profiler.end;
        }
        if (i == 2)
        {
            version(Dplug_ProfileUI) 
                context.profiler.begin("resize Depth background");
            resizer.resizeImageDepth(_depth.toRef, 
                                     _depthResized.toRef);
            version(Dplug_ProfileUI) context.profiler.end;
        }
    }

    // Load backgrounds.
    // Pass a ThreadPool in the case you want parallel image loading
    // (optional). I'm not sure if this is used.
    final void loadBackgroundImagesFromStaticData(ThreadPool* tpool)
    {
        auto basecolorData = cast(ubyte[])(import(baseColorPath));

        // The emissive map is optional
        static if (emissivePath)
            ubyte[] emissiveData = cast(ubyte[])(import(emissivePath));
        else
            ubyte[] emissiveData = null;

        auto materialData = cast(ubyte[])(import(materialPath));
        auto depthData = cast(ubyte[])(import(depthPath));

        loadBackgroundImages(basecolorData,
                             emissiveData,
                             materialData,
                             depthData,
                             tpool);
    }

    enum dir = absoluteGfxDir;

    static immutable string 
        baseColorPathAbs = dir ~ baseColorPath,
        emissivePathAbs  = emissivePath ? (dir ~ emissivePath) : null,
        materialPathAbs  = dir ~ materialPath,
        depthPathAbs     = dir ~ depthPath,
        skyboxPathAbs    = dir ~ skyboxPath;

    // Loaded diffuse image.
    OwnedImage!RGBA _diffuse;

    // Loaded material image.
    OwnedImage!RGBA _material;

    // Loaded depth image.
    OwnedImage!L16 _depth;

    // Resized diffuse image.
    OwnedImage!RGBA _diffuseResized;
    
    // Resized material image.
    OwnedImage!RGBA _materialResized;
    
    // Resized depth image.
    OwnedImage!L16 _depthResized;

    // Where pixel data is taken in the image, expressed in 
    // `_background` coordinates.
    //box2i _sourceRect;

    // Where it is deposited. Same size than _sourceRect. 
    // Expressed in _position coordinates.
    //box2i _destRect;

    // Offset from source to dest.
    //vec2i _offset;

    // Force resize of source image in order to display changes while
    // editing files.
    bool _forceResizeUpdate;

    void freeBackgroundImages()
    {
        _diffuse.destroyFree();
        _diffuse = null;
        _depth.destroyFree();
        _depth = null;
        _material.destroyFree();
        _material = null;
    }

   
    // Live-reload of images for UI development.
    void reloadImagesAtRuntime()
    {
        // reading images with an absolute path since we don't know
        // which is the current directory from the host
        ubyte[] basecolorData = readFile(baseColorPathAbs);
        ubyte[] emissiveData = emissivePathAbs ? readFile(emissivePathAbs) : null;
        ubyte[] materialData = readFile(materialPathAbs);
        ubyte[] depthData = readFile(depthPathAbs);
        ubyte[] skyboxData = readFile(skyboxPathAbs);

        if (basecolorData && materialData
            && depthData && skyboxData) // all valid?
        {
            // Reload images from disk and update the UI
            freeBackgroundImages();
            loadBackgroundImages(basecolorData, emissiveData, 
                                 materialData, depthData, null);
            loadSkybox(skyboxData);
            _forceResizeUpdate = true;
            setDirtyWhole();
        }
        else
        {
            // Note: if you fail here, the absolute path you provided 
            // in your gui.d was incorrect.
            // The background files cannot be loaded at runtime, and 
            // you have to fix your pathes.
            assert(false);
        }

        // Release copy of file contents
        freeSlice(basecolorData);
        freeSlice(emissiveData);
        freeSlice(materialData);
        freeSlice(depthData);
        freeSlice(skyboxData);
    }

    void loadBackgroundImages(ubyte[] basecolorData,
                              ubyte[] emissiveData, // can be null
                              ubyte[] materialData,
                              ubyte[] depthData,
                              ThreadPool* threadPool)
    {
        // Potentially load all 3 background images in parallel, 
        // if one threadPool is provided.
        void loadOneImage(int i, int threadIndex) nothrow @nogc
        {
            ImageResizer resizer;
            if (i == 0)
            {
                version(Dplug_ProfileUI) 
                    context.profiler
                    .category("image")
                    .begin("load Diffuse background");

                if (emissiveData)
                    _diffuse = loadImageSeparateAlpha(basecolorData, emissiveData);
                else
                {
                    // fill with zero, no emissive data => zero Emissive
                    _diffuse = loadImageWithFilledAlpha(basecolorData, 0);
                }

                version(Dplug_ProfileUI) context.profiler.end;
            }
            if (i == 1)
            {
                version(Dplug_ProfileUI) 
                    context.profiler.begin("load Material background");

                _material = loadOwnedImage(materialData);

                version(Dplug_ProfileUI) context.profiler.end;
            }
            if (i == 2) 
            {
                version(Dplug_ProfileUI) 
                    context.profiler.begin("load Depth background");

                _depth = loadOwnedImageDepth(depthData);

                version(Dplug_ProfileUI) context.profiler.end;
            }
        }
        if (threadPool)
        {
            threadPool.parallelFor(3, &loadOneImage);
        }
        else
        {
            loadOneImage(0, -1);
            loadOneImage(1, -1);
            loadOneImage(2, -1);
        }
    }

    // unlike the others, this is called only once, no live-reload
    void loadSkybox(ubyte[] skyboxData)
    {
        // Search for a pass of type PassSkyboxReflections
        if (auto mpc = cast(MultipassCompositor) compositor())
        {
            foreach(pass; mpc.passes())
            {
                if (auto skyreflPass = cast(PassSkyboxReflections)pass)
                {
                    version(Dplug_ProfileUI) 
                        context.profiler
                        .category("image")
                        .begin("load Skybox");
                    OwnedImage!RGBA skybox = loadOwnedImage(skyboxData);

                    // pass image ownership to PassSkyboxReflections
                    skyreflPass.setSkybox(skybox);
                    version(Dplug_ProfileUI) context.profiler.end;
                }
            }
        }
    }
}

