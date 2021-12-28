import "ui" for UI, Element, Point, Size, Rectangle

class Plugin {

    static createUI() { 
        System.print("createUI")
    }

    static reflow() { 
        var W = UI.width
        var H = UI.height
        var S = W / UI.defaultWidth
        UI.getElementById("_imageKnob").position = Rectangle.new(517, 176, 46, 46).scaleByFactor(S)
    }
}