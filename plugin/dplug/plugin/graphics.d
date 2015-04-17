module dplug.plugin.graphics;

import dplug.plugin.client;

/// Plugin GUI
class Graphics
{
    this(Client client)
    {
        _client = client;
    }

    abstract void openUI(void* parentInfo);
    abstract void closeUI();

protected:
    Client _client;
}

/// Default Graphics object, does nothing
class NullGraphics : Graphics
{
    this(Client client)
    {
        super(client);
    }

    override void openUI(void* parentInfo)
    {
    }

    override void closeUI()
    {
    }

protected:
    Client _client;
}
