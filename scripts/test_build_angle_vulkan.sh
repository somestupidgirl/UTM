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

# ============================================================
# Patch 1: vulkan-loader source files - add missing macros
# ============================================================
sed -i '' '1s/^/#define FALLBACK_CONFIG_DIRS "\/etc\/xdg"\n#define FALLBACK_DATA_DIRS "\/usr\/local\/share:\/usr\/share"\n#define SYSCONFDIR "\/etc"\n/' third_party/vulkan-loader/src/loader/settings.c || true
sed -i '' '1s/^/#define FALLBACK_CONFIG_DIRS "\/etc\/xdg"\n#define FALLBACK_DATA_DIRS "\/usr\/local\/share:\/usr\/share"\n#define SYSCONFDIR "\/etc"\n/' third_party/vulkan-loader/src/loader/loader.c || true

# ============================================================
# Patch 2: vulkan-loader BUILD.gn - add CoreFoundation for iOS
# The loader uses CF* functions but ANGLE only links CoreFoundation for is_mac
# ============================================================
VULKAN_LOADER_GN="third_party/vulkan-loader/src/BUILD.gn"
echo -e "${GREEN}Patching vulkan-loader BUILD.gn (is_mac -> is_apple)...${NC}"
sed -i '' 's/if (is_mac)/if (is_apple)/g' "$VULKAN_LOADER_GN"
if ! grep -q 'CoreFoundation' "$VULKAN_LOADER_GN"; then
    echo -e "${GREEN}CoreFoundation not found, adding manually...${NC}"
    sed -i '' '/shared_library("libvulkan")/{
n
a\
  if (is_ios) { frameworks = [ "CoreFoundation.framework" ] }
}' "$VULKAN_LOADER_GN"
fi

# ============================================================
# Patch 3: Vulkan renderer BUILD.gn - include VulkanMac display for iOS
# ANGLE's Vulkan backend gates the "mac" display (used for MoltenVK on Apple)
# behind is_mac, but iOS also needs it. Change is_mac to is_apple.
# ============================================================
echo -e "${GREEN}Patching ANGLE Vulkan backend BUILD.gn files (is_mac -> is_apple)...${NC}"
# Patch all BUILD.gn files in the vulkan renderer directory
find src/libANGLE/renderer/vulkan -name "BUILD.gn" -exec sed -i '' 's/if (is_mac)/if (is_apple)/g' {} \;
# Also patch the main libANGLE BUILD.gn which may gate vulkan mac backend
find src/libANGLE -maxdepth 1 -name "BUILD.gn" -exec sed -i '' 's/if (is_mac)/if (is_apple)/g' {} \;
# And the top-level src BUILD.gn
find src -maxdepth 1 -name "BUILD.gn" -exec sed -i '' 's/if (is_mac)/if (is_apple)/g' {} \;

# Debug: show what references exist for the VulkanMac display
echo -e "${GREEN}Checking VulkanMac display references...${NC}"
grep -rn "VulkanMac\|DisplayVkMac\|vulkan_mac\|is_apple" src/libANGLE/renderer/vulkan/BUILD.gn 2>/dev/null | head -20 || echo "(file not found)"
grep -rn "vulkan_mac\|VulkanMac" src/libANGLE/BUILD.gn 2>/dev/null | head -10 || echo "(not in libANGLE BUILD.gn)"

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
