// This is the Dplug scripting API, for use in your plugin.wren scripts.
// Note that you cannot create widgets from Wren, and the scoping is global (only your main widget 
// is scriptable).

// API for global UI things. Wraps an UIContext.
class UI {

   // Get current width of the UI
   foreign static width

   // Get current height of the UI
   foreign static height

   // Get default width of the UI
   foreign static defaultWidth

   // Get default height of the UI
   foreign static defaultHeight

   // Get root Element of the hierarchy
   static root {
       return UIElement.new("__ROOT__")
   }

   static getElementById(id) {
       return $(id)
   }
}

// API for widget. Wraps an UIElement.
// Note that this is only for internal use! Scripts should manipulate UIElement and its derivative instead.
foreign class Element {

   // Construct an Element from an ID.
   // if "__ROOT__" is passed, the root Element is returned  
   construct new(id) {
       findIdAndBecomeThat_(id)
   }

   // Get current width of the UIElement
   foreign width

   // Get current height of the UIElement
   foreign height

   position=(rect) {
       var orig = rect.origin
       var sz = rect.size
       setPosition_(orig.x, orig.y, sz.width, sz.height)  // PERF: use _fields instead of accessors
   }

   visibility=(v) {
       setVisibility_(v)
   }

   zOrder=(z) {
       setZOrder_(z)
   }

   // Internal use
   foreign findIdAndBecomeThat_(id)
   foreign setPosition_(x, y, w, h)
   foreign setVisibility_(v)
   foreign setZOrder_(z)

   foreign setProp_(nclass, nth, x)
   foreign setPropRGBA_(nclass, nth, r, g, b, a)
   foreign getProp_(nclass, nth)
   foreign getPropRGBA_(nclass, nth, ch)
}

// Non-foreign base classes for UIElement derivatives.
class UIElement {

   construct new(id) {
       _e = Element.new(id)
   }

   // Get current width of the UIElement
   width { _e.width }

   // Get current height of the UIElement
   height { _e.height }

   position=(rect) {
       _e.position = rect
   }

   position(rect) {
       _e.position = rect
       return this
   }

   visibility=(v) {
       _e.visibility = v
   }

   visibility(v) {
       _e.visibility = v
       return this
   }

   zOrder=(z) {
       _e.zOrder = z
   }

   zOrder(z) {
       _e.zOrder = z
       return this
   }

   e { _e }
}

class Point {
    construct new(x, y) {
        _x = x
        _y = y
    }

    x { _x }
    y { _y }
    x (newX) { _x = newX }
    y (newY) { _y = newY }
}

class Size {
    construct new(width, height) {
        _width = width
        _height = height
    }

    width { _width }
    height { _height }
    width (newW) { _width = newW }
    height (newH) { _height = newH }
}

class Rectangle {

    construct new(x, y, width, height) {
        _orig = Point.new(x, y)
        _size = Size.new(width, height)
    }

    construct new(orig, size) {
        _orig = orig
        _size = size
    }

    size { _size }
    origin { _orig }

    scaleByFactor(scale) { 
        var minx = (_orig.x * scale).round
        var miny = (_orig.y * scale).round
        var maxx = ( (_orig.x + _size.width) * scale).round
        var maxy = ( (_orig.y + _size.height) * scale).round
        return Rectangle.new(minx, miny, maxx - minx, maxy - miny)
    }
}

class RGBA {

    construct new(r, g, b, a) {
        _r = r
        _g = g
        _b = b
        _a = a
    }

    // Make it more white: 0 => original    1 => pure white
    whiten(f) {
        return RGBA.new(_r + (255 - _r)*f, _g + (255 - _g)*f, _b + (255 - _b)*f, a)
    }

    // Make it more black: 0 => original    1 => pure black
    blacken(f) {
        return RGBA.new(_r * (1 - f), _g * (1 - f), _b * (1 - f), a)
    }

    withAlpha(a) {
        return RGBA.new(_r, _g, _b, a)
    }

    static grey(v) {
        return RGBA.new(v, v, v, 255)
    }

    static grey(v, alpha) {
        return RGBA.new(v, v, v, alpha)
    }

    r { _r }
    g { _g }
    b { _b }
    a { _a }
    r=(x) { _r = x }
    g=(x) { _g = x }
    b=(x) { _b = x }
    a=(x) { _a = x }
}
