module dplug.gui.toolkit.label;

import std.math;
import dplug.gui.toolkit.element;
import dplug.plugin.params;

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

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i dirtyRect)
    {
        auto croppedDiffuse = dirtyView(diffuseMap);        
        _font.size = _textSize;
        _font.color = _textColor;
        croppedDiffuse.fillText(_font, _text, croppedDiffuse.w * 0.5f, croppedDiffuse.h * 0.5f);
    }

protected:

    /// The font used for text.
    Font _font;

    /// Sensivity: given a mouse movement in 100th of the height of the knob, 
    /// how much should the normalized parameter change.
    string _text;

    /// Size of displayed text.
    float _textSize;

    /// Diffuse color of displayed text.
    RGBA _textColor;
}
