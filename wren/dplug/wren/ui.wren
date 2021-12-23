// This is the scirpting API for scriptiing styling behaviour of the plugin, in case of UI creation or UI resize.
// Cannot create widgets from Wren.

// API for global UI things. Wraps an UIContext.
class UI {

   // Get current width of the UI
   foreign static width

   // Get current height of the UI
   foreign static height

   // Get root Element of the hierarchy
   static root {
       return Element.new("__ROOT__")
   }
}


// API for widget. Wraps an UIElement.
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

   // Internal use
   foreign findIdAndBecomeThat_(id)
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
}
