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
        super(1024, 256); // initial size

        context.setSkybox( loadImage(cast(ubyte[])(import("skybox.png"))) );        
    }

    override void reflow(box2i availableSpace)
    {
        _position = availableSpace;
    }

    override void onDraw(ImageRef!RGBA diffuseMap, ImageRef!RGBA depthMap, box2i[] dirtyRects)
    {
        // Always redraw everything

        
        
        depthMap.fill(RGBA(5, 5, 5, 128));
        diffuseMap.fill(RGBA(128, 128, 128, 0));

        void makeBall(float x, float y, ubyte roughness, Material material)
        {
            RGBA diffuse = RGBA(material.albedo.r, material.albedo.g, material.albedo.b, 0);

            diffuse = RGBA(255, 128, 128, 0);

            ubyte metalness = 0;//material.metalness;
            ubyte specular = 128;

            roughness = cast(ubyte)(linmap!float(x, 50, 950, 0, 255));

            depthMap.softCircleFloat!2.0f(x, y, 0, 40, RGBA(255, metalness, roughness, specular));
            diffuseMap.softCircleFloat!2.0f(x, y, 0, 40, diffuse);            
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

    }
}

