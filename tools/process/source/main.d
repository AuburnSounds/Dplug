import std.stdio;
import std.algorithm;
import std.range;
import std.conv;

import waved;

import dplug.host;


void usage()
{
    writeln("Auburn Sounds ldvst VST benchmark\n");
    writeln("usage: process -i input.wav [-o output.wav] [-h] [-b <bufferSize>] plugin.dll}\n");

}

void main(string[]args)
{
    try
    {
        string pluginPath = null;
        string outPath = null;
        string inPath = null;
        int bufferSize = 256;
        bool help = false;

        for(int i = 1; i < args.length; ++i)
        {
            string arg = args[i];
            if (arg == "-i")
            {
                if (inPath)
                    throw new Exception("Multiple input paths provided");
                ++i;
                inPath = arg;
            }
            else if (arg == "-o")
            {
                if (outPath)
                    throw new Exception("Multiple output paths provided");
                ++i;
                outPath = args[i];
            }
            if (arg == "-b")
            {
                ++i;
                bufferSize = to!int(args[i]);
            }
            else if (arg == "-h")
            {
                help = true;
            }
            else
            {
                if (pluginPath)
                    throw new Exception("Multiple plugin paths provided");
                pluginPath = args[i];
            }
        }
        if (help)
        {
            usage();
            return;
        }
	    if (pluginPath is null)
            throw new Exception("No plugin path provided");
        if (inPath is null)
            throw new Exception("No input path provided");
        if (outPath is null)
            throw new Exception("No output path provided");

        Sound sound = decodeSound(inPath);
        if (sound.numChannels != 2)
            throw new Exception("Only support stereo inputs");
        if (bufferSize < 1)
            throw new Exception("bufferSize is < 1");

        int N = sound.lengthInFrames();

        float[] leftChannelInput;
        float[] rightChannelInput;
        float[] leftChannelOutput;
        float[] rightChannelOutput;
        leftChannelInput.length = N;
        rightChannelInput.length = N;
        leftChannelOutput.length = N;
        rightChannelOutput.length = N;
        

        for (int i = 0; i < N; ++i)
        {
            leftChannelInput[i] = sound.data[i * 2];
            rightChannelInput[i] = sound.data[i * 2 + 1];
        }
    
        IPluginHost host = createPluginHost(pluginPath);
        host.setSampleRate(sound.sampleRate);        
        host.setMaxBufferSize(bufferSize);

        int offset = 0;
        for (int buf = 0; buf < N / bufferSize; ++buf)
        {
            float*[2] inChannels, outChannels;
            inChannels[0] = leftChannelInput.ptr + offset;
            inChannels[1] = rightChannelInput.ptr + offset;        
            outChannels[0] = leftChannelOutput.ptr + offset;
            outChannels[1] = rightChannelOutput.ptr + offset;
            host.processAudioFloat(inChannels.ptr, outChannels.ptr, bufferSize);
            offset += bufferSize;
        }
    
        static auto interleave(Range1, Range2)(Range1 a, Range2 b)
        {
            return a.zip(b).map!(a => only(a[0], a[1])).joiner();
        }

        // write output if necessary
        if (outPath)
        {
            sound.data = interleave(leftChannelOutput, rightChannelOutput).array;
            encodeWAV(sound, outPath);
        }

        host.close();
    }
    catch(Exception e)
    {
        import std.stdio;
        writefln("error: %s", e.msg);
    }
}
