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
sed -i '' 's/if (is_mac)/if (is_apple)/g' "$VULKAN_BACKEND_GNI"
echo "Done: vulkan_backend.gni patched"

echo ""
echo "=== Patch 4: Fix macOS-specific headers in VulkanMac backend for iOS ==="

# WindowSurfaceVkMac.h includes <Cocoa/Cocoa.h> which doesn't exist on iOS
# Replace with UIKit for iOS, keep Cocoa for macOS
MAC_DIR="src/libANGLE/renderer/vulkan/mac"

echo "Patching WindowSurfaceVkMac.h (Cocoa -> TARGET_OS_IPHONE conditional)..."
sed -i '' 's|#include <Cocoa/Cocoa.h>|#include <TargetConditionals.h>\
#if TARGET_OS_IPHONE\
#include <UIKit/UIKit.h>\
#else\
#include <Cocoa/Cocoa.h>\
#endif|' "$MAC_DIR/WindowSurfaceVkMac.h"

echo "Patching DisplayVkMac.mm (Cocoa -> TARGET_OS_IPHONE conditional)..."
# DisplayVkMac.mm includes WindowSurfaceVkMac.h which pulls in Cocoa
# Check if it directly includes Cocoa too
if grep -q '#include <Cocoa/Cocoa.h>' "$MAC_DIR/DisplayVkMac.mm"; then
    sed -i '' 's|#include <Cocoa/Cocoa.h>|#include <TargetConditionals.h>\
#if TARGET_OS_IPHONE\
#include <UIKit/UIKit.h>\
#else\
#include <Cocoa/Cocoa.h>\
#endif|' "$MAC_DIR/DisplayVkMac.mm"
fi

echo "Patching IOSurfaceSurfaceVkMac.mm (IOSurface header)..."
# IOSurface/IOSurface.h exists on iOS but in a different location
# On iOS, use IOSurface/IOSurfaceRef.h or the framework directly
if grep -q '#include <IOSurface/IOSurface.h>' "$MAC_DIR/IOSurfaceSurfaceVkMac.mm"; then
    sed -i '' 's|#include <IOSurface/IOSurface.h>|#include <TargetConditionals.h>\
#if TARGET_OS_IPHONE\
#import <IOSurface/IOSurfaceRef.h>\
#else\
#include <IOSurface/IOSurface.h>\
#endif|' "$MAC_DIR/IOSurfaceSurfaceVkMac.mm"
fi

# Also check for any NSWindow references that need UIWindow on iOS
echo ""
echo "--- Checking for other macOS-only APIs in mac backend ---"
grep -rn 'NSWindow\|NSView\|NSScreen\|NSApplication\|NSOpenGLContext' "$MAC_DIR/" 2>/dev/null | head -20 || echo "(none found)"
grep -rn 'Cocoa\|AppKit' "$MAC_DIR/" 2>/dev/null | head -20 || echo "(none found)"

echo ""
echo "--- Show patched headers (first 20 lines) ---"
echo "WindowSurfaceVkMac.h:"
head -20 "$MAC_DIR/WindowSurfaceVkMac.h"
echo ""
echo "DisplayVkMac.mm (first 20 lines):"
head -20 "$MAC_DIR/DisplayVkMac.mm"
echo ""
echo "IOSurfaceSurfaceVkMac.mm (first 25 lines):"
head -25 "$MAC_DIR/IOSurfaceSurfaceVkMac.mm"

echo ""
echo "=== All patches applied ==="
