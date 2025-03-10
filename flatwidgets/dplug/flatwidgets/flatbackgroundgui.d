/**
The root widget to inherit from for a flat UI.

Copyright: Guillaume Piolat 2015-2018.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flatwidgets.flatbackgroundgui;

import dplug.math.box;
import dplug.core.nogc;
import dplug.core.file;
import dplug.graphics;

import dplug.core.nogc;
import dplug.gui.graphics;
import dplug.gui.element;
public import dplug.gui.sizeconstraints;


/// FlatBackgroundGUI provides a background that is loaded from a PNG or JPEG
/// image. The string for backgroundPath should be in "stringImportPaths"
/// specified in dub.json
class FlatBackgroundGUI(string backgroundPath,
                        string absoluteGfxDirectory = null // for UI development only
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
        super(sizeConstraints, flagRaw | flagAnimated);
        _backgroundImageResized = mallocNew!(OwnedImage!RGBA)();
        loadBackgroundImageFromStaticData();
    }
    
    ~this()
    {
        freeBackgroundImage();
        _backgroundImageResized.destroyFree();
    }
    
    override void reflow()
    {
    }
    
    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        // Resize resources to match actual size.
        {
            int W = position.width;
            int H = position.height;
            if (_forceResizeUpdate || _backgroundImageResized.w != W || _backgroundImageResized.h != H)
            {
                _backgroundImageResized.size(W, H);
                ImageResizer resizer;
                resizer.resizeImage_sRGBNoAlpha(_backgroundImage.toRef, _backgroundImageResized.toRef);
                _forceResizeUpdate = false;
            }
        }

        ImageRef!RGBA backgroundRef = _backgroundImageResized.toRef();

        foreach(dirtyRect; dirtyRects)
        {
            ImageRef!RGBA croppedRawIn = backgroundRef.cropImageRef(dirtyRect);
            ImageRef!RGBA croppedRawOut = rawMap.cropImageRef(dirtyRect);
            croppedRawIn.blitTo(croppedRawOut);
        }
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
                reloadImageAtRuntime();
                return true;
            }

            return false;
        }
    }

private:
    OwnedImage!RGBA _backgroundImage, _backgroundImageResized;

    /// Where pixel data is taken in the image, expressed in _background coordinates.
    box2i _sourceRect;

    /// Where it is deposited. Same size than _sourceRect. Expressed in _position coordinates.
    box2i _destRect;

    /// Offset from source to dest.
    vec2i _offset;

    /// Force resize of source image in order to display changes while editing files.
    bool _forceResizeUpdate;

    static immutable string backgroundPathAbs = absoluteGfxDirectory ~ backgroundPath;

    final void loadBackgroundImageFromStaticData()
    {
        auto backgroundData = cast(ubyte[])(import(backgroundPath));
        loadBackgroundImage(backgroundData);
    }

    // Reloads image for UI development.
    final void reloadImageAtRuntime()
    {
        // reading images with an absolute path since we don't know 
        // which is the current directory from the host
        ubyte[] backgroundData = readFile(backgroundPathAbs);

        if (backgroundData)
        {
            // Reload images from disk and update the UI
            freeBackgroundImage();
            loadBackgroundImage(backgroundData);
            _forceResizeUpdate = true;
            setDirtyWhole();
        }
        else
        {
            // Note: if you fail here, the absolute path you provided in your gui.d was incorrect.
            // The background files cannot be loaded at runtime, and you have to fix your pathes.
            assert(false);
        }

        freeSlice(backgroundData);
    }

    final void loadBackgroundImage(ubyte[] backgroundData)
    {
        _backgroundImage = loadOwnedImage(backgroundData);
    }

    void freeBackgroundImage()
    {
        if (_backgroundImage)
        {
            _backgroundImage.destroyFree();
            _backgroundImage = null;
        }
    }
}