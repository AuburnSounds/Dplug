/**
Static text label.

Copyright: Copyright Auburn Sounds 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors:   Guillaume Piolat
*/
module dplug.pbrwidgets.label;

import std.math;
import dplug.gui.element;
import dplug.client.params;

/// Simple area with text.
class UILabel : UIElement
{
public:
nothrow:
@nogc:

    /// Sets to true if this is clickable
    bool clickable = false;
    string targetURL = "http://example.com";

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
        setDirtyWhole();
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
        setDirtyWhole();
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
        setDirtyWhole();
        return _textSize = textSize_;
    }

    float letterSpacing()
    {
        return _letterSpacing;
    }

    float letterSpacing(float letterSpacing_)
    {
        setDirtyWhole();
        return _letterSpacing = letterSpacing_;
    }

    /// Returns: Diffuse color of displayed text.
    RGBA textColor()
    {
        return _textColor;
    }

    /// Sets diffuse color of displayed text.
    RGBA textColor(RGBA textColor_)
    {
        setDirtyWhole();
        return _textColor = textColor_;
    }

    override void onBeginDrag() 
    {
        if (clickable)
            setDirtyWhole();
    }

    override void onStopDrag()  
    {
        if (clickable)
            setDirtyWhole();
    }

    override void onMouseEnter() 
    {
        if (clickable)
            setDirtyWhole();
    }

    override void onMouseExit()
    {
        if (clickable)
            setDirtyWhole();
    }    

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate) 
    {
        if (clickable)
        {
            browseNoGC(targetURL);
            return true;
        }
        return false;
    }    

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        float textPosx = position.width * 0.5f;
        float textPosy = position.height * 0.5f;
        // only draw text which is in dirty areas

        RGBA diffuse = _textColor;
        int emissive = _textColor.a;
        bool underline = false;

        if (clickable && isMouseOver)
        {
            emissive += 40;
            underline = true;
        }
        else if (clickable && isDragged)
        {
            emissive += 80;
            underline = true;
        }
        if (emissive > 255)
            emissive = 255;
        diffuse.a = cast(ubyte)(emissive);

        // MAYDO: implement underline?

        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.cropImageRef(dirtyRect);
            vec2f positionInDirty = vec2f(textPosx, textPosy) - dirtyRect.min;
            croppedDiffuse.fillText(_font, _text, _textSize, _letterSpacing, diffuse, positionInDirty.x, positionInDirty.y);
        }
    }

    // Sets _position and resize automatically to adjust with text size and content. 
    void setCenterAndResize(int x, int y) nothrow @nogc
    {
        box2i textDimensions = _font.measureText(_text, _textSize, _letterSpacing);
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

    /// Size of displayed text in pixels.
    float _textSize = 16.0f;

    /// Additional space between letters, in pixels.
    float _letterSpacing = 0.0f;

    /// Diffuse color of displayed text.
    RGBA _textColor = RGBA(0, 0, 0, 0);
}
