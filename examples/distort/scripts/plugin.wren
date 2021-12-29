import "ui" for UI, Element, Point, Size, Rectangle

class Plugin {

    static createUI() { 

    }

    static reflow() { 
        var W = UI.width
        var H = UI.height
        var S = W / UI.defaultWidth
        ($"_imageKnob").position = Rectangle.new(517, 176, 46, 46).scaleByFactor(S)
    }
}