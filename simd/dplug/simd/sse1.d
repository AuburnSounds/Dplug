module dplug.simd.sse1;

import core.simd;


version(D_SIMD)
{


pure:

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


/+
comiss
int _mm_comieq_ss (__m128 a, __m128 b)
comiss
int _mm_comige_ss (__m128 a, __m128 b)
comiss
int _mm_comigt_ss (__m128 a, __m128 b)
comiss
int _mm_comile_ss (__m128 a, __m128 b)
comiss
int _mm_comilt_ss (__m128 a, __m128 b)
comiss
int _mm_comineq_ss (__m128 a, __m128 b)
cvtpi2ps
__m128 _mm_cvt_pi2ps (__m128 a, __m64 b)
cvtps2pi
__m64 _mm_cvt_ps2pi (__m128 a)
cvtsi2ss
__m128 _mm_cvt_si2ss (__m128 a, int b)
cvtss2si
int _mm_cvt_ss2si (__m128 a)
...
__m128 _mm_cvtpi16_ps (__m64 a)
cvtpi2ps
__m128 _mm_cvtpi32_ps (__m128 a, __m64 b)
...
__m128 _mm_cvtpi32x2_ps (__m64 a, __m64 b)
...
__m128 _mm_cvtpi8_ps (__m64 a)
...
__m64 _mm_cvtps_pi16 (__m128 a)
cvtps2pi
__m64 _mm_cvtps_pi32 (__m128 a)
...
__m64 _mm_cvtps_pi8 (__m128 a)
...
__m128 _mm_cvtpu16_ps (__m64 a)
...
__m128 _mm_cvtpu8_ps (__m64 a)
cvtsi2ss
__m128 _mm_cvtsi32_ss (__m128 a, int b)
cvtsi2ss
__m128 _mm_cvtsi64_ss (__m128 a, __int64 b)
movss
float _mm_cvtss_f32 (__m128 a)
cvtss2si
int _mm_cvtss_si32 (__m128 a)
cvtss2si
__int64 _mm_cvtss_si64 (__m128 a)
cvttps2pi
__m64 _mm_cvtt_ps2pi (__m128 a)
cvttss2si
int _mm_cvtt_ss2si (__m128 a)
cvttps2pi
__m64 _mm_cvttps_pi32 (__m128 a)
cvttss2si
int _mm_cvttss_si32 (__m128 a)
cvttss2si
__int64 _mm_cvttss_si64 (__m128 a)
divps
__m128 _mm_div_ps (__m128 a, __m128 b)
divss
__m128 _mm_div_ss (__m128 a, __m128 b)
pextrw
int _mm_extract_pi16 (__m64 a, int imm)
unsigned int _MM_GET_EXCEPTION_MASK ()
unsigned int _MM_GET_EXCEPTION_STATE ()
unsigned int _MM_GET_FLUSH_ZERO_MODE ()
unsigned int _MM_GET_ROUNDING_MODE ()
stmxcsr
unsigned int _mm_getcsr (void)
pinsrw
__m64 _mm_insert_pi16 (__m64 a, int i, int imm)
movaps
__m128 _mm_load_ps (float const* mem_addr)
...
__m128 _mm_load_ps1 (float const* mem_addr)
movss
__m128 _mm_load_ss (float const* mem_addr)
...
__m128 _mm_load1_ps (float const* mem_addr)
movhps
__m128 _mm_loadh_pi (__m128 a, __m64 const* mem_addr)
movlps
__m128 _mm_loadl_pi (__m128 a, __m64 const* mem_addr)
...
__m128 _mm_loadr_ps (float const* mem_addr)
movups
__m128 _mm_loadu_ps (float const* mem_addr)
maskmovq
void _mm_maskmove_si64 (__m64 a, __m64 mask, char* mem_addr)
maskmovq
void _m_maskmovq (__m64 a, __m64 mask, char* mem_addr)
pmaxsw
__m64 _mm_max_pi16 (__m64 a, __m64 b)
maxps
__m128 _mm_max_ps (__m128 a, __m128 b)
pmaxub
__m64 _mm_max_pu8 (__m64 a, __m64 b)
maxss
__m128 _mm_max_ss (__m128 a, __m128 b)
pminsw
__m64 _mm_min_pi16 (__m64 a, __m64 b)
minps
__m128 _mm_min_ps (__m128 a, __m128 b)
pminub
__m64 _mm_min_pu8 (__m64 a, __m64 b)
minss
__m128 _mm_min_ss (__m128 a, __m128 b)
movss
__m128 _mm_move_ss (__m128 a, __m128 b)
movhlps
__m128 _mm_movehl_ps (__m128 a, __m128 b)
movlhps
__m128 _mm_movelh_ps (__m128 a, __m128 b)
pmovmskb
int _mm_movemask_pi8 (__m64 a)
movmskps
int _mm_movemask_ps (__m128 a)
mulps
__m128 _mm_mul_ps (__m128 a, __m128 b)
mulss
__m128 _mm_mul_ss (__m128 a, __m128 b)
pmulhuw
__m64 _mm_mulhi_pu16 (__m64 a, __m64 b)
orps
__m128 _mm_or_ps (__m128 a, __m128 b)
pavgb
__m64 _m_pavgb (__m64 a, __m64 b)
pavgw
__m64 _m_pavgw (__m64 a, __m64 b)
pextrw
int _m_pextrw (__m64 a, int imm)
pinsrw
__m64 _m_pinsrw (__m64 a, int i, int imm)
pmaxsw
__m64 _m_pmaxsw (__m64 a, __m64 b)
pmaxub
__m64 _m_pmaxub (__m64 a, __m64 b)
pminsw
__m64 _m_pminsw (__m64 a, __m64 b)
pminub
__m64 _m_pminub (__m64 a, __m64 b)
pmovmskb
int _m_pmovmskb (__m64 a)
pmulhuw
__m64 _m_pmulhuw (__m64 a, __m64 b)
prefetchnta, prefetcht0, prefetcht1, prefetcht2
void _mm_prefetch (char const* p, int i)
psadbw
__m64 _m_psadbw (__m64 a, __m64 b)
pshufw
__m64 _m_pshufw (__m64 a, int imm)
rcpps
__m128 _mm_rcp_ps (__m128 a)
rcpss
__m128 _mm_rcp_ss (__m128 a)
rsqrtps
__m128 _mm_rsqrt_ps (__m128 a)
rsqrtss
__m128 _mm_rsqrt_ss (__m128 a)
psadbw
__m64 _mm_sad_pu8 (__m64 a, __m64 b)
void _MM_SET_EXCEPTION_MASK (unsigned int a)
void _MM_SET_EXCEPTION_STATE (unsigned int a)
void _MM_SET_FLUSH_ZERO_MODE (unsigned int a)
...
__m128 _mm_set_ps (float e3, float e2, float e1, float e0)
...
__m128 _mm_set_ps1 (float a)
void _MM_SET_ROUNDING_MODE (unsigned int a)
...
__m128 _mm_set_ss (float a)
...
__m128 _mm_set1_ps (float a)
ldmxcsr
void _mm_setcsr (unsigned int a)
...
__m128 _mm_setr_ps (float e3, float e2, float e1, float e0)
xorps
__m128 _mm_setzero_ps (void)
sfence
void _mm_sfence (void)
pshufw
__m64 _mm_shuffle_pi16 (__m64 a, int imm)
shufps
__m128 _mm_shuffle_ps (__m128 a, __m128 b, unsigned int imm)
sqrtps
__m128 _mm_sqrt_ps (__m128 a)
sqrtss
__m128 _mm_sqrt_ss (__m128 a)
movaps
void _mm_store_ps (float* mem_addr, __m128 a)
...
void _mm_store_ps1 (float* mem_addr, __m128 a)
movss
void _mm_store_ss (float* mem_addr, __m128 a)
...
void _mm_store1_ps (float* mem_addr, __m128 a)
movhps
void _mm_storeh_pi (__m64* mem_addr, __m128 a)
movlps
void _mm_storel_pi (__m64* mem_addr, __m128 a)
...
void _mm_storer_ps (float* mem_addr, __m128 a)
movups
void _mm_storeu_ps (float* mem_addr, __m128 a)
movntq
void _mm_stream_pi (__m64* mem_addr, __m64 a)
movntps
void _mm_stream_ps (float* mem_addr, __m128 a)
subps
__m128 _mm_sub_ps (__m128 a, __m128 b)
subss
__m128 _mm_sub_ss (__m128 a, __m128 b)
...
_MM_TRANSPOSE4_PS (__m128 row0, __m128 row1, __m128 row2, __m128 row3)
ucomiss
int _mm_ucomieq_ss (__m128 a, __m128 b)
ucomiss
int _mm_ucomige_ss (__m128 a, __m128 b)
ucomiss
int _mm_ucomigt_ss (__m128 a, __m128 b)
ucomiss
int _mm_ucomile_ss (__m128 a, __m128 b)
ucomiss
int _mm_ucomilt_ss (__m128 a, __m128 b)
ucomiss
int _mm_ucomineq_ss (__m128 a, __m128 b)
unpckhps
__m128 _mm_unpackhi_ps (__m128 a, __m128 b)
unpcklps
__m128 _mm_unpacklo_ps (__m128 a, __m128 b)
xorps
__m128 _mm_xor_ps (__m128 a, __m128 b)

+/

}