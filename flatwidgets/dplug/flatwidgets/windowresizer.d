/**
A widget to place at the bottom-right of your UI. It allows the usze to resize the plugin.

Copyright: Guillaume Piolat 2021.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.flatwidgets.windowresizer;

// THIS IS A WORK IN PROGRESS, DOESN'T WORK YET.

import dplug.gui.element;
import dplug.canvas;


class UIWindowResizer : UIElement
{
public:
nothrow:
@nogc:

    RGBA color        = RGBA(255, 255, 255, 96);
    RGBA colorHovered = RGBA(255, 255, 255, 140);
    RGBA colorDragged = RGBA(255, 255, 128, 200);
    RGBA colorCannotResize = RGBA(255, 96, 96, 200);

    float failureDisplayTime = 1.2f; // Time in seconds spent indicating failure to resize.

    /// Construct a new `UIWindowResizer`.
    /// Recommended size is around 20x20 whatever the UI size, and on the bottom-right.
    this(UIContext context)
    {
        super(context, flagRaw | flagAnimated);
        setCursorWhenMouseOver(MouseCursor.diagonalResize);
        setCursorWhenDragged(MouseCursor.diagonalResize);
    }

    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // Initiate drag
        setDirtyWhole();

        _sizeBeforeDrag = context.getUISizeInPixelsLogical();
        _accumX = 0;
        _accumY = 0;

        return true;
    }

    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {
        vec2i size = _sizeBeforeDrag;

        // Cumulative mouse movement since dragging started
        _accumX += dx; // TODO: divide that by user scale
        _accumY += dy;
        size.x += _accumX;
        size.y += _accumY;

        // Find nearest valid _logical_ size.
        context.getUINearestValidSize(&size.x, &size.y);

        // Attempt to resize window with that size.
        bool success = context.requestUIResize(size.x, size.y);

        if (!success)
        {
            _timeDisplayError = failureDisplayTime;
        }
    }

    override void onAnimate(double dt, double time) nothrow @nogc
    {
        if (_timeDisplayError > 0.0f)
        {
            _timeDisplayError = _timeDisplayError - dt;
            if (_timeDisplayError < 0) _timeDisplayError = 0;
            setDirtyWhole();
        }
    }

    override void onDrawRaw(ImageRef!RGBA rawMap, box2i[] dirtyRects)
    {
        float w = position.width;
        float h = position.height;

        foreach(dirtyRect; dirtyRects)
        {
            auto cRaw = rawMap.cropImageRef(dirtyRect);
            canvas.initialize(cRaw);
            canvas.translate(-dirtyRect.min.x, -dirtyRect.min.y);

            // Makes a 3 lines hint like in JUCE or iZotope plugins.
            // This seems to be easiest to understand for users.

            RGBA c = color;
            if (isMouseOver) 
                c = colorHovered;
            if (isDragged) 
                c = colorDragged;
            if (_timeDisplayError > 0)
                c = colorCannotResize;

            canvas.fillStyle = c;

            canvas.beginPath;
            canvas.moveTo(w*0/5, h*5/5);
            canvas.lineTo(w*5/5, h*0/5);
            canvas.lineTo(w*5/5, h*1/5);
            canvas.lineTo(w*1/5, h*5/5);
            canvas.lineTo(w*0/5, h*5/5);

            canvas.moveTo(w*2/5, h*5/5);
            canvas.lineTo(w*5/5, h*2/5);
            canvas.lineTo(w*5/5, h*3/5);
            canvas.lineTo(w*3/5, h*5/5);
            canvas.lineTo(w*2/5, h*5/5);

            canvas.moveTo(w*4/5, h*5/5);
            canvas.lineTo(w*5/5, h*4/5);
            canvas.lineTo(w*5/5, h*5/5);
            canvas.lineTo(w*4/5, h*5/5);

            canvas.fill();
        }
    }

    override bool contains(int x, int y)
    {
        if (!context.isUIResizable())
            return false; // not clickable if UI not resizeable

        return super.contains(x, y);
    }

    // Account for color changes

    override void onBeginDrag()
    {
        setDirtyWhole();
    }

    override void onStopDrag()
    {
        setDirtyWhole();
    }

    override void onMouseEnter()
    {
        setDirtyWhole();
    }

    override void onMouseExit()
    {
        setDirtyWhole();
    }

private:
    Canvas canvas;
    vec2i _sizeBeforeDrag;
    int _accumX;
    int _accumY;

    float _timeDisplayError = 0.0f;
} 