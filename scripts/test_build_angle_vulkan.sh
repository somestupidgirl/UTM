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

# Download depot_tools
if [ ! -d "depot_tools.git" ]; then
    echo -e "${GREEN}Cloning depot_tools...${NC}"
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git depot_tools.git
fi
export PATH="$(realpath depot_tools.git):$PATH"

# Download and Build ANGLE Vulkan
cd "$BUILD_DIR"
if [ ! -d "angle" ]; then
    echo -e "${GREEN}Fetching upstream ANGLE (gclient sync)...${NC}"
    mkdir angle
    cd angle
    fetch angle
else
    echo -e "${GREEN}Syncing upstream ANGLE...${NC}"
    cd angle
    gclient sync
fi

echo -e "${GREEN}Configuring ANGLE (Vulkan)...${NC}"
# Patch vulkan-loader for iOS: add missing macro definitions
sed -i '' '1s/^/#define FALLBACK_CONFIG_DIRS "\/etc\/xdg"\n#define FALLBACK_DATA_DIRS "\/usr\/local\/share:\/usr\/share"\n#define SYSCONFDIR "\/etc"\n/' third_party/vulkan-loader/src/loader/settings.c || true
sed -i '' '1s/^/#define FALLBACK_CONFIG_DIRS "\/etc\/xdg"\n#define FALLBACK_DATA_DIRS "\/usr\/local\/share:\/usr\/share"\n#define SYSCONFDIR "\/etc"\n/' third_party/vulkan-loader/src/loader/loader.c || true

# Patch vulkan-loader BUILD.gn: the loader uses CoreFoundation (CFRelease, CFBundleGetMainBundle, etc.)
# but ANGLE's GN only adds it for is_mac, not is_ios. Fix by changing is_mac to is_apple.
VULKAN_LOADER_GN="third_party/vulkan-loader/src/BUILD.gn"
echo -e "${GREEN}Patching vulkan-loader BUILD.gn for CoreFoundation on iOS...${NC}"
# Method 1: If BUILD.gn has 'is_mac' gating CoreFoundation, broaden to is_apple
sed -i '' 's/if (is_mac)/if (is_apple)/g' "$VULKAN_LOADER_GN"
# Method 2: If CoreFoundation is still not linked for iOS, append it
if ! grep -q 'CoreFoundation' "$VULKAN_LOADER_GN"; then
    echo -e "${GREEN}CoreFoundation not found in BUILD.gn, adding manually...${NC}"
    # Find the libvulkan shared_library target and add frameworks
    sed -i '' '/shared_library("libvulkan")/{
n
a\
  if (is_ios) { frameworks = [ "CoreFoundation.framework" ] }
}' "$VULKAN_LOADER_GN"
fi
echo -e "${GREEN}Current CoreFoundation references in BUILD.gn:${NC}"
grep -n -i "corefoundation\|is_mac\|is_apple\|frameworks" "$VULKAN_LOADER_GN" || echo "(none found)"

gn gen out/Release --args='target_os="ios" target_cpu="arm64" target_environment="device" ios_enable_code_signing=false is_debug=false angle_enable_vulkan=true angle_shared_libvulkan=true angle_enable_swiftshader=false angle_enable_metal=false angle_enable_gl=false angle_enable_vulkan_validation_layers=false angle_build_tests=false angle_enable_dawn=false'

echo -e "${GREEN}Building ANGLE (Vulkan)...${NC}"
ninja -C out/Release libGLESv2 libEGL

echo -e "${GREEN}Installing ANGLE (Vulkan)...${NC}"
cp out/Release/libGLESv2.dylib "$PREFIX/lib/vulkan/"
cp out/Release/libEGL.dylib "$PREFIX/lib/vulkan/"
if [ -f out/Release/libvulkan.dylib ]; then
    cp out/Release/libvulkan.dylib "$PREFIX/lib/vulkan/"
fi

echo -e "${GREEN}Done! ANGLE Vulkan libraries are located at: $PREFIX/lib/vulkan/${NC}"
