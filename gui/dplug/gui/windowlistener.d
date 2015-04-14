module dplug.gui.windowlistener;

enum Key
{
    space,
    upArrow,
    downArrow,
    leftArrow,
    rightArrow,
    digit0,
    digit1,
    digit2,
    digit3,
    digit4,
    digit5,
    digit6,
    digit7,
    digit8,
    digit9,
    enter
};

struct WindowFrameBuffer
{
    ubyte* pixels;  // RGBA data, height x scanlines with contiguous pixels
    int width;      // width of image
    int height;     // height of image
    int byteStride; // offset between scanlines, in bytes
}

interface IWindowListener
{
    void onKeyDown(Key key);
    void onKeyUp(Key up);

    // an image you have to draw to, or return that nothing has changed
    void onDraw(WindowFrameBuffer wfb, out bool needRedraw); // TODO: return just a region!
}

