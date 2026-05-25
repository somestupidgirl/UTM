#!/bin/bash
set -e

# Setup directories
export BUILD_DIR="$(pwd)/build"
export PREFIX="$(pwd)/sysroot"
mkdir -p "$BUILD_DIR"
mkdir -p "$PREFIX/lib/vulkan"

# Download depot_tools
if [ ! -d "depot_tools.git" ]; then
    echo "Cloning depot_tools..."
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git depot_tools.git
fi
export PATH="$(realpath depot_tools.git):$PATH"

# Download ANGLE source
cd "$BUILD_DIR"
if [ ! -d "angle" ]; then
    echo "Fetching upstream ANGLE (gclient sync)..."
    mkdir angle
    cd angle
    fetch angle
else
    echo "Syncing upstream ANGLE..."
    cd angle
    gclient sync
fi
