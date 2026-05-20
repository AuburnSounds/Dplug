/**
A zero-latency hybrid audio convolver.

Copyright: Jules Torres 2026.
Copyright: Guillaume Piolat 2026.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.fft.convolver;

import std.complex;

import dplug.core;
import dplug.dsp;
import dplug.fft;

//debug = convolver;
debug(convolver) import core.stdc.stdio;

/**
    Hybrid zero-latency convolver,
    uses both the naive convolution and FFT convolution.

    FUTURE: options to normalize, trim, and make the impulse 
            minimum phase.
            At least Dplug should provide ways to do that.

    FUTURE: targetLatencySamples should be supported.
            Has implication on the max number of segments in recon.

    Benchmarks 
        (with a 2.5 sec impulse response at 44.1 kHz, 
         SnapDragon X Plus, May 2026)

        * 32-bit float
            - Precision = ~ -108 dB RMS
            - Speed     = ~135x stereo-convolutions real-time

        * 64-bit double 
            - Precision = ~ -150 dB RMS
            - Speed     = ~92x stereo-convolutions real-time

    PERF: find a way to have 64-point FFT in Rfft, so that min block size can be 32
          would win a few %

    PERF: find a way to reuse the FFT convolvers on impulse change
*/
struct Convolver(T)
{
public:
nothrow @nogc:

    /**
        Initialize the convolver.
    */
    void initialize(int maxFrames)
    {
        _maxFrames = maxFrames;
    }


    /**
        Load the impulse reponse.
        Changing the impulse response doesn't necessitate to call
        `.initialize`, however it will click.

        MUST be called before processing samples.
        MUST be called whenever `.initialize` was called.

        Params:
              impulse = Impulse response to convolve with.
              targetLatencySamples = Latency we are willing to have 
                        for this convolution. Trade speed vs latency.
    */
    void setImpulse(const(T)[] impulse, int targetLatencySamples = 0)
    {
        assert(targetLatencySamples == 0); // Not supported

        int N = cast(int) impulse.length;

        int delaylineNeeded;
        int maxBlockSize;
        int directConvArea;
        makePlan(N, delaylineNeeded, maxBlockSize, directConvArea);

        debug(convolver) printf("maxBlockSize = %d\n", maxBlockSize);
        debug(convolver) printf("delayline = %d\n", delaylineNeeded);
        debug(convolver) printf("directConvArea = %d\n", directConvArea);
        _delayline.initialize(delaylineNeeded);


        _naive.setImpulse(impulse[0..directConvArea]);


        // Remove existing block convolver if any, since 
        // maxFrames could have changed. 
        // In this case reuse if too difficult to implement
        // right now.
        for (size_t i = 0; i < _blockConv.length; ++i)
        {
            destroyFree(_blockConv[i]);
        }

        // Create new block convolvers.
        _blockConv.reallocBuffer(_plan.length);
        _tempBuf.reallocBuffer(maxBlockSize * 2);
        _tempBuf2.reallocBuffer(maxBlockSize + 1);
        for (size_t i = 0; i < _plan.length; ++i)
        {            
            int blockSize    = _plan[i].sizeOfBlock;
            int inputOffset  = _plan[i].inputOffset;
            int start        = _plan[i].irOffset;
            int multiplicity = _plan[i].multiplicity;
            int initCounter  = _plan[i].initCounter;

            assert(inputOffset == start - blockSize);
            int stop        = start + blockSize * multiplicity;
            if (stop > N) stop = N;
            _blockConv[i] = mallocNew!(FFTConvolver)();

            _blockConv[i].initialize(_maxFrames, blockSize, inputOffset, multiplicity, initCounter);
            _blockConv[i].setImpulse(impulse[start..stop], _tempBuf);
        }
    }

    /**
        Process samples and return the convolved output.

        `setImpulse` MUST have been called prior.
    */
    void nextBuffer(const(T)* input, T* output, int frames)
    {
        // All sub-convolvers use the same delay-line.
        _delayline.feedBuffer(input[0..frames]);

        // Sum the different convolvers
        _naive.nextBuffer(input, output, frames, &_delayline);
        for (size_t i = 0; i < _plan.length; ++i)
        {
            _blockConv[i].nextBufferAccum(input, output, frames, 
                &_delayline, _tempBuf, _tempBuf2);
        }
    }

    ~this()
    {
        foreach(bc; _blockConv)
        {
            destroyFree(bc);
        }
        _blockConv.reallocBuffer(0);
        _tempBuf.reallocBuffer(0);
        _tempBuf2.reallocBuffer(0);
    }

private:

    // Good values are basically 32 or 64.
    // Note: 32 is faster, but asserts in Rfft.
    enum int MIN_BLOCK_SIZE = 64;

    // After this size we consider that a single FFT of
    // this size is too CPU spikey.    
    enum int MAX_BLOCK_SIZE = 65536;

    int _maxFrames;

    // The shared delay-line all sub-convolver peek into.
    Delayline!T _delayline;

    // Subsequent blocks need a FFT convolution.
    FFTConvolver*[] _blockConv;

    // Plan of various convolutions to do.
    Vec!Step _plan;

    // First part of the IR is convolved without blocks.
    NaiveConvolver _naive;

    // A temporary buffer, it is used:
    // - to precompute IR spectral coeffs
    // - as a temporary buffer for FFT block conv
    // As it turns out the FFT convolvers don't need their own 
    // temp buffers.
    T[] _tempBuf;

    Complex!T[] _tempBuf2;

    /// Describe the recipe for a FFTConvolver step.
    static struct Step
    {
    nothrow @nogc:
        /// Size of block (half the FFT size).
        int sizeOfBlock; 

        /// Starting point in the IR.
        int irOffset;

        /// How many blocks in this FFTConvolver (FDL size).
        int multiplicity;

        /// Phase of the segmenter. See Appendix A. below for how this
        /// reduces CPU spikes.
        int initCounter;

        // How much samples in the past to sample?
        int inputOffset() pure const
        {
            int r = irOffset - sizeOfBlock;
            debug(convolver) printf("irOffset  = %d  sizeOfBlock = %d x %d  counter=%d\n", irOffset, sizeOfBlock, multiplicity, initCounter);
            return r;
        }
    }


    /**
        Compute what to do beyond MIN_BLOCK_SIZE samples of IR.
        Fill _plan with what to do with blocks.

        Params:
            N                = Length of impulse, in samples.
            sizeOfDelayline  = Delay buffer needed to operate.
            maxUsedBlockSize = Largest size of block used, can be 0 if
                               no FFT used.
            directConvArea   = Starting area that is convoluted naively.

        Also depends on maxFrames.

        Optimization that didn't work out: it is very tempting to rationalize
        the plan and start counting from the largest possible block size, down to
        the smallest, and put the rest as , in order to minimize the amount of large
        FFT. However this ends being 25% slower because of the larger amount of small
        FFTs and direct convolution created. This forward design, instead, create the
        smallest amount of costly direct convolution and costly small FFTs.
        Hours lost: 2.
    */
    void makePlan(int N, 
                  out int sizeOfDelayline,
                  out int maxUsedBlockSize,
                  out int directConvArea)
    {
        // Clear previous plan, if any
        _plan.clearContents();

        sizeOfDelayline = NaiveConvolver.delayLineNeeded(MIN_BLOCK_SIZE, _maxFrames);
        maxUsedBlockSize = 0;
        directConvArea = MIN_BLOCK_SIZE;
        if (directConvArea >= N)
        {
            directConvArea = N;
            return; // No block convolver
        }

        int n = directConvArea;
        assert(n < N);

        // Clear winner in benchmarks
        enum int M = 3;

        int blockSize = MIN_BLOCK_SIZE;

        // This really kicks after 300000 samples of IR, and is designed to support
        // those very long IRs. This will have a CPU impact of about -10% to 20% on
        // those loing IRs only, for supposedly better stability.
        enum bool SPIKE_PROTECTION = true;

        // How much MAX_BLOCK_SIZE blocks is too much for the same sample?
        // Stagger the counter around this one to lower CPU spikes.
        enum int PROBLEMATIC_MAX_BLOCKS = 6; // tuned

        // PERF: if we stagger the channels as in multichannel audio, we'd get better results than
        // staggering by lowering FDL length.

        int staggerIndex = 0; // only used for max block size staggering
        int staggerIncrement = 0;

        while(n < N)
        {
            int remain = N - n;
            int maxMultiplicity = (remain + blockSize - 1) / blockSize;
            assert(maxMultiplicity > 0);
            int initCounter = blockSize / 2;

            // Strategy to compute the right multiplicity
            int mult = M;

            // Special handling for largest block
            // who otherwise create CPU spikes.
            if (blockSize == MAX_BLOCK_SIZE)
            {
                static if (SPIKE_PROTECTION)
                {
                    // first time seeing largest block, compute stagger increment
                    // for all subsequent such steps
                    if (staggerIncrement == 0) 
                    {
                        int split = (maxMultiplicity + (PROBLEMATIC_MAX_BLOCKS - 1)) / PROBLEMATIC_MAX_BLOCKS;
                        assert(split > 0);
                        staggerIncrement = (blockSize / split);
                    }

                    initCounter += staggerIndex * staggerIncrement;
                    initCounter = initCounter % blockSize;
                    staggerIndex++;

                    // Cover all remaining blocks, but not more than
                    // `PROBLEMATIC_MAX_BLOCKS` at once.
                    //
                    // PERF: if split == 3 and maxMultiplicity == 13
                    // that makes block of 6, 6, 1 multiplicity, with less spike
                    // protection than say 4, 4, 5.
                    mult = PROBLEMATIC_MAX_BLOCKS;
                }
                else
                    mult = maxMultiplicity;
            }
            if (mult > maxMultiplicity) mult = maxMultiplicity;

            Step step;
            step.sizeOfBlock = blockSize;
            step.irOffset    = n;
            step.multiplicity = mult;
            step.initCounter = initCounter;
            _plan.pushBack(step);

            n += blockSize * step.multiplicity;

            // Will we need a larger delayline because of this step?
            int delayNeeded = FFTConvolver.delayLineNeeded(step.sizeOfBlock, _maxFrames, step.inputOffset(), step.multiplicity);
            if (sizeOfDelayline < delayNeeded)
                sizeOfDelayline = delayNeeded;

            maxUsedBlockSize = blockSize;

            // Try to increase block size as much as possible
            // PERF: last blocks could be tighter-fit
            // Even need to lower size for the remains
            // And then reorder the steps...
            while ((blockSize < MAX_BLOCK_SIZE) && (blockSize*2 <= n))
                blockSize *= 2;
        }
    }    


    /**
        Simplest convolver, only is fast for small impulses.

        Latency: 0 samples.
    */
    static struct NaiveConvolver
    {
    public nothrow @nogc:
        void setImpulse(const(T)[] impulse)
        {
            // Copy IR locally
            _impulseLen = cast(int) impulse.length;
            _impulse[0.._impulseLen] = impulse[];
        }

        static int delayLineNeeded(int impulseLen, int maxFrames)
        {
            return impulseLen + maxFrames;
        }

        // Note: entering this, delayline has already been 
        // .feedBuffer
        void nextBuffer(const(T)* input, 
                        T* output, 
                        int frames,
                        Delayline!T* delayline)
        {
            // Find pointer with latest sample, for n == 0
            const(T*) sample_0 = delayline.readPointer() - frames + 1;
            const(T*) impulse = _impulse.ptr;

            int len = _impulseLen;

            for (int n = 0; n < frames; ++n)
            {
                // This very input sample
                const(T)* thisSample = sample_0 + n;

                // Accumulate
                T sum = 0;
                for (int i = 0; i < len; ++i)
                    sum += thisSample[-i] * impulse[i];

                output[n] = sum;
            }
        }

    private :
        int _impulseLen;
        T[MIN_BLOCK_SIZE] _impulse;
    }

    /**
        FFT convolver, can only do pow2 impulses that are
        >= MIN_BLOCK_SIZE and <= 65536.

        Large FFT size are largely beneficial to speed.
        Latency: `blockSize` samples.

        Quantization noise: in double typically -150 dB RMS,
            the smaller FFT make less quantization noise.
    */
    static struct FFTConvolver
    {
    public:
        nothrow @nogc:

        /**
            Initialize the FFTConvolver.

            Params:
                maxFrames = Maximum amount of `frames` in nextBuffer.
                blockSize = Samples to process at once.
                inputDelay = How much in the past to sample in the input.
                multiplicity = Each FFTConvolver does `multiplicty` blocks 
                               to share the backwards FFT transform.
        */

        void initialize(int maxFrames, 
                        int blockSize, 
                        int inputDelay,
                        int multiplicity,
                        int initCounter)
        {
            // Doesn't work well below MIN_FFT_SIZE
            assert(blockSize >= MIN_BLOCK_SIZE);
            assert(blockSize <= 65536); // didn't test beyond
            assert(isPowerOfTwo(blockSize));
            assert(multiplicity >= 1);
            _inputDelay = inputDelay;
            _blockSize = blockSize;
            _fftSize   = blockSize * 2;
            _multiplicity = multiplicity;
            _FDLidx = 0;
            _counter = initCounter;

            realFFT.initialize(_fftSize);

            // _resA is a Frequency-Domain delay line (aka "FDL")
            // stores the transforms of `_multiplicity` input blocks.
            _resA.reallocBuffer((blockSize + 1) * _multiplicity);
            _resA[] = Complex!T(0, 0);

            // _resB stores the transforms of `_multiplicity` IR blocks.
            _resB.reallocBuffer((blockSize + 1) * _multiplicity);

            // Because convolution of N * N has length 2*N-1,
            // there is at most 2 overlapping segments, plus others 
            // that might be pushed in an audio buffer.
            // PERF: is this tight enough?
            int maxSegments = 2 + (maxFrames + (blockSize - 1)) / blockSize;
            _reconstruct.initialize(maxSegments, _fftSize);
        }

        // Copy IR locally and computes its zero-padded FFTs
        // Note: impulse.length might be less than _clockSize, 
        // in which case, more padding with zeroes.
        // It's up to the plan maker not to do excess multiplicities.
        // Note: The impulse isn't saved, only its transform.
        void setImpulse(const(T)[] impulse, T[] tempBuf)
        {
            // the same temp buffer is given to all sub-convolvers
            assert(tempBuf.length >= _fftSize);

            int coeffSize = _blockSize + 1;
            int remain = cast(int) impulse.length;
            int start = 0;

            for (int iblock = 0; iblock < _multiplicity; ++iblock)
            {
                int count = remain;
                if (count > _blockSize)
                    count = _blockSize;
                assert(count <= _blockSize);
                remain -= count;
                tempBuf[0 .. count] = impulse[start .. start+count];
                tempBuf[count .. _fftSize] = 0;
                start += count;
                realFFT.forwardTransform(tempBuf[0.._fftSize], 
                                         _resB[coeffSize*iblock..coeffSize*(iblock+1)]);
            }
            assert(remain == 0);
        }

        ~this()
        {
            _resA.reallocBuffer(0);
            _resB.reallocBuffer(0);
        }

        static int delayLineNeeded(int blockSize, int maxFrames, int inputDelay, int multiplicity)
        {
            return blockSize * multiplicity + maxFrames + inputDelay;
        }

        void nextBufferAccum(const(T)* input, 
                             T* output, 
                             int frames,
                             Delayline!T* delayline,  // has already been .feedBuffer
                             T[] tmpBuf,
                             Complex!T[] tmpBuf2)
        {
            assert(tmpBuf.length >= _fftSize);
            int coeffSize = _blockSize + 1;
            assert(tmpBuf2.length >= coeffSize);

            T[] inputBuf = tmpBuf[0.._fftSize];

            const(T*) readPtr = delayline.readPointer();

            Complex!T[] sumC = tmpBuf2[0..coeffSize];

            for (int n = 0; n < frames; ++n)
            {   
                ++_counter;
                if (_counter == _blockSize)
                {
                    _counter = 0;

                    // Go find the last pushed _blockSize samples
                    const(T*) posSampleN = readPtr + (-frames + 1 + n);
                    const(T*) posBlockStart = posSampleN + (-_blockSize + 1 -_inputDelay);
                    inputBuf[0.._blockSize] = posBlockStart[0.._blockSize];
                    inputBuf[_blockSize .. _fftSize] = 0;

                    // Forward transform, store in FDL
                    _FDLidx = (_FDLidx + 1) % _multiplicity;
                    realFFT.forwardTransform(inputBuf, _resA[coeffSize*_FDLidx .. coeffSize*(_FDLidx+1)]);

                    // Accumulate the different multiplicities
                    sumC[] = Complex!T(0, 0);
                    for (int iblock = 0; iblock < _multiplicity; ++iblock)
                    {
                        int srcBlock = (_FDLidx - iblock + _multiplicity) % _multiplicity;
                        Complex!T[] A = _resA[ coeffSize*srcBlock .. coeffSize * (srcBlock+1) ];
                        Complex!T[] B = _resB[ coeffSize*iblock .. coeffSize*(iblock+1) ];
                        sumC[] += A[] * B[];
                    }
                    realFFT.reverseTransform(sumC, inputBuf);

                    // Inverse transform.
                    // Warning: _inputBuf reused for result, which means the padding is gone.
                    // Warning: We need to add 1 here to have same latency as the block size,
                    //          which is useful in a larger convolver.
                    int whenToAccumulate = n + 1;
                    _reconstruct.startSegment(inputBuf, whenToAccumulate); 
                }
            }
            _reconstruct.nextBufferAccum(output, frames);
        }

    private:
        int _counter;
        int _blockSize;
        int _fftSize;
        int _inputDelay;
        int _multiplicity;

        // index of latest transformed input = _FDLidx
        // index of last   transformed input = (_FDLidx - 1) % _multiplicity
        int _FDLidx; 

        // PERF: could be indexed in a shared buffer
        Complex!T[] _resA;
        Complex!T[] _resB;

        ShortTermReconstruction!T _reconstruct;

        // MAYDO: if the whole ordeal was multi-channel, would merge 
        // those RFFT. But, it make the process much more complicated.
        RFFT!T realFFT; 
    }
}

//==============================================
// APPENDIX A. INITIAL COUNTERS FOR FFTConvolver
//==============================================
//
// IMPORTANT
//
// Block completion _counter is initialized 
// in a clever way ("staggered").
//
// Let's say block sizes are 2, 4, 8, 16:
//
// 1 means "process a FFT"
// 0 means "nothing to do"
//
// Without offsetting _counter:
//
//     size  2 0101010101010101
//     size  4 0001000100010001
//     size  8 0000000100000001
//     size 16 0000000000000001
//
// => all FFTs happen on the same sample!
//
// With offsetting _counter by block size / 2:
//
//     size  2 1010101010101010
//     size  4 0100010001000100
//     size  8 0001000000010000
//     size 16 0000000100000000
//
// => FFTs never happen on the same sample, 
//    up until a size is replicated.
//
// Beyond that, counter are staggered so that
// to be evenly replicated in the largest size.
// (if SPIKE_PROTECTION is true)
//
// Example:
//     size  2 1010101010101010
//     size  4 0100010001000100
//     size  8 0001000000010000
//     size 16 0100100100100100
//
// This is slower, but prevent CPU spikes.