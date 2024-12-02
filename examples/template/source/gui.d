module gui;

import dplug.gui;
import dplug.flatwidgets;
import dplug.client;

import main;

/**
    This is a barebones and empty UI with only a static image as
    background. 

    To go further:
        - Examples:             Distort and ClipIt.
        - FAQ:                  https://dplug.org/tutorials
        - Inline Documentation: https://dplug.dpldocs.info/dplug.html
*/
class TemplateGUI : FlatBackgroundGUI!("blank.png")
{
public:
nothrow:
@nogc:

    MyClient _client;

    this(MyClient client)
    {
        _client = client;
        super(585, 800);
        setUpdateMargin(0);

        // ...
        // Add widgets here with `addChild`.
        //
        // Base widgets are typically in packages dplug:flat-widgets
        // and `dplug:flat_widgets`.
        //
        // See the examples/distort and example/clipit plug-ins for
        // how to add interface elements to your plug-in.
        // ...
    }

    override void reflow()
    {
        super.reflow();

        // ...
        // Set position of every widget here.
        // This function is called on UI opening and resize.
        // eg: _myKnob.position = rectangle(240, 170, 60, 60);
        // ...
    }

private:

    // ...
    // Child widgets go here
    // ...
}
