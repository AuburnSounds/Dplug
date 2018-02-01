/**
 * Widget for displaying an editable textbox.  User must click on widget to edit,
 * and mouse must be over box while editing.
 *
 * Copyright: Copyright Auburn Sounds 2015-2017.
 * Copyright: Cut Through Recordings 2017.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Ethan Reker
 */
module dplug.pbrwidgets.textbox;

import dplug.gui.element;
import dplug.core.nogc;

private import core.stdc.stdlib : malloc, free;
private import core.stdc.stdio : snprintf, printf;
private import core.stdc.string : strcmp, strlen;

class UITextbox : UIElement
{
public:
nothrow:
@nogc:
    
    this(UIContext context, Font font, int textSize, RGBA textColor = RGBA(200, 200, 200, 255), RGBA backgroundColor = RGBA(0, 0, 0, 255))
    {
        super(context);
        _font = font;
        _textSize = textSize;
        _textColor = textColor;
        _backgroundColor = backgroundColor;
        charBuffer = mallocNew!CharStack(512);
    }
    
    ~this()
    {
        charBuffer.destroyFree();
    }

    @property const(char)[] getText()
    {
        return displayString();
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        float textPosx = position.width * 0.5f;
        float textPosy = position.height * 0.5f;

        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.cropImageRef(dirtyRect);
            vec2f positionInDirty = vec2f(textPosx, textPosy) - dirtyRect.min;

            croppedDiffuse.fillAll(_backgroundColor);
            croppedDiffuse.fillText(_font, displayString(), _textSize, 0.5, _textColor, positionInDirty.x, positionInDirty.y);
        }
    }
    
    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // Left click
        _isActive = true;

        setDirtyWhole();
        return true;
    }

    override void onMouseEnter()
    {
        setDirtyWhole();
    }

    override void onMouseMove(int x, int y, int dx, int dy, MouseState mstate)
    {
        
    }

    override void onMouseExit()
    {
        _isActive = false;
        setDirtyWhole();
    }

    override void onBeginDrag()
    {

    }

    override void onStopDrag()
    {

    }
    
    override void onMouseDrag(int x, int y, int dx, int dy, MouseState mstate)
    {

        
    }
    
    override bool onKeyDown(Key key)
    {
        if(_isActive)
        {
            const char c = getCharFromKey(key);
            if(c == '\t')
                charBuffer.pop();
            else if(c != '\0')
                charBuffer.push(c);
            setDirtyWhole();
            return true;
        }
        
        return false;
    }

private:
    
    Font _font;
    int _textSize;
    RGBA _textColor;
    RGBA _backgroundColor;
    bool _isActive;
    char[] stringBuf;
    CharStack charBuffer;

    const(char)[] displayString() nothrow @nogc
    {
        stringBuf = charBuffer.ptr[0..strlen(charBuffer.ptr)];
        return stringBuf[0..strlen(charBuffer.ptr)];
    }

    final bool containsPoint(int x, int y)
    {
        box2i subSquare = getSubsquare();
        float centerx = (subSquare.min.x + subSquare.max.x - 1) * 0.5f;
        float centery = (subSquare.min.y + subSquare.max.y - 1) * 0.5f;

        float minx = centerx - (_position.width / 2);
        float maxx = centerx + (_position.width / 2);
        float miny = centery - (_position.height / 2);
        float maxy = centery + (_position.height / 2);

        return x > minx && x < maxx && y > miny && y < maxy;
    }

    /// Returns: largest square centered in _position
    final box2i getSubsquare() pure const
    {
        // We'll draw entirely in the largest centered square in _position.
        box2i subSquare;
        if (_position.width > _position.height)
        {
            int offset = (_position.width - _position.height) / 2;
            int minX = offset;
            subSquare = box2i(minX, 0, minX + _position.height, _position.height);
        }
        else
        {
            int offset = (_position.height - _position.width) / 2;
            int minY = offset;
            subSquare = box2i(0, minY, _position.width, minY + _position.width);
        }
        return subSquare;
    }

    final float getRadius() pure const
    {
        return getSubsquare().width * 0.5f;

    }

    final vec2f getCenter() pure const
    {
        box2i subSquare = getSubsquare();
        float centerx = (subSquare.min.x + subSquare.max.x - 1) * 0.5f;
        float centery = (subSquare.min.y + subSquare.max.y - 1) * 0.5f;
        return vec2f(centerx, centery);
    }
    
}

private char getCharFromKey(Key key) nothrow @nogc
{
    switch(key)
    {
        case Key.backspace: return '\t';
        case Key.digit0: .. case Key.digit9: return cast(char)('0' + (key - Key.digit0));
        case Key.a: .. case Key.z: return cast(char)('a' + (key - Key.a));
        case Key.A: .. case Key.Z: return cast(char)('A' + (key - Key.A));
        case Key.space : return ' ';
        default: return '\0';
    }
}

/// Simple stack of chars with the last being the null-terminator
private class CharStack
{
public:
nothrow:
@nogc:
    this(int maxSize)
    {
        if(maxSize > 0)
        {
            buffer = cast(char*)malloc(char.sizeof * maxSize);
            buffer[0] = '\0';
            actualLength = 0;
            assert(strcmp(buffer, "") == 0);
        }
    }
    
    ~this()
    {
        free(buffer);
    }

    void push(const char c)
    {
        if(actualLength + 1 <= 512)
        {
            buffer[actualLength] = c;
            ++actualLength;
            buffer[actualLength] = '\0';

        }
    }

    @property pop()
    {
        if(actualLength > 0)
        {
            --actualLength;
            buffer[actualLength] = '\0';
        }
    }
    
    @property length()
    {
        return actualLength;
    }
    
    @property ptr()
    {
        return buffer;
    }

private:
    char* buffer;
    size_t actualLength;
}

