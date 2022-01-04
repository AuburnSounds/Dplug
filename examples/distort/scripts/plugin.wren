import "ui" for UI, Element, Point, Size, Rectangle
import "widgets" for UISlider, UIKnob, UIOnOffSwitch, UILevelDisplay, UIColorCorrection, UIImageKnob, UIWindowResizer

class Plugin {

    static createUI() { 

    }

    static reflow() { 
        var W = UI.width
        var H = UI.height
        var S = W / UI.defaultWidth
        ($"_imageKnob").position = Rectangle.new(517, 176, 46, 46).scaleByFactor(S)
        ($"_inputSlider").position = Rectangle.new(190, 132, 30, 130).scaleByFactor(S)
        ($"_outputSlider").position = Rectangle.new(410, 132, 30, 130).scaleByFactor(S)
        ($"_onOffSwitch").position = Rectangle.new(90, 177, 30, 40).scaleByFactor(S)
        ($"_driveKnob").position = Rectangle.new(250, 140, 120, 120).scaleByFactor(S)
        ($"_inputLevel").position = Rectangle.new(150, 132, 30, 130).scaleByFactor(S)
        ($"_outputLevel").position = Rectangle.new(450, 132, 30, 130).scaleByFactor(S)
        ($"_colorCorrection").position = Rectangle.new(0, 0, W, H)
        ($"_resizer").position = Rectangle.new(W-30, H-30, 30, 30)
    }
}