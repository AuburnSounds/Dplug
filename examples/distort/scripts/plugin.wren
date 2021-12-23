import "ui" for UI, Element, Point, Size

class Plugin {

    static createUI() { 
        System.print("createUI")
    }

    static reflow() { 
        System.print(UI.root.width)
        System.print(UI.root.height)
        System.print("reflow")
    }
}