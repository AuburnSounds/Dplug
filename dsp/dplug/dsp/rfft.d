module dplug.dsp.rfft;

/**

FFTReal.hpp
By Laurent de Soras

--- Legal stuff ---

This program is free software. It comes without any warranty, to
the extent permitted by applicable law. You can redistribute it
and/or modify it under the terms of the Do What The Fuck You Want
To Public License, Version 2, as published by Sam Hocevar. See
http://sam.zoy.org/wtfpl/COPYING for more details.

*/
/**
* Copyright: Copyright Auburn Sounds 2016.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
* What has changed? Shuffling was added to have a similar output than the regular complex FFT.
*/
import std.math: PI, sin, cos, SQRT1_2;

import dplug.core.math;
import dplug.core.complex;
import dplug.core.alignedbuffer;


/// Performs FFT from real input, and IFFT towards real output.
struct RFFT(T)
{
public:
nothrow:
@nogc:

    // Over this bit depth, we use direct calculation for sin/cos
    enum TRIGO_BD_LIMIT	= 12;
    
    void initialize(int length)
    {
        assert(length > 0);
        assert(isPowerOfTwo(length));
        _length = length;
        _nbr_bits = iFloorLog2(length);
        init_br_lut();
        init_trigo_lut();
        init_trigo_osc();
        _buffer.reallocBuffer(_length);
        _shuffledValues.reallocBuffer(_length);
    }

    ~this()
    {
        _br_lut.reallocBuffer(0);
        _trigo_lut.reallocBuffer(0);
        _trigo_osc.reallocBuffer(0);        
        _buffer.reallocBuffer(0); // temporary buffer
        _shuffledValues.reallocBuffer(0);
    }

    /**
    * Compute the Real FFT of the array.
    * Params:
    *    timeData Input array (N time samples)
    *    outputBins Destination coefficients (N/2 + 1 frequency bins)
    */
    void forwardTransform(const(T)[] timeData, BuiltinComplex!T[] outputBins)
    {
        assert(timeData.length == _length);
        assert(outputBins.length == (_length/2)+1);

        T[] f = _shuffledValues;

        if (_nbr_bits > 2)
        {
            compute_fft_general(f.ptr, timeData.ptr);
        }        
        else if (_nbr_bits == 2) // 4-point FFT
        {
            f[1] = timeData[0] - timeData[2];
            f[3] = timeData[1] - timeData[3];

            T b_0 = timeData[0] + timeData[2];
            T b_2 = timeData[1] + timeData[3];

            f[0] = b_0 + b_2;
            f[2] = b_0 - b_2;
        }        
        else if (_nbr_bits == 1) // 2-point FFT
        {
            f [0] = timeData[0] + timeData[1];
            f [1] = timeData[0] - timeData[1];
        }        
        else
        {
            f[0] = timeData[0]; // 1-point FFT
        }

        // At this point, f contains:
        //    f destination array (frequency bins)
        //    f[0...length(x)/2] = real values,
        //    f[length(x)/2+1...length(x)-1] = negative imaginary values of coefficents 1...length(x)/2-1.
        // So we have to reshuffle them to have nice complex bins.
        int mid = _length/2;
        outputBins[0] = f[0] + 0i;
        for(int i = 1; i < mid; ++i)
            outputBins[i] = f[i] + 1i * -f[mid+i];
        outputBins[mid] = f[mid] + 0i; // for length 1, this still works
    }

    /**
    * Compute the inverse FFT of the array. Perform post-scaling.
    *
    * Params:
	*    inputBins Source arrays (N/2 + 1 frequency bins)    
    *    timeData Destination array (N time samples).
    *
    * Note: 
    *    This transform has the benefit you don't have to conjugate the "mirorred" part of the FFT.
    *    Excess data in imaginary part of DC and Nyquist bins are ignored.
    */
    void reverseTransform(BuiltinComplex!T[] inputBins, T[] timeData) 
    {
        int mid = _length/2;
        assert(inputBins.length == mid+1); // expect _length/2+1 complex numbers, 
        assert(timeData.length == _length);

        // On inverse transform, scale down result
        T invMultiplier = cast(T)1 / _length;

        // Shuffle input frequency bins, and scale down.
        T[] f = _shuffledValues;
        for(int i = 0; i <= mid; ++i)
            f[i] = inputBins[i].re * invMultiplier;
        for(int i = mid+1; i < _length; ++i)
            f[i] = -inputBins[i-mid].im * invMultiplier;

        // At this point, the format in f is:
        //          f [0...length(x)/2] = real values
        //          f [length(x)/2+1...length(x)-1] = negative imaginary values of coefficents 1...length(x)/2-1.
        // Which is suitable for the RealFFT algorithm.

        if (_nbr_bits > 2) // General case
        {
            compute_ifft_general(f.ptr, timeData.ptr);
        }        
        else if (_nbr_bits == 2) // 4-point IFFT
        {
            const(T) b_0 = f[0] + f[2];
            const(T) b_2 = f[0] - f[2];
            timeData[0] = b_0 + f[1] * 2;
            timeData[2] = b_0 - f[1] * 2;
            timeData[1] = b_2 + f[3] * 2;
            timeData[3] = b_2 - f[3] * 2;
        }
        else if (_nbr_bits == 1) // 2-point IFFT
        {
            timeData[0] = f[0] + f[1];
            timeData[1] = f[0] - f[1];
        }
        else // 1-point IFFT
        {
            timeData[0] = f[0];
        }
    }

private:

    int _nbr_bits;
    int _length;
    int[] _br_lut;
    T[] _trigo_lut;    
    OscSinCos!T[] _trigo_osc;
    T[] _buffer; // temporary buffer
    T[] _shuffledValues; // shuffled values, output of the RFFT and input of IRFFT

    // Returns: temporary buffer
    T* use_buffer()
    {
        return _buffer.ptr;
    }

    const(int)* get_br_ptr() pure const
    {
        return _br_lut.ptr;
    }

    int get_trigo_level_index(int level) pure const
    {
        assert(level >= 3);
        return((1 << (level - 1)) - 4);
    }

    const(T)* get_trigo_ptr(int level) pure const
    {
        return (&_trigo_lut [get_trigo_level_index (level)]);
    }

    void init_br_lut ()
    {
        int length = 1 << _nbr_bits;
        _br_lut.reallocBuffer(length);
        _br_lut[0] = 0;
        int br_index = 0;
        for (int cnt = 1; cnt < length; ++cnt)
        {
            // ++br_index (bit reversed)
            int bit = length >> 1;
            while (((br_index ^= bit) & bit) == 0)
            {
                bit >>= 1;
            }
            _br_lut[cnt] = br_index;
        }
    }

    void init_trigo_lut()
    {
        if (_nbr_bits > 3)
        {
            int	total_len = (1 << (_nbr_bits - 1)) - 4;
            _trigo_lut.reallocBuffer(total_len);

            for (int level = 3; level < _nbr_bits; ++level)
            {
                int level_len = 1 << (level - 1);
                T* level_ptr = &_trigo_lut [get_trigo_level_index (level)];
                double mul = PI / (level_len << 1);
                for (int i = 0; i < level_len; ++ i)
                {
                    level_ptr[i] = cast(T)(cos (i * mul));
                }
            }
        }
    }

    void init_trigo_osc ()
    {
        int	nbr_osc = _nbr_bits - TRIGO_BD_LIMIT;
        if (nbr_osc > 0)
        {
            _trigo_osc.reallocBuffer(nbr_osc);
            for (int osc_cnt = 0; osc_cnt < nbr_osc; ++osc_cnt)
            {
                const int		len = 1 << (TRIGO_BD_LIMIT + osc_cnt);
                const double	mul = (0.5 * PI) / len;
                _trigo_osc[osc_cnt].setStep(mul);
            }
        }
    }

    // Transform in several passes
    void compute_fft_general (T* f, const(T)* x)
    {
        T*		sf;
        T*		df;

        if ((_nbr_bits & 1) != 0)
        {
            df = use_buffer();
            sf = f;
        }
        else
        {
            df = f;
            sf = use_buffer();
        }

        compute_direct_pass_1_2 (df, x);
        compute_direct_pass_3 (sf, df);

        for (int pass = 3; pass < _nbr_bits; ++ pass)
        {
            compute_direct_pass_n (df, sf, pass);
            T* temp_ptr = df;
            df = sf;
            sf = temp_ptr;
        }
    }

    void compute_direct_pass_1_2 (T* df, const(T)* x)
    {
        const(int)* bit_rev_lut_ptr = get_br_ptr();
        int				coef_index = 0;
        do
        {
            const int		rev_index_0 = bit_rev_lut_ptr [coef_index];
            const int		rev_index_1 = bit_rev_lut_ptr [coef_index + 1];
            const int		rev_index_2 = bit_rev_lut_ptr [coef_index + 2];
            const int		rev_index_3 = bit_rev_lut_ptr [coef_index + 3];

            T* df2 = df + coef_index;
            df2 [1] = x [rev_index_0] - x [rev_index_1];
            df2 [3] = x [rev_index_2] - x [rev_index_3];

            const(T)	sf_0 = x [rev_index_0] + x [rev_index_1];
            const(T)	sf_2 = x [rev_index_2] + x [rev_index_3];

            df2 [0] = sf_0 + sf_2;
            df2 [2] = sf_0 - sf_2;

            coef_index += 4;
        }
        while (coef_index < _length);
    }



    void compute_direct_pass_3 (T* df, const(T)* sf)
    {
        alias sqrt2_2 = SQRT1_2;
        int				coef_index = 0;
        do
        {
            T			v;

            df [coef_index] = sf [coef_index] + sf [coef_index + 4];
            df [coef_index + 4] = sf [coef_index] - sf [coef_index + 4];
            df [coef_index + 2] = sf [coef_index + 2];
            df [coef_index + 6] = sf [coef_index + 6];

            v = (sf [coef_index + 5] - sf [coef_index + 7]) * sqrt2_2;
            df [coef_index + 1] = sf [coef_index + 1] + v;
            df [coef_index + 3] = sf [coef_index + 1] - v;

            v = (sf [coef_index + 5] + sf [coef_index + 7]) * sqrt2_2;
            df [coef_index + 5] = v + sf [coef_index + 3];
            df [coef_index + 7] = v - sf [coef_index + 3];

            coef_index += 8;
        }
        while (coef_index < _length);
    }

    void compute_direct_pass_n (T* df, const(T)* sf, int pass)
    {
        assert (pass >= 3);
        assert (pass < _nbr_bits);

        if (pass <= TRIGO_BD_LIMIT)
        {
            compute_direct_pass_n_lut (df, sf, pass);
        }
        else
        {
            compute_direct_pass_n_osc (df, sf, pass);
        }
    }



    void compute_direct_pass_n_lut (T* df, const(T)* sf, int pass)
    {
        assert (pass >= 3);
        assert (pass < _nbr_bits);

        const int		nbr_coef = 1 << pass;
        const int		h_nbr_coef = nbr_coef >> 1;
        const int		d_nbr_coef = nbr_coef << 1;
        int				coef_index = 0;
        const(T)	* cos_ptr = get_trigo_ptr (pass);
        do
        {
            const(T)	* sf1r = sf + coef_index;
            const(T)	* sf2r = sf1r + nbr_coef;
            T			* dfr = df + coef_index;
            T			* dfi = dfr + nbr_coef;

            // Extreme coefficients are always real
            dfr [0] = sf1r [0] + sf2r [0];
            dfi [0] = sf1r [0] - sf2r [0];	// dfr [nbr_coef] =
            dfr [h_nbr_coef] = sf1r [h_nbr_coef];
            dfi [h_nbr_coef] = sf2r [h_nbr_coef];

            // Others are conjugate complex numbers
            const(T) * sf1i = sf1r + h_nbr_coef;
            const(T) * sf2i = sf1i + nbr_coef;
            for (int i = 1; i < h_nbr_coef; ++ i)
            {
                const(T)	c = cos_ptr [i];					// cos (i*PI/nbr_coef);
                const(T)	s = cos_ptr [h_nbr_coef - i];	// sin (i*PI/nbr_coef);
                T	 		v;

                v = sf2r [i] * c - sf2i [i] * s;
                dfr [i] = sf1r [i] + v;
                dfi [-i] = sf1r [i] - v;	// dfr [nbr_coef - i] =

                v = sf2r [i] * s + sf2i [i] * c;
                dfi [i] = v + sf1i [i];
                dfi [nbr_coef - i] = v - sf1i [i];
            }

            coef_index += d_nbr_coef;
        }
        while (coef_index < _length);
    }

    void compute_direct_pass_n_osc (T* df, const(T)* sf, int pass)
    {
        assert (pass > TRIGO_BD_LIMIT);
        assert (pass < _nbr_bits);

        const int		nbr_coef = 1 << pass;
        const int		h_nbr_coef = nbr_coef >> 1;
        const int		d_nbr_coef = nbr_coef << 1;
        int				coef_index = 0;
        OscSinCos!T*      osc = &_trigo_osc[pass - (TRIGO_BD_LIMIT + 1)];
        do
        {
            const(T)	* sf1r = sf + coef_index;
            const(T)	* sf2r = sf1r + nbr_coef;
            T			* dfr = df + coef_index;
            T			* dfi = dfr + nbr_coef;

            osc.resetPhase();

            // Extreme coefficients are always real
            dfr [0] = sf1r [0] + sf2r [0];
            dfi [0] = sf1r [0] - sf2r [0];	// dfr [nbr_coef] =
            dfr [h_nbr_coef] = sf1r [h_nbr_coef];
            dfi [h_nbr_coef] = sf2r [h_nbr_coef];

            // Others are conjugate complex numbers
            const(T) * sf1i = sf1r + h_nbr_coef;
            const(T) * sf2i = sf1i + nbr_coef;
            for (int i = 1; i < h_nbr_coef; ++ i)
            {
                osc.step ();
                const(T)	c = osc.getCos;
                const(T)	s = osc.getSin;
                T	 		v;

                v = sf2r [i] * c - sf2i [i] * s;
                dfr [i] = sf1r [i] + v;
                dfi [-i] = sf1r [i] - v;	// dfr [nbr_coef - i] =

                v = sf2r [i] * s + sf2i [i] * c;
                dfi [i] = v + sf1i [i];
                dfi [nbr_coef - i] = v - sf1i [i];
            }

            coef_index += d_nbr_coef;
        }
        while (coef_index < _length);
    }

    // Transform in several pass
    void compute_ifft_general (const(T)* f, T* x)
    {
        T* sf = cast(T*)(f);
        T *		df;
        T *		df_temp;

        if (_nbr_bits & 1)
        {
            df = use_buffer();
            df_temp = x;
        }
        else
        {
            df = x;
            df_temp = use_buffer();
        }

        for (int pass = _nbr_bits - 1; pass >= 3; -- pass)
        {
            compute_inverse_pass_n (df, sf, pass);

            if (pass < _nbr_bits - 1)
            {
                T* temp_ptr = df;
                df = sf;
                sf = temp_ptr;
            }
            else
            {
                sf = df;
                df = df_temp;
            }
        }

        compute_inverse_pass_3 (df, sf);
        compute_inverse_pass_1_2 (x, df);
    }

    void compute_inverse_pass_n (T* df, const(T)* sf, int pass)
    {
        assert (pass >= 3);
        assert (pass < _nbr_bits);

        if (pass <= TRIGO_BD_LIMIT)
        {
            compute_inverse_pass_n_lut (df, sf, pass);
        }
        else
        {
            compute_inverse_pass_n_osc (df, sf, pass);
        }
    }

    void compute_inverse_pass_n_lut (T* df, const(T)* sf, int pass)
    {
        assert (pass >= 3);
        assert (pass < _nbr_bits);

        const int		nbr_coef = 1 << pass;
        const int		h_nbr_coef = nbr_coef >> 1;
        const int		d_nbr_coef = nbr_coef << 1;
        int				coef_index = 0;
        const(T)* cos_ptr = get_trigo_ptr (pass);
        do
        {
            const(T)	* sfr = sf + coef_index;
            const(T)	* sfi = sfr + nbr_coef;
            T			* df1r = df + coef_index;
            T			* df2r = df1r + nbr_coef;

            // Extreme coefficients are always real
            df1r [0] = sfr [0] + sfi [0];		// + sfr [nbr_coef]
            df2r [0] = sfr [0] - sfi [0];		// - sfr [nbr_coef]
            df1r [h_nbr_coef] = sfr [h_nbr_coef] * 2;
            df2r [h_nbr_coef] = sfi [h_nbr_coef] * 2;

            // Others are conjugate complex numbers
            T * 	df1i = df1r + h_nbr_coef;
            T * 	df2i = df1i + nbr_coef;
            for (int i = 1; i < h_nbr_coef; ++ i)
            {
                df1r [i] = sfr [i] + sfi [-i];		// + sfr [nbr_coef - i]
                df1i [i] = sfi [i] - sfi [nbr_coef - i];

                const(T)	c = cos_ptr [i];					// cos (i*PI/nbr_coef);
                const(T)	s = cos_ptr [h_nbr_coef - i];	// sin (i*PI/nbr_coef);
                const(T)	vr = sfr [i] - sfi [-i];		// - sfr [nbr_coef - i]
                const(T)	vi = sfi [i] + sfi [nbr_coef - i];

                df2r [i] = vr * c + vi * s;
                df2i [i] = vi * c - vr * s;
            }

            coef_index += d_nbr_coef;
        }
        while (coef_index < _length);
    }

    void compute_inverse_pass_n_osc (T* df, const(T)* sf, int pass)
    {
        assert (pass > TRIGO_BD_LIMIT);
        assert (pass < _nbr_bits);

        const int		nbr_coef = 1 << pass;
        const int		h_nbr_coef = nbr_coef >> 1;
        const int		d_nbr_coef = nbr_coef << 1;
        int				coef_index = 0;
        OscSinCos!T*    osc = &_trigo_osc[pass - (TRIGO_BD_LIMIT + 1)];
        do
        {
            const(T)	* sfr = sf + coef_index;
            const(T)	* sfi = sfr + nbr_coef;
            T			* df1r = df + coef_index;
            T			* df2r = df1r + nbr_coef;

            osc.resetPhase ();

            // Extreme coefficients are always real
            df1r [0] = sfr [0] + sfi [0];		// + sfr [nbr_coef]
            df2r [0] = sfr [0] - sfi [0];		// - sfr [nbr_coef]
            df1r [h_nbr_coef] = sfr [h_nbr_coef] * 2;
            df2r [h_nbr_coef] = sfi [h_nbr_coef] * 2;

            // Others are conjugate complex numbers
            T * df1i = df1r + h_nbr_coef;
            T * df2i = df1i + nbr_coef;
            for (int i = 1; i < h_nbr_coef; ++ i)
            {
                df1r [i] = sfr [i] + sfi [-i];		// + sfr [nbr_coef - i]
                df1i [i] = sfi [i] - sfi [nbr_coef - i];

                osc.step ();
                const(T)	c = osc.getCos;
                const(T)	s = osc.getSin;
                const(T)	vr = sfr [i] - sfi [-i];		// - sfr [nbr_coef - i]
                const(T)	vi = sfi [i] + sfi [nbr_coef - i];

                df2r [i] = vr * c + vi * s;
                df2i [i] = vi * c - vr * s;
            }

            coef_index += d_nbr_coef;
        }
        while (coef_index < _length);
    }



    void compute_inverse_pass_3 (T* df, const(T)* sf)
    {
        alias sqrt2_2 = SQRT1_2;
        int				coef_index = 0;
        do
        {
            df [coef_index] = sf [coef_index] + sf [coef_index + 4];
            df [coef_index + 4] = sf [coef_index] - sf [coef_index + 4];
            df [coef_index + 2] = sf [coef_index + 2] * 2;
            df [coef_index + 6] = sf [coef_index + 6] * 2;

            df [coef_index + 1] = sf [coef_index + 1] + sf [coef_index + 3];
            df [coef_index + 3] = sf [coef_index + 5] - sf [coef_index + 7];

            const(T)	vr = sf [coef_index + 1] - sf [coef_index + 3];
            const(T)	vi = sf [coef_index + 5] + sf [coef_index + 7];

            df [coef_index + 5] = (vr + vi) * sqrt2_2;
            df [coef_index + 7] = (vi - vr) * sqrt2_2;

            coef_index += 8;
        }
        while (coef_index < _length);
    }

    void compute_inverse_pass_1_2 (T* x, const(T)* sf)
    {
        const(int) *	bit_rev_lut_ptr = get_br_ptr ();
        const(T) *	sf2 = sf;
        int				coef_index = 0;
        do
        {
            {
                const(T)	b_0 = sf2 [0] + sf2 [2];
                const(T)	b_2 = sf2 [0] - sf2 [2];
                const(T)	b_1 = sf2 [1] * 2;
                const(T)	b_3 = sf2 [3] * 2;

                x [bit_rev_lut_ptr [0]] = b_0 + b_1;
                x [bit_rev_lut_ptr [1]] = b_0 - b_1;
                x [bit_rev_lut_ptr [2]] = b_2 + b_3;
                x [bit_rev_lut_ptr [3]] = b_2 - b_3;
            }
            {
                const(T)	b_0 = sf2 [4] + sf2 [6];
                const(T)	b_2 = sf2 [4] - sf2 [6];
                const(T)	b_1 = sf2 [5] * 2;
                const(T)	b_3 = sf2 [7] * 2;

                x [bit_rev_lut_ptr [4]] = b_0 + b_1;
                x [bit_rev_lut_ptr [5]] = b_0 - b_1;
                x [bit_rev_lut_ptr [6]] = b_2 + b_3;
                x [bit_rev_lut_ptr [7]] = b_2 - b_3;
            }

            sf2 += 8;
            coef_index += 8;
            bit_rev_lut_ptr += 8;
        }
        while (coef_index < _length);
    }

    static struct OscSinCos(T)
    {
    public:
    nothrow:
    pure:
    @nogc:
        void setStep(double angleRad)
        {
            _step_cos = cast(T)(cos(angleRad));
            _step_sin = cast(T)(sin(angleRad));
        }

        alias getCos = _pos_cos;
        alias getSin = _pos_sin;

        void resetPhase()
        {
            _pos_cos = 1;
            _pos_sin = 0;
        }

        void step()
        {
            T old_cos = _pos_cos;
            T old_sin = _pos_sin;
            _pos_cos = old_cos * _step_cos - old_sin * _step_sin;
            _pos_sin = old_cos * _step_sin + old_sin * _step_cos;
        }

        T _pos_cos = 1;		// Current phase expressed with sin and cos. [-1 ; 1]
        T _pos_sin = 0;		// -
        T _step_cos = 1;		// Phase increment per step, [-1 ; 1]
        T _step_sin = 0;		// -
    }
}

unittest
{
    import std.numeric: fft, approxEqual;
    import dplug.dsp.rfft;
    import std.stdio; // TEMP
    import dplug.core.random;
    import std.complex;

    auto random = defaultGlobalRNG();

    void testRFFT(T)(T[] A)
    {
        // Takes reference fft
        Complex!T[] reference = fft!T(A);

        RFFT!T rfft;
        rfft.initialize(cast(int)A.length);

        int N = cast(int)(A.length);
        BuiltinComplex!T[] B;
        T[] C;
        B.reallocBuffer(N/2+1);
        C.reallocBuffer(N);

        rfft.forwardTransform(A, B);

        foreach(i; 0..N/2+1)
        {
            if (!approxEqual(reference[i].re, B[i].re))
                assert(false);
            if (!approxEqual(reference[i].im, B[i].im))
                assert(false);
        }
        rfft.reverseTransform(B, C);

        foreach(i; 0..N)
        {
            if (!approxEqual(A[i].re, C[i].re))
                assert(false);
            if (!approxEqual(A[i].im, C[i].im))
                assert(false);
        }

        B.reallocBuffer(0);
        C.reallocBuffer(0);
    }
    testRFFT!float([0.5f]);
    testRFFT!float([1, 2]);
    testRFFT!float([1, 13, 5, 0]);
    testRFFT!float([1, 13, 5, 0, 2, 0, 4, 0]);

    // test larger FFTs
    uint seed = 1;
    for(int bit = 4; bit < 16; ++bit)
    {
        int size = 1 << bit;
        double[] sequence = new double[size];
        foreach(i; 0..size)
            sequence[i] = nogc_uniform_float(-1.0f, 1.0f, random);
        testRFFT!double(sequence);
    }
}
