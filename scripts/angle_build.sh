#!/bin/bash
set -e

export BUILD_DIR="$(pwd)/build"
export PREFIX="$(pwd)/sysroot"
export PATH="$(realpath depot_tools.git):$PATH"
mkdir -p "$PREFIX/lib/vulkan"
cd "$BUILD_DIR/angle"

echo "=== Configuring ANGLE (GN gen) ==="
gn gen out/Release --args='target_os="ios" target_cpu="arm64" target_environment="device" ios_enable_code_signing=false is_debug=false angle_enable_vulkan=true angle_shared_libvulkan=true angle_enable_swiftshader=false angle_enable_metal=false angle_enable_gl=false angle_enable_vulkan_validation_layers=false angle_build_tests=false angle_enable_dawn=false'

echo ""
echo "=== Building ANGLE (ninja) ==="
ninja -C out/Release libGLESv2 libEGL

echo ""
echo "=== Installing libraries ==="
cp out/Release/libGLESv2.dylib "$PREFIX/lib/vulkan/"
cp out/Release/libEGL.dylib "$PREFIX/lib/vulkan/"
if [ -f out/Release/libvulkan.dylib ]; then
    cp out/Release/libvulkan.dylib "$PREFIX/lib/vulkan/"
fi
ls -la "$PREFIX/lib/vulkan/"

echo ""
echo "=== Done! ==="
