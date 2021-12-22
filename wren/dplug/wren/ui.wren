// API for global UI things. Wraps an UIContext.
class UI {

   // Get current width of the UI
   foreign static width

   // Get current height of the UI
   foreign static height

   // Get root Element of the hierarchy
   foreign static root
}


// API for widget. Wraps an UIElement.
foreign class Element {

   // Get current width of the UIElement
   foreign width

   // Get current height of the UIElement
   foreign height
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
