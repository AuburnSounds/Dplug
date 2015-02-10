module dplug.plugin.graphics;

import dplug.plugin.client;

/// Plugin GUI
class Graphics
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
