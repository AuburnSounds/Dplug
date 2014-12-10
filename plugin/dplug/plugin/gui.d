module dplug.plugin.gui;

import dplug.plugin.client;

// interface to send messages from the plugin to the GUI.
class PluginGUI
{
    this(Client client)
    {
        _client = client;
    }

    abstract void open(void* parentInfo);
    abstract void close();

protected:
    Client _client;
}

class NullGUI : PluginGUI
{
public:

    this(Client client)
    {
        super(client);
    }

    override void open(void* parentInfo)
    {
    }

    override void close()
    {
    }
}
