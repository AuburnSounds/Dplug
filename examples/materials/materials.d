/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
import std.math;

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

    override void buildParameters()
    {        
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
        super(1024, 512); // initial size

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

        void makeBall(float x, float y, ubyte roughness, Material material)
        {
            RGBA diffuse = RGBA(material.albedo.r, material.albedo.g, material.albedo.b, 0);

      //      diffuse = RGBA(255, 128, 128, 0);

            ubyte metalness = material.metalness;
            ubyte specular = material.specular;
            ubyte physical = 255;

            roughness = cast(ubyte)(linmap!float(x, 50, 950, 0, 255));

            depthMap.softCircleFloat!1.0f(x, y, 0, 40, L16(65535));
            
            diffuseMap.softCircleFloat(x, y, 38, 40, diffuse);            
            materialMap.softCircleFloat(x, y, 38, 40, RGBA(roughness, metalness, specular, physical));
            
        }

        makeBall( 50, 50, 0, Material.aluminum);
        makeBall(150, 50, 0, Material.charcoal);
        makeBall(250, 50, 0, Material.chromium);
        makeBall(350, 50, 0, Material.cobalt);
        makeBall(450, 50, 0, Material.copper);
        makeBall(550, 50, 0, Material.desertSand);
        makeBall(650, 50, 0, Material.freshSnow);
        makeBall(750, 50, 0, Material.gold);
        makeBall(850, 50, 0, Material.iron);
        makeBall(950, 50, 0, Material.nickel);
        makeBall( 50, 150, 0, Material.oceanIce);
        makeBall(150, 150, 0, Material.platinum);
        makeBall(250, 150, 0, Material.silver);
        makeBall(350, 150, 0, Material.titanium);
        makeBall(450, 150, 0, Material.wornAsphalt);

        makeBall(550, 150, 0, Material.oceanIce);
        makeBall(650, 150, 0, Material.platinum);
        makeBall(750, 150, 0, Material.silver);
        makeBall(850, 150, 0, Material.titanium);
        makeBall(950, 150, 0, Material.wornAsphalt);

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
        }
    }
}

