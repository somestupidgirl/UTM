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
echo "============================================================"
echo "=== DEBUG: Finding where VulkanMac backend is controlled ==="
echo "============================================================"

echo ""
echo "--- Search ALL BUILD.gn/gni files for DisplayVkMac ---"
grep -rn 'DisplayVkMac' --include='*.gn' --include='*.gni' . 2>/dev/null | head -30 || echo "(not found)"

echo ""
echo "--- Search ALL BUILD.gn/gni files for VulkanMac ---"
grep -rn 'VulkanMac\|vulkan_mac\|vulkan.*mac' --include='*.gn' --include='*.gni' . 2>/dev/null | head -30 || echo "(not found)"

echo ""
echo "--- Search for angle_enable_vulkan related GN variables ---"
grep -rn 'angle_enable_vulkan' --include='*.gn' --include='*.gni' . 2>/dev/null | grep -i 'mac\|apple\|ios' | head -20 || echo "(not found)"

echo ""
echo "--- Search for CreateVulkanMacDisplay definition ---"
grep -rn 'CreateVulkanMacDisplay\|IsVulkanMacDisplayAvailable' --include='*.cpp' --include='*.mm' --include='*.h' src/libANGLE/ 2>/dev/null | head -20 || echo "(not found)"

echo ""
echo "--- Search Display.cpp for how VulkanMac is conditionally compiled ---"
grep -B5 -A2 'VulkanMac' src/libANGLE/Display.cpp 2>/dev/null || echo "(not found)"

echo ""
echo "--- Search for ANGLE_ENABLE_VULKAN ifdef around VulkanMac ---"
grep -B10 'CreateVulkanMacDisplay' src/libANGLE/Display.cpp 2>/dev/null | head -20 || echo "(not found)"

echo ""
echo "--- List all .gn/.gni files in vulkan renderer ---"
find src/libANGLE/renderer/vulkan -name '*.gn' -o -name '*.gni' 2>/dev/null || echo "(none)"

echo ""
echo "--- Content of vulkan renderer BUILD.gn (mac-related sections) ---"
grep -n -B2 -A5 'mac\|apple\|ios' src/libANGLE/renderer/vulkan/BUILD.gn 2>/dev/null | head -50 || echo "(not found or no mac references)"

echo ""
echo "--- Search for where vulkan mac sources are listed ---"
grep -rn 'mac/' src/libANGLE/renderer/vulkan/BUILD.gn 2>/dev/null | head -20 || echo "(not in BUILD.gn)"
grep -rn 'mac/' --include='*.gni' src/libANGLE/renderer/vulkan/ 2>/dev/null | head -20 || echo "(not in .gni files)"

echo ""
echo "--- Check if there's a separate mac BUILD.gn ---"
ls -la src/libANGLE/renderer/vulkan/mac/BUILD.gn 2>/dev/null || echo "(no BUILD.gn in mac dir)"
cat src/libANGLE/renderer/vulkan/mac/BUILD.gn 2>/dev/null || echo "(no separate BUILD.gn)"

echo ""
echo "--- Check angle_vulkan.gni or similar for mac backend ---"
find . -name '*vulkan*.gni' -not -path '*/third_party/*' 2>/dev/null | head -10
for f in $(find . -name '*vulkan*.gni' -not -path '*/third_party/*' 2>/dev/null); do
    echo "Contents of $f (mac-related):"
    grep -n -B2 -A5 'mac\|apple\|ios\|DisplayVk' "$f" 2>/dev/null | head -30 || echo "(none)"
done

echo ""
echo "=== All patches and debug complete ==="
