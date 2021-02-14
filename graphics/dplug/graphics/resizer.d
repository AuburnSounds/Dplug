/**
* 
* AVIR Copyright (c) 2015-2020 Aleksey Vaneev
*
* Translation of lancir.h
*
* @section intro_sec Introduction
*
* Description is available at https://github.com/avaneev/avir
*
*
* AVIR License Agreement
*
* The MIT License (MIT)
*
* Copyright (c) 2015-2020 Aleksey Vaneev
*
* Permission is hereby granted, free of charge, to any person obtaining a
* copy of this software and associated documentation files (the "Software"),
* to deal in the Software without restriction, including without limitation
* the rights to use, copy, modify, merge, publish, distribute, sublicense,
* and/or sell copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
* DEALINGS IN THE SOFTWARE.
*/
/**
Resizer ported to D from C++, based on https://github.com/avaneev/avir "lancir" method.
Copyright: (c) Guillaume Piolat (2021)
*/
module dplug.graphics.resizer;

import std.math: PI;
import dplug.core.math;
import dplug.core.vec;
import dplug.graphics.color;
import dplug.graphics.image;

/// Image resizer.
/// To minimize CPU, it is advised to reuse that object for similar resize.
/// To minimize memory allocation, it is advised to reuse that object even across different resize.
struct ImageResizer
{
public:
nothrow:
@nogc:

    @disable this(this);

    /**
    * Function resizes image.
    *
    * Params:
    *   input Input image.
    *   output Output image.
    *   kx0 Resizing step - horizontal (one output pixel corresponds to
    *       "k" input pixels). A downsizing factor if > 1.0; upsizing factor
    *       if <= 1.0. Multiply by -1 if you would like to bypass "ox" and "oy"
    *       adjustment which is done by default to produce a centered image. If
    *       step value equals 0, the step value will be chosen automatically.
    *   ky0 Resizing step - vertical. Same as "kx".
    *   ox Start X pixel offset within source image (can be negative).
    *      Positive offset moves the image to the left.
    *   oy Start Y pixel offset within source image (can be negative).
    *      Positive offset moves the image to the top.
    * 
    * T is the Input and output buffer element's type. Can be ubyte
    * (0-255 value range), ushort (0-65535 value range), float
    * (any value range), double (any value range). Larger integer types are
    * treated as ushort. Signed integer types are unsupported.
    */

    void resizeImage(ImageRef!RGBA input, ImageRef!RGBA output,
                     double kx0 = 0.0, double ky0 = 0.0,
                     double ox = 0.0, double oy = 0.0)
    {
        _lancir.resizeImage!ubyte(cast(ubyte*) input.pixels, input.w, input.h, input.pitch,
                                  cast(ubyte*) output.pixels, output.w, output.h, output.pitch,
                                  4, kx0, ky0, ox, oy);
    }

    ///ditto
    void resizeImage(ImageRef!L16 input, ImageRef!L16 output,
                     double kx0 = 0.0, double ky0 = 0.0,
                     double ox = 0.0, double oy = 0.0)
    {
        _lancir.resizeImage!ushort(cast(ushort*) input.pixels, input.w, input.h, input.pitch,
                                   cast(ushort*) output.pixels, output.w, output.h, output.pitch,
                                   1, kx0, ky0, ox, oy);
    }

    ///ditto
    void resizeImage(ImageRef!L8 input, ImageRef!L8 output,
                     double kx0 = 0.0, double ky0 = 0.0,
                     double ox = 0.0, double oy = 0.0)
    {
        _lancir.resizeImage!ubyte(cast(ubyte*) input.pixels, input.w, input.h, input.pitch,
                                  cast(ubyte*) output.pixels, output.w, output.h, output.pitch,
                                  1, kx0, ky0, ox, oy);
    }

private:
    CLancIR _lancir;
}

private:


alias LANCIR_PI = PI;

/**
 * @brief LANCIR image resizer class.
 *
 * The object of this class can be used to resize 1-4 channel images to any
 * required size. Resizing is performed by utilizing Lanczos filters, with
 * 8-bit precision. This class offers a kind of "optimal" Lanczos resampling
 * implementation.
 *
 * Object of this class can be allocated on stack.
 *
 * Note that object of this class does not free temporary buffers and
 * variables after the resizeImage() call (until object's destruction), these
 * buffers are reused on subsequent calls making batch resizing of same-size
 * images faster. This means resizing is not thread-safe: a separate object
 * should be created for each thread.
 */

struct CLancIR
{
public:
nothrow:
@nogc:

    @disable this(this);

    ~this()
    {
        alignedFree(FltBuf.ptr, 1);
    }

    void resizeImage(T)( const(T*) SrcBuf, 
                         const int SrcWidth,
                         const int SrcHeight, 
                         ptrdiff_t srcScanlineBytes, 
                         T* NewBuf,
                         const int NewWidth, 
                         const int NewHeight, 
                         ptrdiff_t newScanlineBytes, 
                         const int ElCount,
                         const double kx0, 
                         const double ky0, 
                         double ox, 
                         double oy )
    {
        // Removing support for 2 and 3 ElCount wins some code size.
        assert(ElCount == 1 || ElCount == 4); 

        if( NewWidth <= 0 || NewHeight <= 0 )
        {
            return;
        }

        if( SrcWidth <= 0 || SrcHeight <= 0 )
        {
            for (int y = 0; y < NewHeight; ++y)
            {
                T* p = cast(T*)( (cast(ubyte*)NewBuf) + newScanlineBytes );
                size_t elemsInScan = NewWidth * ElCount;
                p[0..elemsInScan] = 0; // no source pixels, output only zeroes.
            }
        }

        const double la = 3.0;
        double kx;
        double ky;

        if( kx0 == 0.0 )
        {
            if( NewWidth > SrcWidth )
            {
                kx = cast(double) ( SrcWidth - 1 ) / ( NewWidth - 1 );
            }
            else
            {
                kx = cast(double) SrcWidth / NewWidth;
                ox += ( kx - 1.0 ) * 0.5;
            }
        }
        else
        if( kx0 > 0.0 )
        {
            kx = kx0;

            if( kx0 > 1.0 )
            {
                ox += ( kx0 - 1.0 ) * 0.5;
            }
        }
        else
        {
            kx = -kx0;
        }

        if( ky0 == 0.0 )
        {
            if( NewHeight > SrcHeight )
            {
                ky = cast(double) ( SrcHeight - 1 ) / ( NewHeight - 1 );
            }
            else
            {
                ky = cast(double) SrcHeight / NewHeight;
                oy += ( ky - 1.0 ) * 0.5;
            }
        }
        else
        if( ky0 > 0.0 )
        {
            ky = ky0;

            if( ky0 > 1.0 )
            {
                oy += ( ky0 - 1.0 ) * 0.5;
            }
        }
        else
        {
            ky = -ky0;
        }

        if( rfh.update( la, kx ))
        {
            rsh.reset();
            rsv.reset();
        }

        // Pointer to resizing filters for vertical resizing, may equal to "rfh" if the same stepping is in use.
        CResizeFilters* rfv; 

        if( ky == kx )
        {
            rfv = &rfh;
        }
        else
        {
            rfv = &rfv0;

            if( rfv0.update( la, ky ))
            {
                rsv.reset();
            }
        }

        rsh.update( kx, ox, ElCount, SrcWidth, NewWidth, rfh );
        rsv.update( ky, oy, ElCount, SrcHeight, NewHeight, *rfv );

        const int NewWidthE = NewWidth * ElCount;

        // Allocate/resize temporary buffer.

        const size_t FltBufLenNew = cast(size_t) NewWidthE * cast(size_t) SrcHeight;
        // Note: because Vec is over-allocating
        float* buf = cast(float*) alignedReallocDiscard(FltBuf.ptr, FltBufLenNew * float.sizeof, 1);
        FltBuf = buf[0..FltBufLenNew];
      
        // Perform horizontal resizing.

        const(ubyte)* ips = cast(const(ubyte)*) SrcBuf;
        float* op = FltBuf.ptr;
        int i;

        if( ElCount == 1 )
        {
            for( i = 0; i < SrcHeight; i++ )
            {
                copyScanline1h( cast(const(T)*) ips, rsh, SrcWidth );
                resize1( op, NewWidth, rsh.pos.ptr, rfh.KernelLen );
                ips += srcScanlineBytes;
                op += NewWidthE;
            }
        }
        else if( ElCount == 4 )
        {
            for( i = 0; i < SrcHeight; i++ )
            {
                copyScanline4h!T( cast(const(T)*) ips, rsh, SrcWidth );
                resize4( op, NewWidth, rsh.pos.ptr, rfh.KernelLen );
                ips += srcScanlineBytes;
                op += NewWidthE;
            }
        }
        else
            assert(false);

        // Perform vertical resizing.

        const int spvlennew = NewHeight * ElCount;
        spv.resize(spvlennew);

        const bool IsIOFloat = ( (cast(T) 0.25) != 0 );
        const int Clamp = ( T.sizeof == 1 ? 255 : 65535 );
        const(float)* ip = FltBuf.ptr;
        T* opd = NewBuf;

        if( ElCount == 1 )
        {
            for( i = 0; i < NewWidth; i++ )
            {
                copyScanline1v( ip, rsv, SrcHeight, NewWidthE );
                resize1( spv.ptr, NewHeight, rsv.pos.ptr, rfv.KernelLen );
                copyOutput1( spv.ptr, opd, NewHeight, newScanlineBytes, IsIOFloat, Clamp);

                ip++;
                opd++;
            }
        }
        else if( ElCount == 4 )
        {
            for( i = 0; i < NewWidth; i++ )
            {
                copyScanline4v( ip, rsv, SrcHeight, NewWidthE );
                resize4( spv.ptr, NewHeight, rsv.pos.ptr, rfv.KernelLen );
                copyOutput4( spv.ptr, opd, NewHeight, newScanlineBytes, IsIOFloat, Clamp);
                ip += 4;
                opd += 4;
            }
        }
        else
            assert(false);
    }

protected:

    float[] FltBuf;      // Intermediate resizing buffer.
    Vec!float spv;         // Scanline buffer for vertical resizing.    

    /**
     * Function rounds a value and applies clamping.
     *
     * @param v Value to round and clamp.
     * @param Clamp High clamp level, low level is 0.
     */

    static int roundclamp( const float v, const int Clamp )
    {
        if( v <= 0.0f )
        {
            return( 0 );
        }

        const int vr = cast(int) ( v + 0.5f );

        if( vr > Clamp )
        {
            return( Clamp );
        }

        return( vr );
    }

    /**
     * Function performs final output of the resized scanline data to the
     * destination image buffer. Variants for 1-4-channel image.
     *
     * @param ip Input resized scanline.
     * @param op Output image buffer.
     * @param l Pixel count.
     * @param pitchInBytes "op" increment in bytes.
     * @param IsIOFloat "True" if float output and no clamping is necessary.
     * @param Clamp Clamp high level, used if IsIOFloat is "false".
     */

    static void copyOutput1(T)( const(float)* ip, T* op, int l, ptrdiff_t pitchInBytes, const bool IsIOFloat, const int Clamp )
    {
        if( IsIOFloat )
        {
            while( l > 0 )
            {
                op[ 0 ] = cast(T) ip[ 0 ];
                ip++;
                op = cast(T*)( (cast(ubyte*)op) + pitchInBytes );
                l--;
            }
        }
        else
        {
            while( l > 0 )
            {
                op[ 0 ] = cast(T) roundclamp( ip[ 0 ], Clamp );
                ip++;
                op = cast(T*)( (cast(ubyte*)op) + pitchInBytes );
                l--;
            }
        }
    }

    static void copyOutput4(T)( const(float)* ip, T* op, int l, ptrdiff_t pitchInBytes, const bool IsIOFloat, const int Clamp )
    {
        if( IsIOFloat )
        {
            while( l > 0 )
            {
                op[ 0 ] = cast(T) ip[ 0 ];
                op[ 1 ] = cast(T) ip[ 1 ];
                op[ 2 ] = cast(T) ip[ 2 ];
                op[ 3 ] = cast(T) ip[ 3 ];
                ip += 4;
                op = cast(T*)( (cast(ubyte*)op) + pitchInBytes );
                l--;
            }
        }
        else
        {
            while( l > 0 )
            {
                op[ 0 ] = cast(T) roundclamp( ip[ 0 ], Clamp );
                op[ 1 ] = cast(T) roundclamp( ip[ 1 ], Clamp );
                op[ 2 ] = cast(T) roundclamp( ip[ 2 ], Clamp );
                op[ 3 ] = cast(T) roundclamp( ip[ 3 ], Clamp );
                ip += 4;
                op = cast(T*)( (cast(ubyte*)op) + pitchInBytes );
                l--;
            }
        }
    }

    /**
     * Class implements fractional delay filter bank calculation.
     */

    static struct CResizeFilters
    {
    nothrow:
    @nogc:

    @disable this(this);

    public:
        int KernelLen; // Resampling filter kernel length, taps. Available after the update() function call.

        /**
         * Function updates the resizing filter bank.
         *
         * @param la Lanczos "a" parameter value.
         * @param k Resizing step.
         * @return "True" if update occured and resizing positions should be
         * updated unconditionally.
         */

        bool update( const double la, const double k )
        {
            if( la == Prevla && k == Prevk )
            {
                return( false );
            }

            Prevla = la;
            Prevk = k;

            NormFreq = ( k <= 1.0 ? 1.0 : 1.0 / k );
            Freq = LANCIR_PI * NormFreq;

            if( Freq > LANCIR_PI )
            {
                Freq = LANCIR_PI;
            }

            FreqA = LANCIR_PI * NormFreq / la;
            Len2 = la / NormFreq;
            fl2 = cast(int) fast_ceil( Len2 );
            KernelLen = fl2 + fl2;

            // For 8-bit precision.
            // Note: minor quality improvement if increasing this number, but quite expensive too.
            FracCount = 607; 
            FracFill = 0;

            const int FilterBufLenNew = ( FracCount + 1 ) * KernelLen;
                // Add +1 to cover rare cases of fractional delay == 1.

            FilterBuf.resize(FilterBufLenNew);

            Filters.resize(FracCount + 1);
            Filters.fill(null);
            return true;
        }

        /**
         * Function returns filter at the specified fractional offset. This
         * function can only be called before the prior update() function
         * call.
         *
         * @param x Fractional offset, [0; 1).
         */

        float* getFilter( const double x )
        {
            const int Frac = cast(int) fast_floor( x * FracCount );

            if( Filters[ Frac ] == null )
            {
                Filters[ Frac ] = FilterBuf.ptr + FracFill * KernelLen;
                FracFill++;
                makeFilter( 1.0 - cast(double) Frac / FracCount, Filters[ Frac ]);
                normalizeFilter( Filters[ Frac ]);
            }

            return( Filters[ Frac ]);
        }

    protected:


        double NormFreq; // Normalized frequency of the filter.
        double Freq; // Circular frequency of the filter.
        double FreqA; // Circular frequency of the window function.
        double Len2; // Half resampling filter length, unrounded.
        int fl2; // Half resampling length, integer.
        int FracCount; // The number of fractional positions for which filters are created.
        int FracFill; // The number of fractional positions filled in the filter buffer.
        Vec!float FilterBuf; // Buffer that holds all filters.
        Vec!(float*) Filters; // Fractional delay filters for all positions.
                              // Filter pointers equal null if filter was not yet created.
        double Prevla = -1.0; // Previous "la".
        double Prevk = -1.0; // Previous "k".
        int FiltersLen; // Allocated length of Filters in elements.

        /**
         * Function creates filter for the specified fractional delay. The
         * update() function should be called prior to calling this function.
         *
         * @param FracDelay Fractional delay, 0 to 1, inclusive.
         * @param[out] Output filter buffer.
         * @tparam T Output buffer type.
         */

        void makeFilter(T)( const double FracDelay, T* op ) const
        {
            CSinGen f = CSinGen( Freq, Freq * ( FracDelay - fl2 ));
            CSinGen fw = CSinGen( FreqA, FreqA * ( FracDelay - fl2 ), Len2 );

            int t = -fl2;

            if( t + FracDelay < -Len2 )
            {
                f.generate();
                fw.generate();
                *op = cast(T) 0.0;
                op++;
                t++;
            }

            int mt = ( FracDelay >= 1.0 - 1e-13 && FracDelay <= 1.0 + 1e-13 ?
                -1 : 0 );

            while( t < mt )
            {
                double ut = ( t + FracDelay ) * LANCIR_PI;
                *op = cast(T) ( f.generate() * fw.generate() / ( ut * ut ));
                op++;
                t++;
            }

            double ut = t + FracDelay;

            if( fast_fabs( ut ) <= 1e-13 )
            {
                *op = cast(T) NormFreq;
                f.generate();
                fw.generate();
            }
            else
            {
                ut *= LANCIR_PI;
                *op = cast(T) ( f.generate() * fw.generate() / ( ut * ut ));
            }

            mt = fl2 - 2;

            while( t < mt )
            {
                op++;
                t++;
                ut = ( t + FracDelay ) * LANCIR_PI;
                *op = cast(T) ( f.generate() * fw.generate() / ( ut * ut ));
            }

            op++;
            t++;
            ut = t + FracDelay;

            if( ut > Len2 )
            {
                *op = cast(T) 0.0;
            }
            else
            {
                ut *= LANCIR_PI;
                *op = cast(T) ( f.generate() * fw.generate() / ( ut * ut ));
            }
        }

        /**
         * Function normalizes the specified filter so that it has unity gain
         * at DC.
         *
         * @param p Filter buffer pointer.
         * @tparam T Filter buffer type.
         */

        void normalizeFilter(T)( T* p ) const
        {
            double s = 0.0;
            int i;

            for( i = 0; i < KernelLen; i++ )
            {
                s += p[ i ];
            }

            s = 1.0 / s;

            for( i = 0; i < KernelLen; i++ )
            {
                p[ i ] = cast(T) ( p[ i ] * s );
            }
        }
    }

    /**
     * Structure defines source scanline positioning and filters for each
     * destination pixel.
     */

    static struct CResizePos
    {
        const(float)* ip; // Source image pixel pointer.
        float* flt; // Fractional delay filter.
    }

    /**
     * Class contains resizing positioning and a temporary scanline buffer,
     * prepares source scanline positions for resize filtering.
     */

    static struct CResizeScanline
    {
    public:
    nothrow:
    @nogc:
        int padl; // Left-padding (in pixels) required for source scanline.
            // Available after the update() function call.
            //
        int padr; // Right-padding (in pixels) required for source scanline.
            // Available after the update() function call.
            //
        Vec!float sp; // Source scanline buffer, with "padl" and "padr"
            // padding.
            //
        Vec!CResizePos pos; // Source scanline pointers (point to "sp")
            // and filters for each destination pixel position. Available
            // after the update() function call.
            //

        /**
         * Function "resets" *this object so that the next update() call fully
         * updates the position buffer. Reset is necessary if the filter
         * object was updated.
         */

        void reset()
        {
            PrevSrcLen = -1;
        }

        /**
         * Function updates resizing positions, updates "padl", "padr" and
         * "pos" buffer.
         *
         * @param k Resizing step.
         * @param o0 Initial source image offset.
         * @param SrcLen Source image scanline length, used to create a
         * scanline buffer without length pre-calculation.
         * @param DstLen Destination image scanline length.
         * @param rf Resizing filters object.
         */

        void update( const double k, const double o0, const int ElCount,
            const int SrcLen, const int DstLen, ref CResizeFilters rf )
        {
            if( SrcLen == PrevSrcLen && DstLen == PrevDstLen &&
                k == Prevk && o0 == Prevo && ElCount == PrevElCount )
            {
                return;
            }

            PrevSrcLen = SrcLen;
            PrevDstLen = DstLen;
            Prevk = k;
            Prevo = o0;
            PrevElCount = ElCount;

            const int fl2m1 = rf.fl2 - 1;
            padl = fl2m1 - cast(int) fast_floor( o0 );

            if( padl < 0 )
            {
                padl = 0;
            }

            padr = cast(int) fast_floor( o0 + k * ( DstLen - 1 )) + rf.fl2 + 1 - SrcLen;

            if( padr < 0 )
            {
                padr = 0;
            }

            const int splennew = ( padl + SrcLen + padr ) * ElCount;

            sp.resize(splennew);
            pos.resize(DstLen);

            const(float*) spo = sp.ptr + ( padl - fl2m1 ) * ElCount;
            int i;

            for( i = 0; i < DstLen; i++ )
            {
                const double o = o0 + k * i;
                const int ix = cast(int) fast_floor( o );
                pos[ i ].ip = spo + ix * ElCount;
                pos[ i ].flt = rf.getFilter( o - ix );
            }
            const(float)* pos0 = pos[ 0 ].ip;
            const(float)* pos1 = pos[ 1 ].ip;
            const(float)* pos2 = pos[ 2 ].ip;
        }

    protected:

        int PrevSrcLen = -1; // Previous SrcLen.
        int PrevDstLen = -1; // Previous DstLen.
        double Prevk = 0.0; // Previous "k".
        double Prevo = 0.0; // Previous "o".
        int PrevElCount = 0; // Previous pixel element count.
    }

    CResizeFilters rfh; // Resizing filters for horizontal resizing.
    CResizeFilters rfv0; // Resizing filters for vertical resizing (may not be in use).
    CResizeScanline rsh; // Horizontal resize scanline.
    CResizeScanline rsv; // Vertical resize scanline.

    /**
     * Function copies scanline from the source buffer in its native format
     * to internal scanline buffer, in preparation for horizontal resizing.
     * Variants for 1-4-channel images.
     *
     * @param ip Source scanline buffer.
     * @param rs Scanline resizing positions object.
     * @param l Source scanline length, in pixels.
     * @param ipinc "ip" increment per pixel.
     */

    static void copyScanline1h(T)( const(T)* ip, ref CResizeScanline rs, const int l )
    {
        float* op = rs.sp.ptr;
        int i;

        for( i = 0; i < rs.padl; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op++;
        }

        for( i = 0; i < l - 1; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            ip++;
            op++;
        }

        for( i = 0; i <= rs.padr; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op++;
        }
    }

    static void copyScanline2h(T)( const(T)* ip, ref CResizeScanline rs, const int l )
    {
        float* op = rs.sp.ptr;
        int i;

        for( i = 0; i < rs.padl; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op += 2;
        }

        for( i = 0; i < l - 1; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            ip += 2;
            op += 2;
        }

        for( i = 0; i <= rs.padr; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op += 2;
        }
    }

    static void copyScanline3h(T)( const(T)* ip, ref CResizeScanline rs, const int l )
    {
        float* op = rs.sp.ptr;
        int i;

        for( i = 0; i < rs.padl; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            op += 3;
        }

        for( i = 0; i < l - 1; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            ip += 3;
            op += 3;
        }

        for( i = 0; i <= rs.padr; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            op += 3;
        }
    }

    static void copyScanline4h(T)( const(T)* ip, ref CResizeScanline rs, const int l )
    {
        float* op = rs.sp.ptr;
        int i;

        for( i = 0; i < rs.padl; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            op[ 3 ] = ip[ 3 ];
            op += 4;
        }

        for( i = 0; i < l - 1; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            op[ 3 ] = ip[ 3 ];
            ip += 4;
            op += 4;
        }

        for( i = 0; i <= rs.padr; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            op[ 3 ] = ip[ 3 ];
            op += 4;
        }
    }

    /**
     * Function copies scanline from the source buffer in its native format
     * to internal scanline buffer, in preparation for vertical resizing.
     * Variants for 1-4-channel images.
     *
     * @param ip Source scanline buffer.
     * @param rs Scanline resizing positions object.
     * @param l Source scanline length, in pixels.
     * @param ipinc "ip" increment per pixel.
     */

    static void copyScanline1v(T)( const(T)* ip, ref CResizeScanline rs, const int l,
        const int ipinc )
    {
        float* op = rs.sp.ptr;
        int i;

        for( i = 0; i < rs.padl; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op++;
        }

        for( i = 0; i < l - 1; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            ip += ipinc;
            op++;
        }

        for( i = 0; i <= rs.padr; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op++;
        }
    }

    static void copyScanline4v(T)( const(T)* ip, ref CResizeScanline rs, const int l,
        const int ipinc )
    {
        float* op = rs.sp.ptr;
        int i;

        for( i = 0; i < rs.padl; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            op[ 3 ] = ip[ 3 ];
            op += 4;
        }

        for( i = 0; i < l - 1; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            op[ 3 ] = ip[ 3 ];
            ip += ipinc;
            op += 4;
        }

        for( i = 0; i <= rs.padr; i++ )
        {
            op[ 0 ] = ip[ 0 ];
            op[ 1 ] = ip[ 1 ];
            op[ 2 ] = ip[ 2 ];
            op[ 3 ] = ip[ 3 ];
            op += 4;
        }
    }


    /**
     * Function performs internal scanline resizing. Variants for 1-4-channel
     * images.
     *
     * @param op Destination buffer.
     * @param DstLen Destination length, in pixels.
     * @param rp Resizing positions and filters.
     * @param kl Filter kernel length, in taps.
     */

    static void resize1( float* op, int DstLen, CResizePos* rp, const int kl )
    {
        if( kl == 6 )
        {
            CResizePos* rpe = rp + DstLen;
            while( rp < rpe )
            {
                const float* ip = rp.ip;
                const float* flt = rp.flt;

                op[ 0 ] =
                    flt[ 0 ] * ip[ 0 ] +
                    flt[ 1 ] * ip[ 1 ] +
                    flt[ 2 ] * ip[ 2 ] +
                    flt[ 3 ] * ip[ 3 ] +
                    flt[ 4 ] * ip[ 4 ] +
                    flt[ 5 ] * ip[ 5 ];

                op++;
                rp++;
            }
        }
        else
        {
            CResizePos* rpe = rp + DstLen;
            while( rp < rpe )
            {
                const float* ip = rp.ip;
                const float* flt = rp.flt;
                float sum = 0.0;
                int i;

                for( i = 0; i < kl; i++ )
                {
                    sum += flt[ i ] * ip[ i ];
                }

                op[ 0 ] = sum;
                op++;
                rp++;
            }
        }
    }



    static void resize4( float* op, int DstLen, CResizePos* rp, const int kl )
    {
        CResizePos* rpe = rp + DstLen;
        while( rp < rpe )
        {
            const(float)* ip = rp.ip;
            const(float)* flt = rp.flt;
            float[ 4 ] sum;
            sum[ 0 ] = 0.0;
            sum[ 1 ] = 0.0;
            sum[ 2 ] = 0.0;
            sum[ 3 ] = 0.0;
            int i;

            for( i = 0; i < kl; i++ )
            {
                const float xx = flt[ i ];
                sum[ 0 ] += xx * ip[ 0 ];
                sum[ 1 ] += xx * ip[ 1 ];
                sum[ 2 ] += xx * ip[ 2 ];
                sum[ 3 ] += xx * ip[ 3 ];
                ip += 4;
            }

            op[ 0 ] = sum[ 0 ];
            op[ 1 ] = sum[ 1 ];
            op[ 2 ] = sum[ 2 ];
            op[ 3 ] = sum[ 3 ];
            op += 4;
            rp++;
        }
    }
}

private struct CSinGen
{
public:
nothrow:
@nogc:

    ///
    /// Initialize a sine generator.
    ///
    /// Params:
    ///     si Sine function increment, in radians.
    ///     ph Starting phase, in radians. Add 0.5 * LANCIR_PI for cosine function.
    ///     g Gain value.
    ///
    this (double si, double ph, double g = 1.0)
    {
        svalue1 = fast_sin( ph ) * g;
        svalue2 = fast_sin( ph - si ) * g;
        sincr = 2.0 * fast_cos( si );
    }

    /// Returns:
    ///     The next value of the sine function, without biasing.
    double generate()
    {
        double res = svalue1;
        svalue1 = sincr * res - svalue2;
        svalue2 = res;
        return res;
    }

private:
    double svalue1; // Current sine value.
    double svalue2; // Previous sine value.
    double sincr;   // Sine value increment.
}
