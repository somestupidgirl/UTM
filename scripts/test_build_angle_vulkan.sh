#!/bin/bash
set -e

# Setup directories
export BUILD_DIR="$(pwd)/build"
export PREFIX="$(pwd)/sysroot"
mkdir -p "$BUILD_DIR"
mkdir -p "$PREFIX/lib/vulkan"

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Download WebKit
WEBKIT_REPO="https://github.com/utmapp/WebKit.git"
WEBKIT_COMMIT="ed78ab6e1a37f4f11583a0bd038f22ec91f3ff10"
WEBKIT_SUBDIRS="Source/ThirdParty/ANGLE Configurations Tools/ccache"

cd "$BUILD_DIR"
if [ ! -d "WebKit.git" ]; then
    echo -e "${GREEN}Cloning WebKit...${NC}"
    git clone --filter=tree:0 --no-checkout "$WEBKIT_REPO" WebKit.git
    cd WebKit.git
    git sparse-checkout init
    git sparse-checkout set $WEBKIT_SUBDIRS
    git checkout "$WEBKIT_COMMIT"
    cd ..
fi

# Download depot_tools
if [ ! -d "depot_tools.git" ]; then
    echo -e "${GREEN}Cloning depot_tools...${NC}"
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git depot_tools.git
fi
export PATH="$(realpath depot_tools.git):$PATH"

# Build ANGLE Vulkan
cd WebKit.git/Source/ThirdParty/ANGLE
echo -e "${GREEN}Bootstrapping ANGLE for Vulkan (gclient sync)...${NC}"
python3 scripts/bootstrap.py
gclient sync

echo -e "${GREEN}Configuring ANGLE (Vulkan)...${NC}"
gn gen out/Release --args='target_os="ios" target_cpu="arm64" is_debug=false angle_enable_vulkan=true angle_enable_metal=false angle_enable_gl=false'

echo -e "${GREEN}Building ANGLE (Vulkan)...${NC}"
ninja -C out/Release libGLESv2 libEGL

echo -e "${GREEN}Installing ANGLE (Vulkan)...${NC}"
cp out/Release/libGLESv2.dylib "$PREFIX/lib/vulkan/"
cp out/Release/libEGL.dylib "$PREFIX/lib/vulkan/"

echo -e "${GREEN}Done! ANGLE Vulkan libraries are located at: $PREFIX/lib/vulkan/${NC}"
