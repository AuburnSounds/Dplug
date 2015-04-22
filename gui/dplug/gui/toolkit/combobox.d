module dplug.gui.toolkit.combobox;

import std.algorithm;

import gfm.math;

import dplug.gui.toolkit.element;

class ComboBox : UIElement
{
public:    

    this(UIContext context, dstring[] labels, dstring[] choices, string icon = null)
    {
        super(context);
        _labels = labels;
        _choices = choices;
        assert(_labels.length == _choices.length);
        _select = -1;
        
        _paddingW = 8;
        _paddingH = 4;
        setSelectedChoice(0);     

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

    final void setSelectedChoice(int n)
    {
        if (_select != n)
        {
            _select = n;
            onChoice(n);
        }
    }

    // Called whenever a combobox is selected.
    void onChoice(int n)
    {
        // do nothing
    }

    override void reflow(box2i availableSpace)
    {
        int width = 2 * _paddingW + longestStringLength() * font.charWidth;
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

        dstring textChoice = label(_select);
        int heightOfText = font.charHeight;
        int widthOfText = font.charWidth * cast(int) textChoice.length;
        int iconX = _paddingW;
        int availableWidthForText = position.width - ((_icon is null) ? 0 : (marginIcon + _iconWidth));
        int textX = 1 + (availableWidthForText - widthOfText) / 2;
        if (_icon !is null)
        {
            textX += marginIcon + _iconWidth;
            renderer.copy(_iconImage, iconX, 1 + (position.height - _iconHeight) / 2);
        }
        font.renderString(textChoice, textX, 1 + (position.height - heightOfText) / 2);
    }

    override bool onMousePostClick(int x, int y, int button, bool isDoubleClick)
    {
        if (_choices.length == 0)
            return false;
        setSelectedChoice((_select + 1) % cast(int) _choices.length);
        return true;
    }

    // Called when mouse move over this Element.
    override void onMouseMove(int x, int y, int dx, int dy)
    {
    }

    // Called when mouse enter this Element.
    override void onMouseExit()
    {
    }

    dstring choice(int n)
    {
        return _choices[n];
    }

    dstring label(int n)
    {
        return _labels[n];
    }

private:

    int _select;
    int _paddingW;
    int _paddingH;

    string _icon;
    int _iconWidth;
    int _iconHeight;
    Image!RGBA _iconImage;

    dstring[] _labels;
    dstring[] _choices;

    int longestStringLength()
    {
        int maximum = 0;
        foreach(ref dstring c; _labels)
        {
            if (maximum < cast(int) c.length)
                maximum = cast(int) c.length;
        }
        return maximum;
    }
}