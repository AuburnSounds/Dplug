import core.stdc.stdio;
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
    writefln("    -ov     Sets overlap (default = 2)");
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

    if (!inputFile || !outputFile || !isPowerOfTwo(windowSize) || stretchFactor < 1 || overlap < 1)
    {
        usage();
        return 1;
    }

    Sound input = decodeWAV(inputFile);

    int lengthInFrames = input.lengthInFrames();
    int numChans = input.numChannels;
    int sampleRate = input.sampleRate;
    int fftSize = windowSize;

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
    Complex!float[] fftData = new Complex!float[fftSize];

    Complex!float[] fftDataSegment = new Complex!float[fftSize];

    float[] segment = new float[fftSize];

    

    void process() nothrow @nogc
    {
        for (int ch = 0; ch < numChans; ++ch)
        {
            FFTAnalyzer ffta;
            ShortTermReconstruction strec;
            ffta.initialize(windowSize, fftSize, windowSize / overlap, WindowType.RECT, false);
            int maxSimultaneousSegments = 1 + (1 + overlap) * stretchFactor;
            strec.initialize(maxSimultaneousSegments, fftSize);
            int counter = 0;
            for (int i = 0; i < lengthInFrames; ++i)
            {
                float sample = input.data[i * numChans + ch];
                if (ffta.feed(sample, fftData[0..fftSize]))
                {
                    // prepate stretchFactor time segments with random phase
                    for (int stretch = 0; stretch < stretchFactor; ++stretch)
                    {
                        if (randomizePhase)
                        {
                            fftDataSegment[0] = fftData[0];
                            foreach(bin; 1..fftSize/2)
                            {
                                Complex!float mul = randomPhase();
               //                 if (bin > 512)
               //                     mul = Complex!float(1, 0);
                                fftDataSegment[bin] = fftData[bin] * mul;
                            }
                            fftDataSegment[fftSize/2] = fftData[fftSize/2];

                            // keep it real
                            foreach(bin; 1..fftSize/2)
                                fftDataSegment[$-bin] = fftDataSegment[bin].conj();
                        }
                        else
                        {
                            foreach(bin; 0..fftSize)
                                fftDataSegment[bin] = fftData[bin];
                        }

                        inverseFFT!float(fftDataSegment);

                        // apply time window to segment

                        for (int k = 0; k < fftSize; ++k)
                        {
                            segment[k] = fftDataSegment[k].re * segmentWindow[k] * 2;
                            assert( abs(fftDataSegment[k].im) < 0.01f );
                        }

                        // schedule several of these segments spaced by a window size
                        int delay = (stretch * windowSize) / 2;
                        //if (delay == 0)
                            strec.startSegment(segment, delay);
                        counter++;
                    }
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
