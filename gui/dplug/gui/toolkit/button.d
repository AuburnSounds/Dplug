module dplug.gui.toolkit.button;

import std.algorithm;
import dplug.gui.toolkit.element;

class UIButton : UIElement
{
public:    

    this(UIContext context, dstring label, string icon = null)
    {
        super(context);
        _label = label;
        
        _paddingW = 8;
        _paddingH = 4;
        _icon = icon;
        _iconWidth = 0;
        _iconHeight = 0;
        if (_icon !is null)
        {
            _iconImage = context.image(icon);
            _iconWidth = _iconImage.w;
            _iconHeight = _iconImage.h;
        }
    }

    enum marginIcon = 6;

    override void reflow(box2i availableSpace)
    {
        int width = 2 * _paddingW + cast(int) _label.length * font.charWidth;
        if (_icon !is null)
            width += marginIcon + _iconWidth;
        int height = 2 * _paddingH + font.charHeight;
        _position = box2i(availableSpace.min.x, availableSpace.min.y, availableSpace.min.x + width, availableSpace.min.y + height);        
    }

    override void preRender(UIRenderer renderer)
    {
        if (isMouseOver())
        {
            renderer.setColor(30, 27, 27, 255);
            renderer.fillRect(1, 1, _position.width - 2, _position.height -2);
        }

        if (isMouseOver())
            renderer.setColor(70, 67, 67, 255);
        else
            renderer.setColor(30, 27, 27, 255);

        renderer.drawRect(0, 0, _position.width, _position.height);

        if (isMouseOver())
            font.setColor(255, 255, 200);
        else
            font.setColor(200, 200, 200);

        dstring textChoice = _label;
        int heightOfText = font.charHeight;
        int widthOfTextPlusIcon = font.charWidth * cast(int) textChoice.length;
        if (_icon !is null)
            widthOfTextPlusIcon += marginIcon + _iconWidth;

        int iconX = 1 + (position.width - widthOfTextPlusIcon) / 2;
        int textX = iconX;
        if (_icon !is null)
        {
            textX += marginIcon + _iconWidth;
            renderer.copy(_iconImage, iconX, 1 + (position.height - _iconHeight) / 2);
        }
        font.renderString(textChoice, textX, 1 + (position.height - heightOfText) / 2);
    }

private:
    dstring _label;
    int _paddingW;
    int _paddingH;
    string _icon;
    int _iconWidth;
    int _iconHeight;
    Image!RGBA _iconImage;
}

class UIImage : UIElement
{
public:
    this(UIContext context, string imageName)
    {
        super(context);
        _tex = context.image(imageName);
        _width = _tex.w;
        _height = _tex.h;
    }

    override void preRender(UIRenderer renderer)
    {
        renderer.copy(_tex, 0, 0);
    }

    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;

        // TODO leave this logic out of UIImage
        _position.min.x = _position.max.x - _width;
        _position.min.y = _position.max.y - _height;
    }

private:
    Image!RGBA _tex;
    int _width;
    int _height;
}
