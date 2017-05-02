################################################################################
# New Project Creator for Dplug                                                #
# This script clones the ExamplePlugin directory to a new directory based on   #
# user input and replaces all of the important identifiers such as             #
# "pluginName", "vendorName", "vendorID", "pluginID" etc.                      #
################################################################################

import os
import shutil
import stat

src = "example-plugin"
vname = raw_input("Vendor Name: ")
vid = raw_input("Vender ID: ")
pname = raw_input("Plugin Name: ")
pid = raw_input("Plugin ID: ")
cfbundleIdentifier = raw_input("CFBundle Identifier: ")
issynth = raw_input("Synth?(y/n): ")
receivesmidi = raw_input("Recieves Midi?(y/n): ")

dest = pname.replace(" ", "_")

# Recursively copy all files and directories for ExamplePlugin to a new
# directory with the name of the new plugin.
shutil.copytree(src, dest)

# Rename the D source file to the name of the plugin.
for filename in os.listdir(dest):
    if filename.startswith("example"):
		print(filename)
		os.rename(dest + "/" + filename, dest + "/" + dest + ".d")

with open(dest + "/" + dest +".d", "wt") as fout:
    with open(src + "/" + "example.d", "rt") as fin:
        for line in fin:
            line.replace('Witty Audio', vname)
            line.replace('Wity', vid)
            line.replace('ExamplePlugin', pname)
            line.replace('WiDi', pid)
            line.replace('com.wittyaudio', cfbundleIdentifier)
            if issynth == "y":
                l.replace("false", "true")
            fout.write(line)
            
with open(dest + "/plugin.json", "wt") as fout:
    with open(src + "/plugin.json", "rt") as fin:
        for line in fin:
            line.replace('Witty Audio', vname)
            line.replace('Wity', vid)
            line.replace('ExamplePlugin', pname)
            line.replace('WiDi', pid)
            line.replace('com.wittyaudio', cfbundleIdentifier)
            if issynth == "y":
                l.replace("false", "true")
            fout.write(line)
            
with open(dest + "/dub.json", "wt") as fout:
    with open(src + "/dub.json", "rt") as fin:
        for line in fin:
            fout.write(line.replace('ExamplePlugin', pname))