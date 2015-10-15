import std.math;

import waved,
       dplug.dsp;

import std.stdio;

// stretch a sound 2x

void main(string[] args)
{
    if (args.length != 3)
    {
        writefln("usage: time_stretch input.wav output.wav");
        return;
    }

    Sound input = decodeWAV(args[1]);

    int N = input.lengthInFrames();
    int numChans = input.numChannels;
    int sampleRate = input.sampleRate;


    float[] stretched = new float[2 * N * numChans];

    int windowSize = 1024;

    Complex!float[] fftData = new Complex!float[windowSize * 2];
    float[] segment = new float[windowSize * 2];

    void process() nothrow @nogc
    {
        for (int ch = 0; ch < numChans; ++ch)
        {
            FFTAnalyzer ffta;
            ShortTermReconstruction strec;
            ffta.initialize(windowSize, windowSize, windowSize / 4, WindowType.HANN, false);
            strec.initialize(8, windowSize * 2);

            for (int i = 0; i < N; ++i)
            {
                float sample = input.data[i * numChans + ch];
                if (ffta.feed(sample, fftData[0..windowSize]))
                {                
                    // zero-padding the middle of spectrum
                    fftData[windowSize/2..windowSize*2] = Complex!float(0);

                    // inverse FFT
                    FFT!float(fftData[0..windowSize*2], FFTDirection.REVERSE);

                    for (int k = 0; k < windowSize*2; ++k)
                        segment[k] = fftData[k].re * 0.5f;

                    strec.startSegment(segment[0..windowSize*2]);
                }
                stretched[(i * numChans + ch)*2] = strec.next();
                stretched[(i * numChans + ch)*2+1] = strec.next();
            }
        }     
    }
    process();

    Sound(sampleRate, numChans, stretched).encodeWAV(args[2]);
}
