/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
import std.math;
import std.random;

import gfm.image;

import dplug.core,
       dplug.plugin,
       dplug.vst,
       dplug.dsp,
       dplug.gui;

mixin(DLLEntryPoint!());
mixin(VSTEntryPoint!MaterialsPlugin);

/// Example mono/stereo distortion plugin.
final class MaterialsPlugin : dplug.plugin.Client
{
public:

    this()
    {
    }

    override bool isSynth() pure const nothrow
    {
        return false;
    }

    override IGraphics createGraphics()
    {
        return new MaterialsGUI(this);
    }

    override int getPluginID() pure const nothrow
    {
        return CCONST('g', 'f', 'm', '1'); // change this!
    }

    override void buildLegalIO()
    {
        addLegalIO(1, 1);
        addLegalIO(1, 2);
        addLegalIO(2, 1);
        addLegalIO(2, 2);
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {       
    }

    override void processAudio(const(double*)[] inputs, double*[]outputs, int frames) nothrow @nogc
    {       
    }
}

class MaterialsGUI : GUIGraphics
{
public:
    MaterialsPlugin _client;

    this(MaterialsPlugin client)
    {
        _client = client;
        super(1024, 1024); // initial size

        context.setSkybox( loadImage(cast(ubyte[])(import("skybox.png"))) );        
    }

    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!L16 depthMap, ImageRef!RGBA materialMap, box2i[] dirtyRects)
    {
        // Always redraw everything       
        
        materialMap.fill(RGBA(128, defaultMetalnessMetal, defaultSpecular, defaultPhysical));
        depthMap.fill(L16(defaultDepth));
        diffuseMap.fill(RGBA(186, 186, 186, 0));

        void makeBall(float curvature)(float x, float y, float radius, ushort height, ubyte roughness, ubyte emissive, Material material)
        {
            RGBA diffuse = RGBA(material.albedo.r, material.albedo.g, material.albedo.b, emissive);

      //      diffuse = RGBA(255, 128, 128, 0);

            ubyte metalness = material.metalness;
            ubyte specular = material.specular;
            ubyte physical = 255;

            depthMap.softCircleFloat!1.4f(x, y, 0, radius, L16(height));
            
            diffuseMap.softCircleFloat(x, y, radius- 2, radius, diffuse);            
            materialMap.softCircleFloat(x, y, radius - 2, radius, RGBA(roughness, metalness, specular, physical));
            
        }

        import gfm.math;

        Random random = Random();

        foreach(ghertg; 0..5000)
        {
            float fr = uniform(0.8f, 1.0f);
            float fg = uniform(0.0f, 0.2f);
            float fb = uniform(0.3f, 0.4f);

            float radius = 2 + 50.0f * uniform(0.0f, 1.0f) ^^ 2;

            if (uniform(0.0f, 1.0f) < 0.5f)
            {
                fr *= 0.4f;
                fg *= 0.4f;
                fb *= 0.4f;
                radius *= 0.5f;
            }else
                if (uniform(0.0f, 1.0f) < 0.5f)
                {
                    fr *= 2.0f;
                    fg *= 2.0f;
                    fb *= 2.0f;
                    radius *= 0.4f;
                }

            ubyte r = cast(ubyte)(0.5 + 255.0f * fr);
            ubyte g = cast(ubyte)(0.5 + 255.0f * fg);
            ubyte b = cast(ubyte)(0.5 + 255.0f * fb);
            ubyte metal = cast(ubyte)(0.5 + 255.0f * uniform(0.0f, 1.0f));
            ubyte emissive = cast(ubyte)(0.5 + 255.0f * uniform(0.0f, 1.0f) ^^ 4);
            ubyte specular = cast(ubyte)(0.5 + 255.0f * uniform(0.0f, 1.0f));
            ubyte roughness = cast(ubyte)(0.5 + 255.0f * uniform(0.0f, 1.0f) ^^ 2 );

            Material mat;
            mat.albedo = ae.utils.graphics.RGB(r, g, b);
            mat.metalness =  uniform(0.0f, 1.0f) > 0.5 ? 255 : 10;
            mat.specular = specular;

            float x = randNormal(random, 511.5f, 128.0f);
            float y = randNormal(random, 511.5f, 128.0f);
            
            ushort depth = uniform(0.0f, 1.0f) > 0.5 ? 65535 : 0;

            makeBall!1.0f(x, y, radius, depth, roughness, emissive, mat);
        }
/*
        makeBall!1.0f(150, 150, 60, 65535, 32, Material.aluminum);
        makeBall!0.3f(100, 170, 60, 0, 128, Material.nickel);
   */     
        
        
        
        /*makeBall!1.2f(350, 100, 80, 0, Material.platinum);
        makeBall!1.3f(400, 100, 60, 0, Material.gold);
        makeBall!1.4f(500, 100, 80, 0, Material.copper);*/
/*
        makeBall( 50, 150, 0, Material.oceanIce);
        makeBall(150, 150, 0, Material.platinum);
        makeBall(250, 150, 0, Material.silver);
        makeBall(350, 150, 0, Material.titanium);
        makeBall(450, 150, 0, Material.wornAsphalt);*/
/*
        void makeRect(int x1, int y1, int x2, int y2, ushort depth0, ushort depth1,ubyte roughness, Material material)
        {
            RGBA diffuse = RGBA(material.albedo.r, material.albedo.g, material.albedo.b, 0);

            diffuseMap.fillRect(x1, y1, x2, y2, diffuse);

            ubyte metalness = material.metalness;
            ubyte specular = material.specular;
            ubyte physical = 255;
            materialMap.fillRect(x1, y1, x2, y2,  RGBA(roughness, metalness, specular, physical));
            depthMap.verticalSlope(box2i(x1, y1, x2, y2), L16(depth0), L16(depth1));
        }

        for (int i = 0; i < 10; ++i)
        {
            makeRect(i * 90, 250, i * 90 + 70, 270 + i * 20, 0, 65535, 128, Material.iron);
        }*/
    }
}

