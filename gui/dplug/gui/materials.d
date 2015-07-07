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
    ubyte roughness;

    // Pre-defined materials
    static Material
        iron     =    Material(RGB(143, 145, 148), 255),
        silver   =    Material(RGB(248, 245, 233), 255),
        aluminum =    Material(RGB(233, 235, 236), 255),
        gold     =    Material(RGB(255, 195,  86), 255),
        copper   =    Material(RGB(243, 162, 137), 255),
        chromium =    Material(RGB(140, 142, 141), 255),
        nickel   =    Material(RGB(168, 155, 134), 255),
        titanium =    Material(RGB(138, 127, 114), 255),
        cobalt   =    Material(RGB(169, 170, 162), 255),
        platinum =    Material(RGB(171, 162, 218), 255),
        charcoal =    Material(RGB( 50,  50,  50),  10), 
        wornAsphalt = Material(RGB( 70,  70,  70),  10), 
        desertSand =  Material(RGB( 92,  92,  92),  10), 
        oceanIce =    Material(RGB(142, 142, 142),  10), 
        freshSnow =   Material(RGB(207, 207, 207),  10); 
}

// Sets of recommended values

enum ushort defaultDepth = 15000;
enum ushort defaultRoughness = 128;
enum ushort defaultSpecular = 128; // because everything is shiny
enum ushort defaultPhysical = 255;
enum ushort defaultMetalnessDielectric = 10; // ~ 0.04
enum ushort defaultMetalnessMetal = 255;
