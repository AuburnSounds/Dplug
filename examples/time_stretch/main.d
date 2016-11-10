import std.math;

import std.stdio;
import std.complex;
import std.conv;

import waved;

import dplug.core;
import dplug.dsp;

// stretch a sound N times

void usage()
{
    writeln();
    writefln("usage: time_stretch [-n 10] [-rp] [-ov 4] -o output.wav -i input.wav");
    writeln();
    writefln("    Stretches a sound N times.");
    writeln();
    writefln("    -n      Dilation factor (default = 1)");
    writefln("    -o      Set output file (WAV only)");
    writefln("    -rp     Randomize phases");
    writefln("    -w      Changes window size (must be power of 2, default = 1024)");
    writefln("    -ov      Sets overlap (default = 2)");
    writeln();
}

int main(string[] args)
{
    // Parse arguments
    bool randomizePhase = false;
    string inputFile = null;
    string outputFile = null;
    int stretchFactor = 1;
    int windowSize = 1024;
    int overlap = 2;

    for(int i = 1; i < args.length; ++i)
    {
        string arg = args[i];
        if (arg == "-n")
        {
            stretchFactor = to!int(args[++i]);
        }
        else if (arg == "-o")
        {
            outputFile = args[++i];
        }
        else if (arg == "-i")
        {
            inputFile = args[++i];
        }
        else if (arg == "-w")
        {
            windowSize = to!int(args[++i]);            
        }
        else if (arg == "-ov")
        {
            overlap = to!int(args[++i]);            
        }
        else if (arg == "-rp")
        {
            randomizePhase = true;
        }
    }

    if (!inputFile || !outputFile || !isPowerOfTwo(windowSize) || overlap < 1)
    {
        usage();
        return 1;
    }

    Sound input = decodeWAV(inputFile);

    int lengthInFrames = input.lengthInFrames();
    int numChans = input.numChannels;
    int sampleRate = input.sampleRate;

    Complex!float randomPhase() nothrow @nogc
    {
        float phase = nogc_uniform_float(0, 2 * PI, defaultGlobalRNG());
        return Complex!float(cos(phase), sin(phase));
    }

    // output sound
    float[] stretched = new float[stretchFactor * lengthInFrames * numChans];


    Complex!float[] fftData = new Complex!float[windowSize * stretchFactor];
    int fftSize = windowSize * stretchFactor;
    float[] segment = new float[fftSize];
    

    int maxSimultaneousSegments = 1 + windowSize / ( windowSize / overlap);

    void process() nothrow @nogc
    {
        for (int ch = 0; ch < numChans; ++ch)
        {
            FFTAnalyzer ffta;
            ShortTermReconstruction strec;
            ffta.initialize(windowSize, fftSize, windowSize / overlap, WindowType.HANN, false);
            strec.initialize(maxSimultaneousSegments, fftSize);

            for (int i = 0; i < lengthInFrames; ++i)
            {
                float sample = input.data[i * numChans + ch];
                if (ffta.feed(sample, fftData))
                {  
                    inverseFFT!float(fftData);

                    for (int k = 0; k < fftSize; ++k)
                    {
                        segment[k] = fftData[k].re;
                        assert( abs(fftData[k].im) < 0.01f );
                    }
                    strec.startSegment(segment);
                }
                for (int k = 0; k < stretchFactor; ++k)
                {
                    stretched[ ( (i * stretchFactor + k) * numChans + ch) ] = strec.next();
                }
            }
        }     
    }
    process();

    Sound(sampleRate, numChans, stretched).encodeWAV(outputFile);

    return 0;
}
