#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> Unpacking dependencies sysroot..."
if [ -f "blender-deps-android-arm64.tar.gz" ]; then
    mkdir -p "${SYSROOT_DIR}"
    tar -xzf blender-deps-android-arm64.tar.gz -C "${SYSROOT_DIR}"
fi

echo "===> Ensuring Imath and OpenEXR headers are directly available in sysroot include..."
mkdir -p "${SYSROOT_DIR}/usr/include/Imath" "${SYSROOT_DIR}/usr/include/OpenEXR"
cp -r "${SYSROOT_DIR}/usr/include/Imath/"* "${SYSROOT_DIR}/usr/include/" 2>/dev/null || true
cp -r "${SYSROOT_DIR}/usr/include/OpenEXR/"* "${SYSROOT_DIR}/usr/include/" 2>/dev/null || true
mkdir -p "${TOOLCHAIN}/sysroot/usr/include/Imath" "${TOOLCHAIN}/sysroot/usr/include/OpenEXR"
cp -r "${SYSROOT_DIR}/usr/include/Imath" "${TOOLCHAIN}/sysroot/usr/include/" 2>/dev/null || true
cp -r "${SYSROOT_DIR}/usr/include/OpenEXR" "${TOOLCHAIN}/sysroot/usr/include/" 2>/dev/null || true
cp -r "${SYSROOT_DIR}/usr/include/Imath/"* "${TOOLCHAIN}/sysroot/usr/include/" 2>/dev/null || true
cp -r "${SYSROOT_DIR}/usr/include/OpenEXR/"* "${TOOLCHAIN}/sysroot/usr/include/" 2>/dev/null || true

echo "===> Ensuring Vulkan & Shaderc pkg-config..."
mkdir -p "${SYSROOT_DIR}/usr/lib/pkgconfig" "${SYSROOT_DIR}/usr/share/pkgconfig"
cat << VEOF > "${SYSROOT_DIR}/usr/lib/pkgconfig/vulkan.pc"
prefix=${SYSROOT_DIR}/usr
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Vulkan-Loader
Description: Vulkan Loader for Android NDK
Version: 1.4.304
Libs: -L${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL} -lvulkan
Cflags: -I${TOOLCHAIN}/sysroot/usr/include
VEOF

cat << SEOF > "${SYSROOT_DIR}/usr/lib/pkgconfig/shaderc.pc"
prefix=${SYSROOT_DIR}/usr
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: shaderc
Description: Shaderc library for Android NDK
Version: 2024.1
Libs: -L\${libdir} -lshaderc
Cflags: -I\${includedir}
SEOF

