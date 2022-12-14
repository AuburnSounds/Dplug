import "ui" for UI, Element, Point, Size, Rectangle, RGBA
import "widgets" for UISlider, UIKnob, UIOnOffSwitch, UILevelDisplay, UIColorCorrection, UIImageKnob, UIWindowResizer

class Plugin {

    static createUI() {
        setupEverything()
    }

    static setupEverything() {

        // Note: do not create static __fields in create, since
        // in case of Wren VM reload (live edit), create won't be called.

        ($"_imageKnob").hasTrail = false  // no trail by default
        var litTrailDiffuse = RGBA.new(151, 119, 255, 100)
        var unlitTrailDiffuse = RGBA.new(81, 54, 108, 0)

        var driveKnob = ($"_driveKnob")
        driveKnob.knobDiffuse = RGBA.new(255, 255, 238, 0)
        driveKnob.knobMaterial = RGBA.new(0, 255, 128, 255)
        driveKnob.litTrailDiffuse = litTrailDiffuse
        driveKnob.unlitTrailDiffuse = unlitTrailDiffuse
        driveKnob.LEDDiffuseLit = RGBA.new(40, 40, 40, 100)
        driveKnob.LEDDiffuseUnlit = RGBA.new(40, 40, 40, 0)

        driveKnob.visibility = true
        driveKnob.zOrder = 1

        // Note: chaining syntax is also supported (but you can't mix and match property assignment and chaining)
        ($"_inputSlider").litTrailDiffuse(litTrailDiffuse)
                         .unlitTrailDiffuse(unlitTrailDiffuse)
        ($"_outputSlider").litTrailDiffuse(litTrailDiffuse)
                          .unlitTrailDiffuse(unlitTrailDiffuse)
        ($"_onOffSwitch").diffuseOn(litTrailDiffuse)
                         .diffuseOff(unlitTrailDiffuse)

        ($"_driveKnob").knobRadius(0.65) // does nothing yet, but an UIKnob is returned
                       .numLEDs(15)
                       .LEDRadiusMin(0.06)
                       .LEDRadiusMax(0.06)
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
        setupEverything()
    }
}