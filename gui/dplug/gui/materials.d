/**
* Copyright: Copyright Auburn Sounds 2015 and later.
* License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
* Authors:   Guillaume Piolat
*/
module dplug.gui.materials;

import ae.utils.graphics;

/// Common material albedo values from Unreal Engine.
/// https://docs.unrealengine.com/latest/INT/Engine/Rendering/Materials/PhysicallyBased/index.html

struct Material
{
    RGB albedo;
    ubyte metalness;
    ubyte specular;

    /// Return a RGBA suitable to fit into the diffuse map
    /// emissive must be provided since it isn't a material feature
    RGBA diffuse(ubyte emissive) pure const nothrow @nogc
    {
        return RGBA(albedo.r, albedo.g, albedo.b, emissive);
    }

    /// Return a RGBA suitable to fit into the material map
    /// roughness and physical must be provided since they aren't material features
    RGBA material(ubyte roughness, ubyte physical = 255) pure const nothrow @nogc
    {
        return RGBA(roughness, metalness, specular, physical);
    }

    // Pre-defined materials
    static Material
        iron     =    Material(RGB(143, 145, 148), 255, 128),
        silver   =    Material(RGB(248, 245, 233), 255, 128),
        aluminum =    Material(RGB(233, 235, 236), 255, 128),
        gold     =    Material(RGB(255, 195,  86), 255, 128),
        copper   =    Material(RGB(243, 162, 137), 255, 128),
        chromium =    Material(RGB(140, 142, 141), 255, 128),
        nickel   =    Material(RGB(168, 155, 134), 255, 128),
        titanium =    Material(RGB(138, 127, 114), 255, 128),
        cobalt   =    Material(RGB(169, 170, 162), 255, 128),
        platinum =    Material(RGB(171, 162, 218), 255, 128),
        charcoal =    Material(RGB( 50,  50,  50),  defaultMetalnessDielectric, 64), 
        wornAsphalt = Material(RGB( 70,  70,  70),  defaultMetalnessDielectric, 64), 
        desertSand =  Material(RGB( 92,  92,  92),  defaultMetalnessDielectric, 64), 
        oceanIce =    Material(RGB(142, 142, 142),  defaultMetalnessDielectric, 57), 
        freshSnow =   Material(RGB(255, 255, 255),  defaultMetalnessDielectric, 50); 
}

// Sets of recommended values

enum ushort defaultDepth = 15000;
enum ushort defaultRoughness = 128;
enum ushort defaultSpecular = 128; // because everything is shiny
enum ushort defaultPhysical = 255;
enum ushort defaultMetalnessDielectric = 25; // ~ 0.08
enum ushort defaultMetalnessMetal = 255;
