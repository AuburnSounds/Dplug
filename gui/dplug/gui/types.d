/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.types;

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
    enter,
    unsupported // special value, means "other"
};

enum MouseButton
{
    left,
    right,
    middle,
    x1,
    x2
}

struct MouseState
{
    bool leftButtonDown;
    bool rightButtonDown;
    bool middleButtonDown;
    bool x1ButtonDown;
    bool x2ButtonDown;
    bool ctrlPressed;
    bool shiftPressed;
    bool altPressed;
}