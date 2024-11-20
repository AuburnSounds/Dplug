module gui;

import dplug.gui;
import dplug.flatwidgets;
import dplug.client;

import main;

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
        // Add widgets here with `addChild`
        // ...

    }

    override void reflow()
    {
        super.reflow();

        // ...
        // Set position of every widget here
        // ...
    }

private:

    // ...
    // Child widgets go here
    // ...
}
