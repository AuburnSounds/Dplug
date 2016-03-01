/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.label;

import std.math;
import dplug.gui.element;
import dplug.client.params;

/// Simple area with text.
class UILabel : UIElement
{
public:

    this(UIContext context, Font font, string text = "")
    {
        super(context);
        _text = text;
        _font = font;
    }

    /// Returns: Font used.
    Font font()
    {
        return _font;
    }

    /// Sets text size.
    Font font(Font font_)
    {
        setDirty();
        return _font = font_;
    }

    /// Returns: Displayed text.
    string text()
    {
        return _text;
    }

    /// Sets displayed text.
    string text(string text_)
    {
        setDirty();
        return _text = text_;
    }

    /// Returns: Size of displayed text.
    float textSize()
    {
        return _textSize;
    }

    /// Sets size of displayed text.
    float textSize(float textSize_)
    {
        setDirty();
        return _textSize = textSize_;
    }

    /// Returns: Diffuse color of displayed text.
    RGBA textColor()
    {
        return _textColor;
    }

    /// Sets diffuse color of displayed text.
    RGBA textColor(RGBA textColor_)
    {
        setDirty();
        return _textColor = textColor_;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        // only draw text which is in dirty areas
        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.cropImageRef(dirtyRect);
            vec2f positionInDirty = vec2f(diffuseMap.w * 0.5f, diffuseMap.h * 0.5f) - dirtyRect.min;
            croppedDiffuse.fillText(_font, _text, _textSize, _textColor, positionInDirty.x, positionInDirty.y);
        }
    }

    // Sets _position and resize automatically to adjust with text size and content. 
    void setCenterAndResize(int x, int y)
    {
        box2i textDimensions = _font.measureText(_text, _textSize);
        int bx = x - textDimensions.width/2 - 1;
        int by = y - textDimensions.height/2 - 1;
        int w = textDimensions.width/2 + 1;
        int h = textDimensions.height/2 + 1;
        _position = box2i(bx, by, x + w, y + h);
    }

protected:

    /// The font used for text.
    Font _font;

    /// Text to draw
    string _text;

    /// Size of displayed text.
    float _textSize = 16.0f;

    /// Diffuse color of displayed text.
    RGBA _textColor = RGBA(0, 0, 0, 0);
}
