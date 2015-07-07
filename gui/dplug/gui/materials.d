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
        charcoal =    Material(RGB(  5,   5,   5),   0), 
        wornAsphalt = Material(RGB( 20,  20,  20),   0), 
        desertSand =  Material(RGB( 92,  92,  92),   0), 
        oceanIce =    Material(RGB(142, 142, 142),   0), 
        freshSnow =   Material(RGB(207, 207, 207),   0); 
}