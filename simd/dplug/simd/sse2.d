module dplug.simd.sse2;

import core.simd;



uint _MM_SHUFFLE(uint z, uint y, uint x, uint w)
{
    return (z<<6) | (y<<4) | (x<<2) | w;
}

// Note: no way to do COMISS intrinsics since no compiler support
// Note: no way to do intrinsics involving MMX registers
// Note: no way to do load instruction, use vector extension assignment instead
// Note: How to do _mm_movemask_ps?
version(D_SIMD)
{
    @safe pure nothrow:

    // Keep those in Intel website order for easier dealing with missing intrinsics

    //
    // SSE1
    //

    float4 _mm_add_ss (float4 a, float4 b)
    {
        return __simd(XMM.ADDSS, a, b);    
    }

    float4 _mm_add_ps (float4 a, float4 b)
    {
        return __simd(XMM.ADDPS, a, b);
    }

    float4 _mm_and_ps(float4 a, float4 b)
    {
        return __simd(XMM.ANDPS, a, b);
    }

    float4 _mm_andnot_ps(float4 a, float4 b)
    {
        return __simd(XMM.ANDNPS, a, b);
    }

    template CMPSSIntrinsics(string suffix, int imm)
    {
        const char[] CMPSSIntrinsics =
            "float4 _mm_cmp" ~ suffix ~ "_ps(float4 a, float4 b)"
            "{"
            "    return __simd(XMM.CMPPS, a, b, " ~ to!string(imm) ~ ");"
            "}"

            "float4 _mm_cmp" ~ suffix ~ "_ss(float4 a, float4 b)"
            "{"
            "    return __simd(XMM.CMPSS, a, b, " ~ to!string(imm) ~ ");"
            "}";
    }

    mixin(CMPSSIntrinsics!("eq", 0));
    mixin(CMPSSIntrinsics!("lt", 1));
    mixin(CMPSSIntrinsics!("nge", 1));
    mixin(CMPSSIntrinsics!("le", 2));
    mixin(CMPSSIntrinsics!("ngt", 2));
    mixin(CMPSSIntrinsics!("unord", 3));
    mixin(CMPSSIntrinsics!("neq", 4));
    mixin(CMPSSIntrinsics!("ge", 5));
    mixin(CMPSSIntrinsics!("nlt", 5));
    mixin(CMPSSIntrinsics!("gt", 6));
    mixin(CMPSSIntrinsics!("nle", 6));
    mixin(CMPSSIntrinsics!("ord", 7));


    float4 _mm_div_ps(float4 a, float4 b)
    {
        return __simd(XMM.DIVPS, a, b);
    }

    float4 _mm_div_ss(float4 a, float4 b)
    {
        return __simd(XMM.DIVSS, a, b);
    }

    float4 _mm_load_ps(const float* mem_addr)
    {
        // TODO: should be slow, find a way to use movaps
        return _mm_set1_ps(mem_addr[3], mem_addr[2], mem_addr[1], mem_addr[0]);
    }

    float4 _mm_load_ps1(const float* mem_addr)
    {
        return _mm_set1_ps(*mem_addr);
    }

    float4 _mm_load_ss(const float* mem_addr)
    {
        return _mm_set_ss(*mem_addr);
    }

    alias _mm_load1_ps = _mm_load_ps1;

    float4 _mm_loadr_ps(const float* mem_addr)
    {
        // TODO: should be slow, find a way to use movaps
        return _mm_set1_ps(mem_addr[0], mem_addr[1], mem_addr[2], mem_addr[3]);
    }

    float4 _mm_loadu_ps(const float* mem_addr)
    {
        // TODO: should be slow, find a way to use movups
        return _mm_set1_ps(mem_addr[3], mem_addr[2], mem_addr[1], mem_addr[0]);
    }


    float4 _mm_max_ps(float4 a, float4 b)
    {
        return __simd(XMM.MAXPS, a, b);
    }

    float4 _mm_max_ss(float4 a, float4 b)
    {
        return __simd(XMM.MAXSS, a, b);
    }

    float4 _mm_min_ps(float4 a, float4 b)
    {
        return __simd(XMM.MINPS, a, b);
    }

    float4 _mm_min_ss(float4 a, float4 b)
    {
        return __simd(XMM.MINSS, a, b);
    }

    float4 _mm_move_ss(float4 a, float4 b)
    {
        return __simd(XMM.MOVSS, a, b);
    }

    float4 _mm_movehl_ps(float4 a, float4 b)
    {
        return __simd(XMM.MOVHLPS, a, b);
    }

    float4 _mm_movelh_ps(float4 a, float4 b)
    {
        return __simd(XMM.MOVLHPS, a, b);
    }

    float4 _mm_mul_ps(float4 a, float4 b)
    {
        return __simd(XMM.MULPS, a, b);
    }

    float4 _mm_mul_ss(float4 a, float4 b)
    {
        return __simd(XMM.MULSS, a, b);
    }

    float4 _mm_or_ps(float4 a, float4 b)
    {
        return __simd(XMM.ORPS, a, b);
    }

    float4 _mm_rcp_ps(float4 a)
    {
        return __simd(XMM.RCPPS, a);
    }

    float4 _mm_rcp_ss(float4 a)
    {
        return __simd(XMM.RCPSS, a);
    }

    float4 _mm_rsqrt_ps(float4 a)
    {
        return __simd(XMM.RSQRTPS, a);
    }

    float4 _mm_rsqrt_ss(float4 a)
    {
        return __simd(XMM.RSQRTSS, a);
    }

    float4 _mm_set_ps(float e3, float e2, float e1, float e0)
    {
        float4 res;
        res.array[0] = e0;
        res.array[1] = e1;
        res.array[2] = e2;
        res.array[3] = e3;
        return res;
    }

    float4 _mm_set_ps1(float a)
    {
        return _mm_set_ps(a, a, a, a);
    }

    alias _mm_set1_ps = _mm_set_ps1;

    float4 _mm_set_ss(float a)
    {
        return _mm_set_ps(a, 0.0f, 0.0f, 0.0f);
    }

    float4 _mm_setr_ps(float e0, float e1, float e2, float e3)
    {
        return _mm_set_ps(e3, e2, e1, e0);
    }

    float4 _mm_setzero_ps()
    {
        float4 r = void;
        return _mm_xor_ps(r, r);
    }

    float4 _mm_shuffle_ps(float4 a, float4 b, uint imm)
    {
        return __simd(XMM.SHUFPS, a, b, imm);
    }

    float4 _mm_sqrt_ps(float4 a)
    {
        return __simd(XMM.SQRTPS, a);
    }

    float4 _mm_sqrt_ss(float4 a)
    {
        return __simd(XMM.SQRTSS, a);
    }

    float4 _mm_sub_ps(float4 a, float4 b)
    {
        return __simd(XMM.SUBPS, a, b);
    }

    float4 _mm_sub_ss(float4 a, float4 b)
    {
        return __simd(XMM.SUBSS, a, b);
    }

    float4 _mm_unpackhi_ps(float4 a, float4 b)
    {
        return __simd(XMM.UNPCKHPS, a, b);
    }

    float4 _mm_unpacklo_ps(float4 a, float4 b)
    {
        return __simd(XMM.UNPCKLPS, a, b);
    }

    float4 _mm_xor_ps(float4 a, float4 b)
    {
        return __simd(XMM.XORPS, a, b);
    }

    //
    // SSE2
    //

    short8 _mm_add_epi16(short8 a, short8 b)
    {
        return __simd(XMM.PADDW, a, b);
    }

    int4 _mm_add_epi32(int4 a, int4 b)
    {
        return __simd(XMM.PADDD, a, b);
    }

    long2 _mm_add_epi64(long2 a, long2 b)
    {
        return __simd(XMM.PADDQ, a, b);
    }

    byte16 _mm_add_epi8(byte16 a, byte16 b)
    {
        return __simd(XMM.PADDB, a, b);
    }



}
