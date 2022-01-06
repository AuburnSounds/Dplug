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
class FlatBackgroundGUI(string backgroundPath) : GUIGraphics
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
        _backgroundImage = loadOwnedImage(cast(ubyte[])(import(backgroundPath)));
        _backgroundImageResized = mallocNew!(OwnedImage!RGBA)();
    }
    
    ~this()
    {
        _backgroundImage.destroyFree();
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
            if (_backgroundImageResized.w != W || _backgroundImageResized.h != H)
            {
                _backgroundImageResized.size(W, H);
                ImageResizer resizer;
                resizer.resizeImage_sRGBNoAlpha(_backgroundImage.toRef, _backgroundImageResized.toRef);
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
    
private:
    OwnedImage!RGBA _backgroundImage, _backgroundImageResized;

    /// Where pixel data is taken in the image, expressed in _background coordinates.
    box2i _sourceRect;

    /// Where it is deposited. Same size than _sourceRect. Expressed in _position coordinates.
    box2i _destRect;

    /// Offset from source to dest.
    vec2i _offset;
}