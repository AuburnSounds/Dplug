#!/bin/bash
dub --root=../../examples/distort -c LV2
sudo rm -rf /usr/lib/lv2/lv2example.lv2
sudo mkdir /usr/lib/lv2/lv2example.lv2
sudo cp ../../examples/distort/libdistort.so /usr/lib/lv2/lv2example.lv2/libdistort.so
sudo cp manifest.ttl /usr/lib/lv2/lv2example.lv2/manifest.ttl
sudo cp lv2example.ttl /usr/lib/lv2/lv2example.lv2/lv2example.ttl