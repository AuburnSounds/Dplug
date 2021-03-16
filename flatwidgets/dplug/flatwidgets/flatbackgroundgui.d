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
import dplug.graphics.color;
import dplug.graphics.image;
import dplug.graphics.view;
import dplug.graphics.drawex;

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
        super(sizeConstraints, flagRaw);
        _backgroundImage = loadOwnedImage(cast(ubyte[])(import(backgroundPath)));
    }
    
    ~this()
    {
        if(_backgroundImage)
            _backgroundImage.destroyFree();
    }
    
    override void reflow()
    {
        // Note: the position is entirely decorrelated from the size of _backgroundImage

        // Compute which rect of _backgroundImage goes into which rect of _position
        // if the full element was entirely dirty
        // The image is not resized to fit, instead it is cropped.
        int sourceX;
        int sourceY;
        int destX;
        int destY;
        int width;
        int height;
        if (_position.width >= _backgroundImage.w)
        {
            width = _backgroundImage.w;
            sourceX = 0;
            destX = 0;
        }
        else
        {
            width = _position.width;
            sourceX = 0;
            destX = 0;
        }

        if (_position.height >= _backgroundImage.h)
        {
            height = _backgroundImage.h;
            sourceY = 0;
            destY = 0;
        }
        else
        {
            height = _position.height;
            sourceY = 0;
            destY = 0;
        }

        _sourceRect = box2i.rectangle(sourceX, sourceY, width, height);
        _destRect = box2i.rectangle(destX, destY, width, height);
        _offset = vec2i(destX - sourceX, destY - sourceY);
    }
    
    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        auto backgroundRef = _backgroundImage.toRef();

        foreach(dirtyRect; dirtyRects)
        {
            // Compute source and dest
            box2i source = _sourceRect.intersection(dirtyRect.translate(_offset));
            box2i dest = _destRect.intersection(dirtyRect); // since dirtyRect is relative to _position 
            if (source.empty())
                continue;
            if (dest.empty())
                continue;

            assert(source.width == dest.width);
            assert(source.height == dest.height);
            
            int W = dest.width;
            int H = dest.height;

            auto croppedRawIn = backgroundRef.cropImageRef(source);
            auto croppedRawOut = rawMap.cropImageRef(dest);

            immutable RGBA inputMaterial = RGBA(0, 0, 0, 0);
            immutable L16 inputDepth = L16(0);

            for(int j = 0; j < H; ++j)
            {
                RGBA[] inputRaw = croppedRawIn.scanline(j);
                RGBA[] outputRaw = croppedRawOut.scanline(j);

                for(int i = 0; i < W; ++i)
                {
                    outputRaw[i] = inputRaw[i];
                }
            }
        }
    }
    
private:
    OwnedImage!RGBA _backgroundImage;

    /// Where pixel data is taken in the image, expressed in _background coordinates.
    box2i _sourceRect;

    /// Where it is deposited. Same size than _sourceRect. Expressed in _position coordinates.
    box2i _destRect;

    /// Offset from source to dest.
    vec2i _offset;
}