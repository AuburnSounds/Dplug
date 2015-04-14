module dplug.gui.windowlistener;

import ae.utils.graphics;

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

interface IWindowListener
{
    void onKeyDown(Key key);
    void onKeyUp(Key up);
    void onDraw(Image!RGBA* image);
}

