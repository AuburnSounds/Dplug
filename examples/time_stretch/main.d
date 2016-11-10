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
    writefln("    -n      Stretch factor (must be power of 2, default = 1)");
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

    if (!inputFile || !outputFile || !isPowerOfTwo(windowSize) || !isPowerOfTwo(stretchFactor) || overlap < 1)
    {
        usage();
        return 1;
    }

    Sound input = decodeWAV(inputFile);

    int lengthInFrames = input.lengthInFrames();
    int numChans = input.numChannels;
    int sampleRate = input.sampleRate;
    int fftSmallSize = windowSize;
    int fftSize = windowSize * stretchFactor;

    Complex!float randomPhase() nothrow @nogc
    {
        float phase = nogc_uniform_float(0, 2 * PI, defaultGlobalRNG());
        return Complex!float(cos(phase), sin(phase));
    }

    // output sound
    float[] stretched = new float[stretchFactor * lengthInFrames * numChans];

    // For reonstruction, since each segment is generated larger and periodic
    Window!float segmentWindow;
    segmentWindow.initialize(WindowType.HANN, fftSize);
    Complex!float[] fftData = new Complex!float[windowSize * stretchFactor];

    float[] segment = new float[fftSize];
    int counter = 0;

    int maxSimultaneousSegments = 1 + windowSize / ( windowSize / overlap);

    void process() nothrow @nogc
    {
        for (int ch = 0; ch < numChans; ++ch)
        {
            FFTAnalyzer ffta;
            ShortTermReconstruction strec;
            ffta.initialize(windowSize, fftSmallSize, windowSize / overlap, WindowType.HANN, false);
            strec.initialize(maxSimultaneousSegments, fftSize);

            for (int i = 0; i < lengthInFrames; ++i)
            {
                float sample = input.data[i * numChans + ch];
                if (ffta.feed(sample, fftData[0..fftSmallSize]))
                {
                    // Pad in frequency domain
                    // Here we have meaningful data in fftData[0..fftSmallSize], and garbage in fftData[fftSmallSize..$]

                    fftData[($-fftSmallSize/2)..$] = fftData[(fftSmallSize/2)..fftSmallSize];

                    fftData[fftSmallSize/2..($-fftSmallSize/2)] = Complex!float(0, 0);

                    // TODO change phase randomly on fftData[0..fftSmallSize/2]
/*
                    for(int k = 0; k < fftSmallSize; ++k)
                    {
                        fftData[$ - 1 - k] = -fftData[k];//.conj;
                    }
*/
                    inverseFFT!float(fftData);

                    for (int k = 0; k < fftSize; ++k)
                    {
                        segment[k] = fftData[k].re * segmentWindow[k] * 5;
                        assert( abs(fftData[k].im) < 0.01f );
                    }
               //     if ((counter % 4) == 0)
                    {
                        strec.startSegment(segment);
                    }
                    counter++;
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
