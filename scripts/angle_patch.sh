#!/bin/bash
set -e

export BUILD_DIR="$(pwd)/build"
export PATH="$(realpath depot_tools.git):$PATH"
cd "$BUILD_DIR/angle"

echo "=== Patch 1: vulkan-loader source files - add missing macros ==="
sed -i '' '1s/^/#define FALLBACK_CONFIG_DIRS "\/etc\/xdg"\n#define FALLBACK_DATA_DIRS "\/usr\/local\/share:\/usr\/share"\n#define SYSCONFDIR "\/etc"\n/' third_party/vulkan-loader/src/loader/settings.c || true
sed -i '' '1s/^/#define FALLBACK_CONFIG_DIRS "\/etc\/xdg"\n#define FALLBACK_DATA_DIRS "\/usr\/local\/share:\/usr\/share"\n#define SYSCONFDIR "\/etc"\n/' third_party/vulkan-loader/src/loader/loader.c || true
echo "Done: patched settings.c and loader.c"

echo ""
echo "=== Patch 2: vulkan-loader BUILD.gn - CoreFoundation for iOS ==="
VULKAN_LOADER_GN="third_party/vulkan-loader/src/BUILD.gn"
sed -i '' 's/if (is_mac)/if (is_apple)/g' "$VULKAN_LOADER_GN"
if ! grep -q 'CoreFoundation' "$VULKAN_LOADER_GN"; then
    sed -i '' '/shared_library("libvulkan")/{
n
a\
  if (is_ios) { frameworks = [ "CoreFoundation.framework" ] }
}' "$VULKAN_LOADER_GN"
fi
echo "Done: CoreFoundation patched"

echo ""
echo "=== Patch 3: vulkan_backend.gni - include VulkanMac display for iOS ==="
VULKAN_BACKEND_GNI="src/libANGLE/renderer/vulkan/vulkan_backend.gni"
echo "Before patch - condition around mac backend sources (lines 220-240):"
sed -n '220,240p' "$VULKAN_BACKEND_GNI" 2>/dev/null || echo "(could not read)"

# The mac backend sources (DisplayVkMac.mm etc.) are gated by is_mac.
# iOS also uses this backend (via MoltenVK). Change is_mac to is_apple.
sed -i '' 's/if (is_mac)/if (is_apple)/g' "$VULKAN_BACKEND_GNI"

echo ""
echo "After patch - condition around mac backend sources (lines 220-240):"
sed -n '220,240p' "$VULKAN_BACKEND_GNI" 2>/dev/null || echo "(could not read)"

echo ""
echo "=== Patch 4: angle.gni - fix default for angle_shared_libvulkan ==="
ANGLE_GNI="gni/angle.gni"
echo "Before patch - angle_shared_libvulkan default:"
grep -n 'angle_shared_libvulkan' "$ANGLE_GNI" 2>/dev/null || echo "(not found)"
# Default is !is_mac (static on mac). For iOS we explicitly set it in GN args, so this is informational only.

echo ""
echo "=== All patches applied ==="
