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
echo "Before patch - is_mac references:"
grep -n 'is_mac' "$VULKAN_LOADER_GN" || echo "(none)"
echo "Before patch - CoreFoundation references:"
grep -n 'CoreFoundation' "$VULKAN_LOADER_GN" || echo "(none)"

sed -i '' 's/if (is_mac)/if (is_apple)/g' "$VULKAN_LOADER_GN"
if ! grep -q 'CoreFoundation' "$VULKAN_LOADER_GN"; then
    echo "CoreFoundation not found in BUILD.gn, adding manually..."
    sed -i '' '/shared_library("libvulkan")/{
n
a\
  if (is_ios) { frameworks = [ "CoreFoundation.framework" ] }
}' "$VULKAN_LOADER_GN"
fi

echo "After patch - is_apple references:"
grep -n 'is_apple' "$VULKAN_LOADER_GN" || echo "(none)"
echo "After patch - CoreFoundation references:"
grep -n 'CoreFoundation' "$VULKAN_LOADER_GN" || echo "(none)"
echo "After patch - frameworks references:"
grep -n 'frameworks' "$VULKAN_LOADER_GN" || echo "(none)"

echo ""
echo "=== Patch 3: Vulkan renderer BUILD.gn - VulkanMac display for iOS ==="
echo "Before patch - is_mac in vulkan renderer:"
grep -rn 'is_mac' src/libANGLE/renderer/vulkan/BUILD.gn 2>/dev/null | head -20 || echo "(file not found)"
echo "Before patch - VulkanMac/DisplayVkMac references:"
grep -rn 'VulkanMac\|DisplayVkMac\|vulkan_mac' src/libANGLE/renderer/vulkan/BUILD.gn 2>/dev/null | head -20 || echo "(none)"

# Patch all BUILD.gn files: is_mac -> is_apple
find src/libANGLE/renderer/vulkan -name "BUILD.gn" -exec sed -i '' 's/if (is_mac)/if (is_apple)/g' {} \;
find src/libANGLE -maxdepth 1 -name "BUILD.gn" -exec sed -i '' 's/if (is_mac)/if (is_apple)/g' {} \;
find src -maxdepth 1 -name "BUILD.gn" -exec sed -i '' 's/if (is_mac)/if (is_apple)/g' {} \;

echo "After patch - is_apple in vulkan renderer:"
grep -rn 'is_apple' src/libANGLE/renderer/vulkan/BUILD.gn 2>/dev/null | head -20 || echo "(none)"
echo "After patch - VulkanMac/DisplayVkMac references:"
grep -rn 'VulkanMac\|DisplayVkMac\|vulkan_mac' src/libANGLE/renderer/vulkan/BUILD.gn 2>/dev/null | head -20 || echo "(none)"

echo ""
echo "=== Checking Display.cpp for VulkanMac references ==="
grep -n 'VulkanMac\|CreateVulkanMac\|IsVulkanMac' src/libANGLE/Display.cpp 2>/dev/null | head -10 || echo "(none)"

echo ""
echo "=== Listing vulkan/mac directory ==="
ls -la src/libANGLE/renderer/vulkan/mac/ 2>/dev/null || echo "(directory not found)"

echo ""
echo "=== All patches applied successfully ==="
