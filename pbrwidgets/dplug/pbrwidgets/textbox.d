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
    
    this(UIContext context, Font font, int textSize, RGBA color)
    {
        super(context);
        _font = font;
        _textSize = textSize;
        _color = color;
        charBuffer = mallocNew!CharStack(512);
    }
    
    ~this()
    {
        charBuffer.destroyFree();
    }
    
    const(char)[] displayString() nothrow @nogc
    {
        stringBuf = charBuffer.ptr[0..strlen(charBuffer.ptr)];
        return stringBuf[0..strlen(charBuffer.ptr)];
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects) nothrow @nogc
    {
        float textPosx = position.width * 0.5f;
        float textPosy = position.height * 0.5f;
        RGBA backgroundDiffuse = RGBA(100, 100, 100, 255);
        if(_isActive)
            backgroundDiffuse = RGBA(0, 0, 0, 255);

        foreach(dirtyRect; dirtyRects)
        {
            auto croppedDiffuse = diffuseMap.cropImageRef(dirtyRect);
            vec2f positionInDirty = vec2f(textPosx, textPosy) - dirtyRect.min;

			croppedDiffuse.fillAll(backgroundDiffuse);
            croppedDiffuse.fillText(_font, displayString(), _textSize, 0.5, _color, positionInDirty.x, positionInDirty.y);
        }
    }
    
    override bool onMouseClick(int x, int y, int button, bool isDoubleClick, MouseState mstate)
    {
        // Left click
        if(containsPoint(x, y))
        {
            _isActive = true;
        }
        else
        {
            _isActive = false;
        }
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
    RGBA _color;
    bool _isActive;
    char[] stringBuf;
    CharStack charBuffer;

    final bool containsPoint(int x, int y)
    {
        vec2f center = getCenter();
        return vec2f(x, y).distanceTo(center) < getRadius();
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
        case Key.a:  return 'a';
        case Key.b:  return 'b';
        case Key.c:  return 'c';
        case Key.d:  return 'd';
        case Key.e:  return 'e';
        case Key.f:  return 'f';
        case Key.g:  return 'g';
        case Key.h:  return 'h';
        case Key.i:  return 'i';
        case Key.j:  return 'j';
        case Key.k:  return 'k';
        case Key.l:  return 'l';
        case Key.m:  return 'm';
        case Key.n:  return 'n';
        case Key.o:  return 'o';
        case Key.p:  return 'p';
        case Key.q:  return 'q';
        case Key.r:  return 'r';
        case Key.s:  return 's';
        case Key.t:  return 't';
        case Key.u:  return 'u';
        case Key.v:  return 'v';
        case Key.w:  return 'w';
        case Key.x:  return 'x';
        case Key.y:  return 'y';
        case Key.z:  return 'z';
        case Key.A:  return 'A';
        case Key.B:  return 'B';
        case Key.C:  return 'C';
        case Key.D:  return 'D';
        case Key.E:  return 'E';
        case Key.F:  return 'F';
        case Key.G:  return 'G';
        case Key.H:  return 'H';
        case Key.I:  return 'I';
        case Key.J:  return 'J';
        case Key.K:  return 'K';
        case Key.L:  return 'L';
        case Key.M:  return 'M';
        case Key.N:  return 'N';
        case Key.O:  return 'O';
        case Key.P:  return 'P';
        case Key.Q:  return 'Q';
        case Key.R:  return 'R';
        case Key.S:  return 'S';
        case Key.T:  return 'T';
        case Key.U:  return 'U';
        case Key.V:  return 'V';
        case Key.W:  return 'W';
        case Key.X:  return 'X';
        case Key.Y:  return 'Y';
        case Key.Z:  return 'Z';
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