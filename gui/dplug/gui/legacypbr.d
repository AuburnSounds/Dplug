/**
* Original fixed-function PBR rendering in Dplug.
* For compatibility purpose.
*
* Copyright: Copyright Auburn Sounds 2015-2019.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module dplug.gui.legacypbr;



import std.math;

import dplug.math.vector;
import dplug.math.box;
import dplug.math.matrix;

import dplug.core.vec;
import dplug.core.nogc;
import dplug.core.math;
import dplug.core.thread;

import dplug.gui.compositor;

import dplug.graphics;
import dplug.window.window;

import dplug.gui.ransac;

import inteli.math;
import inteli.emmintrin;


/// When inheriging from `MultipassCompositor`, you can define what the passes exchange 
/// between each other. However, the first field has to be a `CompositorPassBuffers`.
struct PBRCompositorPassBuffers
{
    // First field must be `CompositorPassBuffers` for ABI compatibility of `MultipassCompositor`.
    CompositorPassBuffers parent;
    alias parent this;

    // Computed normal, one buffer per thread
    OwnedImage!RGBf[] normalBuffers;

    // Accumulates light for each deferred pass, one buffer per thread
    OwnedImage!RGBAf[] accumBuffers;

    // Approximate of normal variance, one buffer per thread
    OwnedImage!L32f[] varianceBuffers;
}


/// Equivalence factor between Z samples and pixels.
/// Tuned once by hand to match the other normal computation algorithm
/// This affects virutal geometry, and as such: normals and raymarching into depth.
/// Future: this should be modifiable in order to have more Z range in plugins (more 3D).
enum float FACTOR_Z = 4655.0f;

/// Originally, Dplug compositor was fixed function.
/// This is the legacy compositor.
class PBRCompositor : MultipassCompositor
{
nothrow @nogc:


    // <LEGACY> parameters, reproduced here as properties for compatibility.
    // Instead you are supposed to tweak settings when creating the passes.

    void light1Color(vec3f color)
    {
        (cast(PassObliqueShadowLight)getPass(PASS_OBLIQUE_SHADOW)).color = color;        
    }

    void light2Dir(vec3f dir)
    {
        (cast(PassDirectionalLight)getPass(PASS_DIRECTIONAL)).direction = dir;
    }

    void light2Color(vec3f color)
    {
        (cast(PassDirectionalLight)getPass(PASS_DIRECTIONAL)).color = color;        
    }

    void light3Dir(vec3f dir)
    {
        (cast(PassSpecularLight)getPass(PASS_SPECULAR)).direction = dir;
    }

    void light3Color(vec3f color)
    {
        (cast(PassSpecularLight)getPass(PASS_SPECULAR)).color = color;        
    }

    void skyboxAmount(float amount)
    {
        (cast(PassSkyboxReflections)getPass(PASS_SKYBOX)).amount = amount;
    }

    void ambientLight(float amount)
    {
        (cast(PassAmbientOcclusion)getPass(PASS_AO)).amount = amount;
    }

    // </LEGACY>



    private enum // MUST be kept in sync with below passes, it's for legacy purpose
    {
        PASS_NORMAL      = 0,
        PASS_AO          = 1,
        PASS_OBLIQUE_SHADOW = 2,
        PASS_DIRECTIONAL = 3,
        PASS_SPECULAR    = 4,
        PASS_SKYBOX      = 5,
        PASS_EMISSIVE    = 6,
        PASS_CLAMP       = 7
    }

    this(CompositorCreationContext* context)
    {
        super(context);

        _normalBuffers = mallocSlice!(OwnedImage!RGBf)(numThreads());
        _accumBuffers = mallocSlice!(OwnedImage!RGBAf)(numThreads());
        _varianceBuffers = mallocSlice!(OwnedImage!L32f)(numThreads());

        for (int t = 0; t < numThreads(); ++t)
        {
            _normalBuffers[t] = mallocNew!(OwnedImage!RGBf)();
            _accumBuffers[t] = mallocNew!(OwnedImage!RGBAf)();
            _varianceBuffers[t] = mallocNew!(OwnedImage!L32f)();
        }

        // Create the passes
        addPass( mallocNew!PassComputeNormal(this) );         // PASS_NORMAL
        addPass( mallocNew!PassAmbientOcclusion(this) );      // PASS_AO
        addPass( mallocNew!PassObliqueShadowLight(this) );    // PASS_OBLIQUE_SHADOW
        addPass( mallocNew!PassDirectionalLight(this) );      // PASS_DIRECTIONAL
        addPass( mallocNew!PassSpecularLight(this) );         // PASS_SPECULAR
        addPass( mallocNew!PassSkyboxReflections(this) );     // PASS_SKYBOX
        addPass( mallocNew!PassEmissiveContribution(this) );  // PASS_EMISSIVE
        addPass( mallocNew!PassClampAndConvertTo8bit(this) ); // PASS_CLAMP
    }

    ~this()
    {
        for (size_t t = 0; t < _normalBuffers.length; ++t)
        {
            _normalBuffers[t].destroyFree();
            _accumBuffers[t].destroyFree();
            _varianceBuffers[t].destroyFree();
        }
        freeSlice(_normalBuffers);
        freeSlice(_accumBuffers);
        freeSlice(_varianceBuffers);
    }

    override void resizeBuffers(int width, 
                                int height,
                                int areaMaxWidth,
                                int areaMaxHeight)
    {
        super.resizeBuffers(width, height, areaMaxWidth, areaMaxHeight);

        // Create numThreads thread-local buffers of areaMaxWidth x areaMaxHeight size.
        for (int t = 0; t < numThreads(); ++t)
        {

            int border_0 = 0;
            int rowAlign_1 = 1;
            int rowAlign_16 = 16;
            _normalBuffers[t].size(areaMaxWidth, areaMaxHeight, border_0, rowAlign_1);
            _accumBuffers[t].size(areaMaxWidth, areaMaxHeight, border_0, rowAlign_16);
            _varianceBuffers[t].size(areaMaxWidth, areaMaxHeight, border_0, rowAlign_1);
        }
    }


    override void compositeTile(ImageRef!RGBA wfb, 
                                const(box2i)[] areas,
                                Mipmap!RGBA diffuseMap,
                                Mipmap!RGBA materialMap,
                                Mipmap!L16 depthMap)
    {
        // Call each pass in sequence
        PBRCompositorPassBuffers buffers;
        buffers.outputBuf = &wfb;
        buffers.diffuseMap = diffuseMap;
        buffers.materialMap = materialMap;
        buffers.depthMap = depthMap;
        buffers.accumBuffers = _accumBuffers;
        buffers.normalBuffers = _normalBuffers;
        buffers.varianceBuffers = _varianceBuffers;

        // For each tile, do all pass one by one.
        void compositeOneTile(int i, int threadIndex) nothrow @nogc
        {
            OwnedImage!RGBAf accumBuffer = _accumBuffers[threadIndex];

            box2i area = areas[i];
            // Clear the accumulation buffer, since all passes add to it
            {
                RGBAf zero = RGBAf(0.0f, 0.0f, 0.0f, 0.0f);
                for (int j = 0; j < area.height; ++j)
                {
                    RGBAf* accumScan = accumBuffer.scanline(j).ptr;
                    accumScan[0..area.width] = zero;
                }
            }

            foreach(pass; passes())
            {
                pass.renderIfActive(threadIndex, area, cast(CompositorPassBuffers*)&buffers);
            }
        }
        int numAreas = cast(int)areas.length;
        threadPool().parallelFor(numAreas, &compositeOneTile);
    }

private:
    OwnedImage!RGBf[] _normalBuffers; // store computed normals
    OwnedImage!RGBAf[] _accumBuffers; // store accumulated color
    OwnedImage!L32f[] _varianceBuffers; // store computed normal variance, useful for anti-aliasing
}

// Compute normals from depth, and normal variance.
class PassComputeNormal : CompositorPass
{
nothrow:
@nogc:

    this(MultipassCompositor parent)
    {
        super(parent);
    }

    override void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        PBRCompositorPassBuffers* PBRbuf = cast(PBRCompositorPassBuffers*) buffers;
        OwnedImage!RGBf normalBuffer = PBRbuf.normalBuffers[threadIndex];
        OwnedImage!L16 depthLevel0 = PBRbuf.depthMap.levels[0];
        OwnedImage!L32f varianceBuffer = PBRbuf.varianceBuffers[threadIndex];

        const int depthPitchBytes = depthLevel0.pitchInBytes();

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBf* normalScan = normalBuffer.scanline(j - area.min.y).ptr;
            L32f* varianceScan = varianceBuffer.scanline(j - area.min.y).ptr;

            // Note: because the level 0 of depth map has a border of 1 and a trailingSamples of 2,
            //       then we are allowed to read 4 depth samples at once.
            const(L16)* depthScan   = depthLevel0.scanlinePtr(j);

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                // Compute normal
                {
                    const(L16)* depthHere = depthScan + i;
                    const(L16)* depthHereM1 = cast(const(L16)*) ( cast(const(ubyte)*)depthHere - depthPitchBytes );
                    const(L16)* depthHereP1 = cast(const(L16)*) ( cast(const(ubyte)*)depthHere + depthPitchBytes );
                    enum float multUshort = 1.0 / FACTOR_Z;
                    float[9] depthNeighbourhood = void;
                    depthNeighbourhood[0] = depthHereM1[-1].l * multUshort;
                    depthNeighbourhood[1] = depthHereM1[ 0].l * multUshort;
                    depthNeighbourhood[2] = depthHereM1[+1].l * multUshort;
                    depthNeighbourhood[3] = depthHere[-1].l   * multUshort;
                    depthNeighbourhood[4] = depthHere[ 0].l   * multUshort;
                    depthNeighbourhood[5] = depthHere[+1].l   * multUshort;
                    depthNeighbourhood[6] = depthHereP1[-1].l * multUshort;
                    depthNeighbourhood[7] = depthHereP1[ 0].l * multUshort;
                    depthNeighbourhood[8] = depthHereP1[+1].l * multUshort;
                    vec3f normal = computePlaneFittingNormal(depthNeighbourhood.ptr);
                    normalScan[i - area.min.x] = RGBf(normal.x, normal.y, normal.z);
                }

                // Compute normal variance (old method)
                // PERF: somehow merge the computations
                // TODO: somehow get the variance from plane squared error
                {
                    const(ubyte)* depthHere = cast(const(ubyte)*)(depthScan + i);

                    // Read 12 depth samples, the rightmost are unused
                    __m128i depthSamplesM1 = _mm_loadl_epi64( cast(const(__m128i)*)(depthHere - depthPitchBytes - 2) );
                    __m128i depthSamplesP0 = _mm_loadl_epi64( cast(const(__m128i)*)(depthHere - 2) );
                    __m128i depthSamplesP1 = _mm_loadl_epi64( cast(const(__m128i)*)(depthHere + depthPitchBytes - 2) );

                    // Extend to float
                    __m128i zero = _mm_setzero_si128();
                    __m128 depthM1 = _mm_cvtepi32_ps(_mm_unpacklo_epi16(depthSamplesM1, zero));
                    __m128 depthP0 = _mm_cvtepi32_ps(_mm_unpacklo_epi16(depthSamplesP0, zero));
                    __m128 depthP1 = _mm_cvtepi32_ps(_mm_unpacklo_epi16(depthSamplesP1, zero));

                    // 2nd-order-derivative for depth in the X direction
                    //  1 -2  1
                    //  1 -2  1
                    //  1 -2  1
                    const(__m128) fact_DDX_M1 = _mm_setr_ps( 1.0f, -2.0f,  1.0f, 0.0f);   
                    __m128 mulForDDX = fact_DDX_M1 * (depthM1 + depthP0 + depthP1);
                    float depthDX = mulForDDX.array[0] + mulForDDX.array[1] + mulForDDX.array[2];

                    // 2nd-order-derivative for depth in the Y direction
                    //  1  1  1
                    // -2 -2 -2
                    //  1  1  1
                    const(__m128) fact_DDY_M1 = _mm_setr_ps( 1.0f,  1.0f,  1.0f, 0.0f);
                    const(__m128) fact_DDY_P0 = _mm_setr_ps(-2.0f, -2.0f, -2.0f, 0.0f);
                    __m128 mulForDDY = fact_DDY_M1 * (depthM1 + depthP1) + depthP0 * fact_DDY_P0;
                    float depthDY = mulForDDY.array[0] + mulForDDY.array[1] + mulForDDY.array[2];

                    depthDX *= (1 / 256.0f);
                    depthDY *= (1 / 256.0f);
                    float variance = (depthDX * depthDX + depthDY * depthDY);
                    varianceScan[i - area.min.x] = L32f(variance);
                }
            }
        }
    }
}


/// Give light depending on whether the pixels are statistically above their neighbours.
class PassAmbientOcclusion : CompositorPass
{
nothrow:
@nogc:

    float amount = 0.08125f;

    // TODO: add ambient light color

    this(MultipassCompositor parent)
    {
        super(parent);
    }

    override void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        PBRCompositorPassBuffers* PBRbuf = cast(PBRCompositorPassBuffers*) buffers;
        OwnedImage!RGBA diffuseLevel0 = PBRbuf.diffuseMap.levels[0];
        Mipmap!L16 depthMap = PBRbuf.depthMap;
        OwnedImage!L16 depthLevel0 = PBRbuf.depthMap.levels[0];
        OwnedImage!RGBAf accumBuffer = PBRbuf.accumBuffers[threadIndex];

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* diffuseScan = diffuseLevel0.scanlinePtr(j);
            const(L16*) depthScan = depthLevel0.scanlinePtr(j);
            RGBAf* accumScan = accumBuffer.scanlinePtr(j - area.min.y);

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                __m128 baseColor = convertBaseColorToFloat4(diffuseScan[i]);

                const(L16)* depthHere = depthScan + i;

                float px = i + 0.5f;
                float py = j + 0.5f;

                float avgDepthHere =
                    ( depthMap.linearSample(1, px, py)
                        + depthMap.linearSample(2, px, py)
                        + depthMap.linearSample(3, px, py)
                        + depthMap.linearSample(4, px, py) ) * 0.25f;

                float diff = (*depthHere).l - avgDepthHere;

                enum float divider23040 = 1.0f / 23040;
                float cavity = (diff + 23040.0f) * divider23040;
                if (cavity >= 1)
                    cavity = 1;
                else if (cavity < 0)
                    cavity = 0;

                __m128 color = baseColor * _mm_set1_ps(cavity * amount);
                _mm_store_ps(cast(float*)(&accumScan[i - area.min.x]), _mm_load_ps(cast(float*)(&accumScan[i - area.min.x])) + color);
            }
        }
    }
}

class PassObliqueShadowLight : CompositorPass
{
nothrow:
@nogc:

    /// Color of this light pass.
    vec3f color = vec3f(0.25f, 0.25f, 0.25f) * 1.3f;

    this(MultipassCompositor parent)
    {
        super(parent);
    }

    override void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        PBRCompositorPassBuffers* PBRbuf = cast(PBRCompositorPassBuffers*) buffers;
        OwnedImage!L16 depthLevel0 = PBRbuf.depthMap.levels[0];
        OwnedImage!RGBA diffuseLevel0 = PBRbuf.diffuseMap.levels[0];
        OwnedImage!RGBAf accumBuffer = PBRbuf.accumBuffers[threadIndex];

        // Add a primary light that cast shadows
        
        enum float fallOff = 0.78f;

        int samples = 11;

        static immutable float[11] weights =
        [
            1.0f,
            fallOff,
            fallOff ^^ 2,
            fallOff ^^ 3,
            fallOff ^^ 4,
            fallOff ^^ 5,
            fallOff ^^ 6,
            fallOff ^^ 7,
            fallOff ^^ 8,
            fallOff ^^ 9,
            fallOff ^^ 10
        ];

        enum float totalWeights = (1.0f - (fallOff ^^ 11)) / (1.0f - fallOff) - 1;
        enum float invTotalWeights = 1 / (1.7f * totalWeights);

        int wholeWidth = depthLevel0.w;
        int wholeHeight = depthLevel0.h;

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* diffuseScan = diffuseLevel0.scanlinePtr(j);

            const(L16*) depthScan = depthLevel0.scanlinePtr(j);
            RGBAf* accumScan = accumBuffer.scanlinePtr(j - area.min.y);

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                const(L16)* depthHere = depthScan + i;
                RGBA ibaseColor = diffuseScan[i];
                vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;

                float lightPassed = 0.0f;

                int depthCenter = (*depthHere).l;
                for (int sample = 1; sample < samples; ++sample)
                {
                    int x1 = i + sample;
                    if (x1 >= wholeWidth)
                        x1 = wholeWidth - 1;
                    int x2 = i - sample;
                    if (x2 < 0)
                        x2 = 0;
                    int y = j - sample;
                    if (y < 0)
                        y = 0;
                    int z = depthCenter + sample; // ???
                    L16* scan = depthLevel0.scanlinePtr(y);
                    int diff1 = z - scan[x1].l; // FUTURE: use pointer offsets here instead of opIndex
                    int diff2 = z - scan[x2].l;

                    float contrib1 = void, 
                        contrib2 = void;

                    static immutable float divider15360 = 1.0f / 15360;

                    if (diff1 >= 0)
                        contrib1 = 1;
                    else if (diff1 < -15360)
                        contrib1 = 0;
                    else
                        contrib1 = (diff1 + 15360) * divider15360;

                    if (diff2 >= 0)
                        contrib2 = 1;
                    else if (diff2 < -15360)
                        contrib2 = 0;
                    else
                        contrib2 = (diff2 + 15360) * divider15360;

                    lightPassed += (contrib1 + contrib2 * 0.7f) * weights[sample];
                }
                vec3f finalColor = baseColor * color * (lightPassed * invTotalWeights);
                __m128 mmColor = _mm_setr_ps(finalColor.r, finalColor.g, finalColor.b, 0.0f);
                _mm_store_ps(cast(float*)(&accumScan[i - area.min.x]), _mm_load_ps(cast(float*)(&accumScan[i - area.min.x])) + mmColor);
            }
        }
    }
}

class PassDirectionalLight : CompositorPass
{
nothrow:
@nogc:
public:

    /// World-space direction. Unsure of the particular space it lives in.
    vec3f direction = vec3f(0.0f, 1.0f, 0.1f).normalized;

    /// Color of this light pass.
    vec3f color = vec3f(0.481f, 0.481f, 0.481f);

    this(MultipassCompositor parent)
    {
        super(parent);
    }

    override void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        PBRCompositorPassBuffers* PBRbuf = cast(PBRCompositorPassBuffers*) buffers;
        OwnedImage!RGBA diffuseLevel0 = PBRbuf.diffuseMap.levels[0];
        OwnedImage!RGBA materialLevel0 = PBRbuf.materialMap.levels[0];
        OwnedImage!RGBf normalBuffer = PBRbuf.normalBuffers[threadIndex];
        OwnedImage!RGBAf accumBuffer = PBRbuf.accumBuffers[threadIndex];

        // secundary light
        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* materialScan = materialLevel0.scanlinePtr(j);
            RGBA* diffuseScan = diffuseLevel0.scanlinePtr(j);
            RGBf* normalScan = normalBuffer.scanlinePtr(j - area.min.y);
            RGBAf* accumScan = accumBuffer.scanlinePtr(j - area.min.y);

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                RGBf normalFromBuf = normalScan[i - area.min.x];
                RGBA materialHere = materialScan[i];
                float roughness = materialHere.r * div255;
                RGBA ibaseColor = diffuseScan[i];
                vec3f baseColor = vec3f(ibaseColor.r, ibaseColor.g, ibaseColor.b) * div255;
                vec3f normal = vec3f(normalFromBuf.r, normalFromBuf.g, normalFromBuf.b);
                float diffuseFactor = 0.5f + 0.5f * dot(normal, direction);
                diffuseFactor = linmap!float(diffuseFactor, 0.24f - roughness * 0.5f, 1, 0, 1.0f);
                vec3f finalColor = baseColor * color * diffuseFactor;
                accumScan[i - area.min.x] += RGBAf(finalColor.r, finalColor.g, finalColor.b, 0.0f);
            }
        }
    }
}

class PassSpecularLight : CompositorPass
{
nothrow:
@nogc:
public:

    /// World-space direction. Unsure of the particular space it lives in.
    vec3f direction = vec3f(0.0f, 1.0f, 0.1f).normalized;

    /// Color of this light pass.
    vec3f color = vec3f(0.26f, 0.26f, 0.26f);

    this(MultipassCompositor parent)
    {
        super(parent);
        _specularFactor.reallocBuffer(numThreads());
        _exponentFactor.reallocBuffer(numThreads());

        // initialize new elements in the array, else realloc wouldn't work well next
        for (int thread = 0; thread < numThreads(); ++thread)
        {
            _specularFactor[thread] = null;
            _exponentFactor[thread] = null;
        }

        for (int roughByte = 0; roughByte < 256; ++roughByte)
        {
            _exponentTable[roughByte] = 0.8f * exp( (1-roughByte / 255.0f) * 5.5f);

            // Convert Phong exponent to Blinn-phong exponent
            version(legacyBlinnPhong)
            {}
            else
                _exponentTable[roughByte] *= 2.8f; // tuned bu hand to match the former Phong specular highlight. This makes very little difference.
        }

    }

    override void resizeBuffers(int width, 
                                int height,
                                int areaMaxWidth,
                                int areaMaxHeight)
    {
        // resize all thread-local buffers
        for (int thread = 0; thread < numThreads(); ++thread)
        {
            _specularFactor[thread].reallocBuffer(width);
            _exponentFactor[thread].reallocBuffer(width);
        }
    }

    override void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        PBRCompositorPassBuffers* PBRbuf = cast(PBRCompositorPassBuffers*) buffers;
        OwnedImage!RGBA diffuseLevel0 = PBRbuf.diffuseMap.levels[0];
        OwnedImage!RGBA materialLevel0 = PBRbuf.materialMap.levels[0];
        OwnedImage!RGBf normalBuffer = PBRbuf.normalBuffers[threadIndex];
        OwnedImage!RGBAf accumBuffer = PBRbuf.accumBuffers[threadIndex];

        int w = diffuseLevel0.w;
        int h = diffuseLevel0.h;
        immutable float invW = 1.0f / w;
        immutable float invH = 1.0f / h;

        __m128 mmlight3Dir = _mm_setr_ps(-direction.x, -direction.y, -direction.z, 0.0f);
        float* pSpecular = _specularFactor[threadIndex].ptr;
        float* pExponent = _exponentFactor[threadIndex].ptr;

        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBA* materialScan = materialLevel0.scanlinePtr(j);
            RGBA* diffuseScan = diffuseLevel0.scanlinePtr(j);
            RGBf* normalScan = normalBuffer.scanlinePtr(j - area.min.y);
            RGBAf* accumScan = accumBuffer.scanlinePtr(j - area.min.y);

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                RGBA materialHere = materialScan[i];
                RGBf normalFromBuf = normalScan[i - area.min.x];
                __m128 normal = convertNormalToFloat4(normalFromBuf);

                // TODO: this should be tuned interactively, maybe it's annoying to feel
                //       Need to compute the viewer distance from screen... and DPI.
                __m128 toEye = _mm_setr_ps(0.5f - i * invW, j * invH - 0.5f, 1.0f, 0.0f);
                toEye = _mm_fast_normalize_ps(toEye);

                version(legacyBlinnPhong)
                {
                    __m128 lightReflect = _mm_reflectnormal_ps(mmlight3Dir, normal);
                    float specularFactor = _mm_dot_ps(toEye, lightReflect);
                }
                else
                {
                    __m128 halfVector = toEye - mmlight3Dir;
                    halfVector = _mm_fast_normalize_ps(halfVector);
                    float specularFactor = _mm_dot_ps(halfVector, normal);
                }
                if (specularFactor < 1e-3f) 
                    specularFactor = 1e-3f;
                pSpecular[i] = specularFactor;
                pExponent[i] = _exponentTable[materialHere.r];
            }

            // Just the pow operation for this line
            {
                int i = area.min.x;
                for (; i + 3 < area.max.x; i += 4)
                {
                    _mm_storeu_ps(&pSpecular[i], _mm_pow_ps(_mm_loadu_ps(&pSpecular[i]), _mm_loadu_ps(&pExponent[i])));
                }
                for (; i < area.max.x; ++i)
                {
                    pSpecular[i] = _mm_pow_ss(pSpecular[i], pExponent[i]);
                }
            }

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                float specularFactor = pSpecular[i];

                __m128 material = convertMaterialToFloat4(materialScan[i]);
                RGBA materialHere = materialScan[i];
                float roughness = material.array[0];
                float metalness = material.array[1];
                float specular  = material.array[2];
                __m128 baseColor = convertBaseColorToFloat4(diffuseScan[i]);
                __m128 mmLightColor = _mm_setr_ps(color.x, color.y, color.z, 0.0f);

                float roughFactor = 10 * (1.0f - roughness) * (1 - metalness * 0.5f);
                specularFactor = specularFactor * roughFactor;
                __m128 finalColor = baseColor * mmLightColor * _mm_set1_ps(specularFactor * specular);

                _mm_store_ps(cast(float*)(&accumScan[i - area.min.x]), _mm_load_ps(cast(float*)(&accumScan[i - area.min.x])) + finalColor);
            }
        }
    }

    ~this()
    {
        foreach(thread; 0..numThreads())
        {
            _specularFactor[thread].reallocBuffer(0);
            _exponentFactor[thread].reallocBuffer(0);
        }
        _specularFactor.reallocBuffer(0);
        _exponentFactor.reallocBuffer(0);
    }

private:
    float[256] _exponentTable;

    // Note: those are thread-local buffers
    float[][] _specularFactor;
    float[][] _exponentFactor;    
}

class PassSkyboxReflections : CompositorPass
{
nothrow:
@nogc:
public:

    float amount = 0.52f;

    this(MultipassCompositor parent)
    {
        super(parent);
    }

    ~this()
    {
        if (_skybox !is null)
        {
            _skybox.destroyFree();
            _skybox = null;
        }
    }

    // Note: take ownership of image
    // That image must have been built with `mallocNew`
    void setSkybox(OwnedImage!RGBA image)
    {
        if (_skybox !is null)
        {
            _skybox.destroyFree();
            _skybox = null;
        }
        _skybox = mallocNew!(Mipmap!RGBA)(12, image);
        _skybox.generateMipmaps(Mipmap!RGBA.Quality.box);
    }

    override void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        PBRCompositorPassBuffers* PBRbuf = cast(PBRCompositorPassBuffers*) buffers;
        OwnedImage!RGBA diffuseLevel0 = PBRbuf.diffuseMap.levels[0];
        OwnedImage!RGBA materialLevel0 = PBRbuf.materialMap.levels[0];
        OwnedImage!RGBf normalBuffer = PBRbuf.normalBuffers[threadIndex];
        OwnedImage!RGBAf accumBuffer = PBRbuf.accumBuffers[threadIndex];
        OwnedImage!L32f varianceBuffer = PBRbuf.varianceBuffers[threadIndex];

        int w = diffuseLevel0.w;
        int h = diffuseLevel0.h;
        immutable float invW = 1.0f / w;
        immutable float invH = 1.0f / h;

        // skybox reflection (use the same shininess as specular)
        if (_skybox !is null)
        {
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                RGBA* materialScan = materialLevel0.scanlinePtr(j);
                RGBA* diffuseScan = diffuseLevel0.scanlinePtr(j);
                RGBf* normalScan = normalBuffer.scanlinePtr(j - area.min.y);
                RGBAf* accumScan = accumBuffer.scanlinePtr(j - area.min.y);
                L32f* varianceScan = varianceBuffer.scanlinePtr(j - area.min.y);

                immutable float amountOfSkyboxPixels = _skybox.width * _skybox.height;
                
                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    // First compute the needed mipmap level for this line
                    float mipmapLevel = varianceScan[i - area.min.x].l * amountOfSkyboxPixels;
                    enum float ROUGH_FACT = 6.0f / 255.0f;
                    float roughness = materialScan[i].r;
                    mipmapLevel = 0.5f * fastlog2(1.0f + mipmapLevel * 0.00001f) + ROUGH_FACT * roughness;

                    immutable float fskyX = (_skybox.width - 1.0f);
                    immutable float fSkyY = (_skybox.height - 1.0f);

                    immutable float amountFactor = amount * div255;

                    // TODO: same remark than above about toEye, something to think about
                    __m128 toEye = _mm_setr_ps(0.5f - i * invW, j * invH - 0.5f, 1.0f, 0.0f);
                    toEye = _mm_fast_normalize_ps(toEye);

                    __m128 normal = convertNormalToFloat4(normalScan[i - area.min.x]);
                    __m128 pureReflection = _mm_reflectnormal_ps(toEye, normal);
                    __m128 material = convertMaterialToFloat4(materialScan[i]);
                    float metalness = material.array[1];
                    __m128 baseColor = convertBaseColorToFloat4(diffuseScan[i]);
                    float skyx = 0.5f + ((0.5f - pureReflection.array[0] * 0.5f) * fskyX);
                    float skyy = 0.5f + ((0.5f + pureReflection.array[1] * 0.5f) * fSkyY);
                    __m128 skyColorAtThisPoint = convertVec4fToFloat4( _skybox.linearMipmapSample(mipmapLevel, skyx, skyy) );
                    __m128 color = baseColor * skyColorAtThisPoint * _mm_set1_ps(metalness * amountFactor);
                    _mm_store_ps(cast(float*)(&accumScan[i - area.min.x]), _mm_load_ps(cast(float*)(&accumScan[i - area.min.x])) + color);
                }
            }
        }
    }

private:
    /// Used for faking environment reflections.
    Mipmap!RGBA _skybox = null;
}

class PassEmissiveContribution : CompositorPass
{
nothrow:
@nogc:
public:

    this(MultipassCompositor parent)
    {
        super(parent);
    }

    override void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        PBRCompositorPassBuffers* PBRbuf = cast(PBRCompositorPassBuffers*) buffers;
        OwnedImage!RGBAf accumBuffer = PBRbuf.accumBuffers[threadIndex];
        Mipmap!RGBA diffuseMap = PBRbuf.diffuseMap;

        // Add light emitted by neighbours
        // Bloom-like.
        for (int j = area.min.y; j < area.max.y; ++j)
        {
            RGBAf* accumScan = accumBuffer.scanlinePtr(j - area.min.y);
            for (int i = area.min.x; i < area.max.x; ++i)
            {
                float ic = i + 0.5f;
                float jc = j + 0.5f;

                // Get alpha-premultiplied, avoids to have to do alpha-aware mipmapping
                vec4f colorLevel1 = diffuseMap.linearSample(1, ic, jc);
                vec4f colorLevel2 = diffuseMap.linearSample(2, ic, jc);
                vec4f colorLevel3 = diffuseMap.linearSample(3, ic, jc);
                vec4f colorLevel4 = diffuseMap.linearSample(4, ic, jc);
                vec4f colorLevel5 = diffuseMap.linearSample(5, ic, jc);

                vec4f emitted = colorLevel1 * 0.00117647f;
                emitted += colorLevel2      * 0.00176471f;
                emitted += colorLevel3      * 0.00147059f;
                emitted += colorLevel4      * 0.00088235f;
                emitted += colorLevel5      * 0.00058823f;
                accumScan[i - area.min.x] += RGBAf(emitted.r, emitted.g, emitted.b, emitted.a);
            }
        }
    }
}

class PassClampAndConvertTo8bit : CompositorPass
{
nothrow:
@nogc:
public:

    this(MultipassCompositor parent)
    {
        super(parent);
    }

    override void render(int threadIndex, const(box2i) area, CompositorPassBuffers* buffers)
    {
        PBRCompositorPassBuffers* PBRbuf = cast(PBRCompositorPassBuffers*) buffers;
        OwnedImage!RGBAf accumBuffer = PBRbuf.accumBuffers[threadIndex];
        ImageRef!RGBA* wfb = PBRbuf.outputBuf;
        
        immutable __m128 mm255_99 = _mm_set1_ps(255.99f);
        immutable __m128i zero = _mm_setzero_si128();

        // Final pass, clamp, convert to ubyte
        for (int j = area.min.y; j < area.max.y; ++j)
        {
            int* wfb_scan = cast(int*)(wfb.scanline(j).ptr);
            const(RGBAf)* accumScan = accumBuffer.scanlinePtr(j - area.min.y);            

            for (int i = area.min.x; i < area.max.x; ++i)
            {
                RGBAf accum = accumScan[i - area.min.x];
                __m128 color = _mm_setr_ps(accum.r, accum.g, accum.b, 1.0f);
                __m128i icolorD = _mm_cvttps_epi32(color * mm255_99);
                __m128i icolorW = _mm_packs_epi32(icolorD, zero);
                __m128i icolorB = _mm_packus_epi16(icolorW, zero);
                wfb_scan[i] = icolorB.array[0];
            }
        }
    }
}




private:

// log2 approximation by Laurent de Soras
// http://www.flipcode.com/archives/Fast_log_Function.shtml
float fastlog2(float val) pure nothrow @nogc
{
    union fi_t
    {
        int i;
        float f;
    }

    fi_t fi;
    fi.f = val;
    int x = fi.i;
    int log_2 = ((x >> 23) & 255) - 128;
    x = x & ~(255 << 23);
    x += 127 << 23;
    fi.i = x;
    return fi.f + log_2;
}

// log2 approximation by Laurent de Soras
// http://www.flipcode.com/archives/Fast_log_Function.shtml
// Same but 4x at once
__m128 _mm_fastlog2_ps(__m128 val) pure nothrow @nogc
{
    __m128i x = _mm_castps_si128(val);
    __m128i m128 = _mm_set1_epi32(128);
    __m128i m255 = _mm_set1_epi32(255);
    __m128i log_2 = _mm_and_si128(_mm_srai_epi32(x, 23), m255) - m128;
    x = _mm_and_si128(x, _mm_set1_epi32(~(255 << 23)));
    x = x + _mm_set1_epi32(127 << 23);
    __m128 fif = _mm_castsi128_ps(x);
    return fif + _mm_cvtepi32_ps(log_2);
}



alias convertMaterialToFloat4 = convertBaseColorToFloat4;

// Convert a 8-bit color to a normalized 4xfloat color
__m128 convertBaseColorToFloat4(RGBA rgba) nothrow @nogc pure
{
    int asInt = *cast(int*)(&rgba);
    __m128i packed = _mm_cvtsi32_si128(asInt);
    __m128i mmZero = _mm_setzero_si128();
    __m128i shorts = _mm_unpacklo_epi8(packed, mmZero);
    __m128i ints = _mm_unpacklo_epi16(shorts, mmZero);
    return _mm_cvtepi32_ps(ints) * _mm_set1_ps(div255);
}

__m128 convertNormalToFloat4(RGBf normal) nothrow @nogc pure
{
    return _mm_setr_ps(normal.r, normal.g, normal.b, 0.0f);
}

__m128 convertVec4fToFloat4(vec4f vec) nothrow @nogc pure
{
    return _mm_setr_ps(vec.x, vec.y, vec.z, vec.w);
}

private enum float div255 = 1 / 255.0f;