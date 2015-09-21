import core.memory;

import std.stdio;
import std.typecons;
import std.string;
import std.algorithm;
import std.conv;

import derelict.cocoa;
import derelict.util.sharedlib;
import dplug.vst;

void usage()
{
    writeln("Auburn Sounds ldvst VST checker\n");
    writeln("usage: ldvst [-w | -wait] [-t times] {plugin.vst|plugin.so|plugin.dll}\n");

}

void main(string[]args)
{
    int times = 1;
    string vstpath = null;
    bool gui = true;
    bool wait = false;

    for(int i = 1; i < args.length; ++i)
    {
        string arg = args[i];
        if (arg == "-no-gui")
            gui = true;
        else if (arg == "-w" || arg == "-wait")
            wait = true;
        else if (arg == "-t")
        {
            ++i;
            times = to!int(args[i]);
        }
        else
        {
            if (!vstpath)
                vstpath = arg;
            else
            {
                usage();
                throw new Exception(format("Excess argument '%s'", arg));
            }
        }
    }
	if (vstpath is null)
    {
        usage();
        return;
    }

    if (wait)
    {
        writeln("Press ENTER to start the VST hosting...");
        readln;
    }

	// just a dyn lib, try to load it
    for (int t = 0; t < times; ++t)
    {
	   auto server = scoped!VSTServer(vstpath, gui);
    }

    if (wait)
    {
        writeln("Press ENTER to end the program...");
        readln;
    }
}

alias VSTPluginMain_t = extern(C) AEffect* function(HostCallbackFunction fun);

class VSTServer
{
	SharedLib lib;
	this(string dylibPath, bool gui)
	{
		writefln("Load library %s", dylibPath);
		lib.load([ dylibPath ]);
		writefln("  Look-up symbol VSTPluginMain");
		VSTPluginMain_t VSTPluginMain = cast(VSTPluginMain_t)( lib.loadSymbol("VSTPluginMain") );
		writefln("  Call VSTPluginMain");
        AEffect* aeffect = VSTPluginMain(&hostCallback);

        if (aeffect.magic != kEffectMagic)
            throw new Exception("  Wrong VST magic number");

        if (aeffect.dispatcher == null)
            throw new Exception("  dispatcher is null");
        if (aeffect.setParameter == null)
            throw new Exception("  setParameter is null");
        if (aeffect.getParameter == null)
            throw new Exception("  getParameter is null");

        writefln("  numPrograms = %s", aeffect.numPrograms);
        writefln("  numParams = %s", aeffect.numParams);
        writefln("  numInputs = %s", aeffect.numInputs);
        writefln("  numOutputs = %s", aeffect.numOutputs);
        writefln("  flags = %s", aeffect.flags);
        writefln("  initialDelay = %s", aeffect.initialDelay);
        writefln("  object = %s", aeffect.object);
        writefln("  user = %s", aeffect.user);
        writefln("  uniqueID = %s", aeffect.uniqueID);
        writefln("  version = %s", aeffect.version_);


        auto dispatcher = aeffect.dispatcher;

        writefln("  effOpen");
        dispatcher(aeffect, effOpen, 0, 0, null, 0.0f);

        writefln("  effGetPlugCategory");
        dispatcher(aeffect, effGetPlugCategory, 0, 0, null, 0.0f);

        char[65] buf;
        dispatcher(aeffect, effGetVendorString, 0, 0, buf.ptr, 0.0f);
        writefln("  effGetVendorString returned '%s'", fromStringz(buf.ptr));

        dispatcher(aeffect, effGetEffectName, 0, 0, buf.ptr, 0.0f);
        writefln("  effGetEffectName returned '%s'", fromStringz(buf.ptr));

        dispatcher(aeffect, effGetProductString, 0, 0, buf.ptr, 0.0f);
        writefln("  effGetProductString returned '%s'", fromStringz(buf.ptr));


        // Create a GUI
        version(OSX)
        {
            if (gui)
            {
                writefln("  open GUI");
                DerelictCocoa.load();
                auto NSApp = NSApplication.sharedApplication;
                NSWindow window = NSWindow.alloc();
                window.initWithContentRect(NSMakeRect(0, 0, 1024, 768), NSBorderlessWindowMask, NSBackingStoreBuffered, NO);
                window.makeKeyAndOrderFront();
                NSView parentView = window.contentView();

                dispatcher(aeffect, effEditOpen, 0, 0, cast(void*)parentView._id, 0.0f);

                writefln("  effEditGetRect");
                ERect rect;
                dispatcher(aeffect, effEditGetRect, 0, 0, &rect, 0.0f);

                writefln("  close GUI");
                dispatcher(aeffect, effEditClose, 0, 0, null, 0.0f);
            }
        }

        writefln("  effClose");
        dispatcher(aeffect, effClose, 0, 0, null, 0.0f);

		writefln("Everything OK, unloading\n");
        lib.unload();
        lib.destroy();
        GC.collect();
	}
}

extern(C) nothrow VstIntPtr hostCallback(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt)
{
    try
    {
        import std.stdio;
        writeln("Received opcode: ");
        switch(opcode)
        {
            case DEPRECATED_audioMasterWantMidi: writeln("DEPRECATED_audioMasterWantMidi"); return 0;
            case audioMasterGetTime: writeln("audioMasterGetTime"); return 0;
            case audioMasterProcessEvents: writeln("audioMasterProcessEvents"); return 0;
            case DEPRECATED_audioMasterSetTime: writeln("DEPRECATED_audioMasterSetTime"); return 0;
            case DEPRECATED_audioMasterTempoAt: writeln("DEPRECATED_audioMasterTempoAt"); return 0;
            case DEPRECATED_audioMasterGetNumAutomatableParameters: writeln("DEPRECATED_audioMasterGetNumAutomatableParameters"); return 0;
            case DEPRECATED_audioMasterGetParameterQuantization: writeln("DEPRECATED_audioMasterGetParameterQuantization"); return 0;
            case audioMasterIOChanged: writeln("audioMasterIOChanged"); return 0;
            case DEPRECATED_audioMasterNeedIdle: writeln("DEPRECATED_audioMasterNeedIdle"); return 0;
            case audioMasterSizeWindow: writeln("audioMasterSizeWindow"); return 0;
            case audioMasterGetSampleRate: writeln("audioMasterGetSampleRate"); return 0;
            case audioMasterGetBlockSize: writeln("audioMasterGetBlockSize"); return 0;
            case audioMasterGetInputLatency: writeln("audioMasterGetInputLatency"); return 0;
            case audioMasterGetOutputLatency: writeln("audioMasterGetOutputLatency"); return 0;
            case DEPRECATED_audioMasterGetPreviousPlug: writeln("DEPRECATED_audioMasterGetPreviousPlug"); return 0;
            case DEPRECATED_audioMasterGetNextPlug: writeln("DEPRECATED_audioMasterGetNextPlug"); return 0;
            case DEPRECATED_audioMasterWillReplaceOrAccumulate: writeln("DEPRECATED_audioMasterWillReplaceOrAccumulate"); return 0;
            case audioMasterGetCurrentProcessLevel: writeln("audioMasterGetCurrentProcessLevel"); return 0;
            case audioMasterGetAutomationState: writeln("audioMasterGetAutomationState"); return 0;
            case audioMasterOfflineStart: writeln("audioMasterOfflineStart"); return 0;
            case audioMasterOfflineRead: writeln("audioMasterOfflineRead"); return 0;
            case audioMasterOfflineWrite: writeln("audioMasterOfflineWrite"); return 0;
            case audioMasterOfflineGetCurrentPass: writeln("audioMasterOfflineGetCurrentPass"); return 0;
            case audioMasterOfflineGetCurrentMetaPass: writeln("audioMasterOfflineGetCurrentMetaPass"); return 0;
            case DEPRECATED_audioMasterSetOutputSampleRate: writeln("DEPRECATED_audioMasterSetOutputSampleRate"); return 0;
            case DEPRECATED_audioMasterGetOutputSpeakerArrangement: writeln("DEPRECATED_audioMasterGetOutputSpeakerArrangement"); return 0;
            case audioMasterGetVendorString: writeln("audioMasterGetVendorString"); return 0;
            case audioMasterGetProductString: writeln("audioMasterGetProductString"); return 0;
            case audioMasterGetVendorVersion: writeln("audioMasterGetVendorVersion"); return 0;
            case audioMasterVendorSpecific: writeln("audioMasterVendorSpecific"); return 0;
            case DEPRECATED_audioMasterSetIcon: writeln("DEPRECATED_audioMasterSetIcon"); return 0;
            case audioMasterCanDo: writeln("audioMasterCanDo"); return 0;
            case audioMasterGetLanguage: writeln("audioMasterGetLanguage"); return 0;
            case DEPRECATED_audioMasterOpenWindow: writeln("DEPRECATED_audioMasterOpenWindow"); return 0;
            case DEPRECATED_audioMasterCloseWindow: writeln("DEPRECATED_audioMasterCloseWindow"); return 0;
            case audioMasterGetDirectory: writeln("audioMasterGetDirectory"); return 0;
            case audioMasterUpdateDisplay: writeln("audioMasterUpdateDisplay"); return 0;
            case audioMasterBeginEdit: writeln("audioMasterBeginEdit"); return 0;
            case audioMasterEndEdit: writeln("audioMasterEndEdit"); return 0;
            case audioMasterOpenFileSelector: writeln("audioMasterOpenFileSelector"); return 0;
            case audioMasterCloseFileSelector: writeln("audioMasterCloseFileSelector"); return 0;
            case DEPRECATED_audioMasterEditFile: writeln("DEPRECATED_audioMasterEditFile"); return 0;
            case DEPRECATED_audioMasterGetChunkFile: writeln("DEPRECATED_audioMasterGetChunkFile"); return 0;
            case DEPRECATED_audioMasterGetInputSpeakerArrangement: writeln("DEPRECATED_audioMasterGetInputSpeakerArrangement"); return 0;
            default: writeln(" unknown opcode"); return 0;
        }
    }
    catch(Exception e)
    {
        return 0;
    }
}
