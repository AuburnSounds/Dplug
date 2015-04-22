module dplug.gui.toolkit.scrollbar;

import std.algorithm;

import gfm.math;
import dplug.gui.toolkit.element;

class ScrollBar : UIElement
{
public:    

    this(UIContext context, int thicknessOfFocusBar, int padding, bool vertical)
    {
        super(context);
        _vertical = vertical;
        _thicknessOfFocusBar = thicknessOfFocusBar;
        _padding = padding;
        setProgress(0.45f, 0.55f);
    }

    // Called whenever a scrollbar move is done. Override it to change behaviour.
    void onScrollChangeMouse(float newProgressStart)
    {
        // do nothing
    }

    int thickness() pure const nothrow
    {
        return _thicknessOfFocusBar + 2 * _padding;
    }

    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;

        if (_vertical)
        {
            _position.min.x = _position.max.x - thickness();
        }
        else
        {
            _position.min.y = _position.max.y - thickness();
        }
    }

    override void preRender(UIRenderer renderer)
    {
        // Do not display useless scrollbar
        if (_progressStart <= 0.0f && _progressStop >= 1.0f)
            return;

        renderer.setColor(0x30, 0x2C, 0x2C, 255);
        renderer.fillRect(0, 0, _position.width, _position.height);
        
        if (isMouseOver())
            renderer.setColor(120, 120, 120, 255);
        else
            renderer.setColor( 80,  80,  80, 255);

        box2i focus = getFocusBox();
        roundedRect(renderer, focus);
    }

    void roundedRect(UIRenderer renderer, box2i b)
    {
        if (b.height > 2 && b.width > 2)
        {
            renderer.fillRect(b.min.x + 1, b.min.y    , b.width - 2, 1);
            renderer.fillRect(b.min.x    , b.min.y + 1, b.width    , b.height - 2);
            renderer.fillRect(b.min.x + 1, b.max.y - 1, b.width - 2, 1);
        }
        else
            renderer.fillRect(b.min.x, b.min.y, b.width, b.height);
    }

    void setProgress(float progressStart, float progressStop)
    {
        _progressStart = clamp!float(progressStart, 0.0f, 1.0f);
        _progressStop = clamp!float(progressStop, 0.0f, 1.0f);
        if (_progressStop < _progressStart)
            _progressStop = _progressStart;
    }

    override bool onMousePostClick(int x, int y, int button, bool isDoubleClick)
    {        
        float clickProgress;
        if (_vertical)
        {
            int heightWithoutButton = _position.height;
            clickProgress = cast(float)(y) / heightWithoutButton;
        }
        else
        {
            int widthWithoutButton = _position.width;
            clickProgress = cast(float)(x) / widthWithoutButton;
        }

        // now this clickProgress should move the _center_ of the scrollbar to it
        float newStartProgress = clickProgress - (_progressStop - _progressStart) * 0.5f;

        onScrollChangeMouse(newStartProgress);
        return true;
    }

    // Called when mouse move over this Element.
    override void onMouseDrag(int x, int y, int dx, int dy)
    {
        float clickProgress;
        if (_vertical)
        {
            int heightWithoutButton = _position.height;
            clickProgress = cast(float)(dy) / heightWithoutButton;
        }
        else
        {
            int widthWithoutButton = _position.width;
            clickProgress = cast(float)(dx) / widthWithoutButton;
        }
        onScrollChangeMouse(_progressStart + clickProgress);
    }

private:

    int _thicknessOfFocusBar;
    int _padding;

    bool _vertical;
    float _progressStart;
    float _progressStop;

    box2i getFocusBox()
    {
        if (_vertical)
        {
            int iprogressStart = cast(int)(0.5f + _progressStart * (_position.height - 2 * _padding));
            int iprogressStop = cast(int)(0.5f + _progressStop * (_position.height - 2 * _padding));
            int x = _padding;
            int y = iprogressStart + _padding;
            return box2i(x, y, x + _position.width - 2 * _padding, y + iprogressStop - iprogressStart);
        }
        else
        {
            int iprogressStart = cast(int)(0.5f + _progressStart * (_position.width - 2 * _padding));
            int iprogressStop = cast(int)(0.5f + _progressStop * (_position.width - 2 * _padding));
            int x = iprogressStart + _padding;
            int y = _padding;
            return box2i(x, y, x + iprogressStop - iprogressStart, y + _position.height - 2 * _padding);
        }
    }
    
}