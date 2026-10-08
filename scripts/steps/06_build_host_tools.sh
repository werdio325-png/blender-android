#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Step 06] Building native host tools (makesdna, makesrna, datatoc, shader_tool)..."
echo "===> Ensuring OpenImageIO namespace compatibility for Blender..."
if [ -f "${SYSROOT_DIR}/usr/include/OpenImageIO/oiioversion.h" ]; then
    sed -i 's/namespace OIIO = \([a-zA-Z0-9_]*\);/&\nnamespace OpenImageIO = \1;/' "${SYSROOT_DIR}/usr/include/OpenImageIO/oiioversion.h"
fi
if [ -f "${SYSROOT_DIR}/usr/include/OpenImageIO/ustring.h" ]; then
    sed -i '/namespace OpenImageIO = OIIO;/d' "${SYSROOT_DIR}/usr/include/OpenImageIO/ustring.h"
fi

echo "===> Ensuring dummy libutil for Android sysroot..."
${TOOLCHAIN}/bin/llvm-ar cr "${SYSROOT_DIR}/usr/lib/libutil.a" 2>/dev/null || true
echo "INPUT()" > "${SYSROOT_DIR}/usr/lib/libutil.so"

echo "===> Ensuring sse2neon header..."
mkdir -p "${SYSROOT_DIR}/usr/include/sse2neon"
if [ -f "${SYSROOT_DIR}/usr/include/sse2neon.h" ]; then
    cp -f "${SYSROOT_DIR}/usr/include/sse2neon.h" "${SYSROOT_DIR}/usr/include/sse2neon/" 2>/dev/null || true
fi
export SSE2NEON_ROOT_DIR="${SYSROOT_DIR}/usr"
export SSE2NEON_INCLUDE_DIR="${SYSROOT_DIR}/usr/include"

echo "===> Ensuring modern Vulkan-Headers (1.4+ / main) for Android NDK and sysroot..."
VK_DIR="${BUILD_TMP}/vulkan-headers"
rm -rf "${VK_DIR}"
mkdir -p "${VK_DIR}"
wget -qO- "https://codeload.github.com/KhronosGroup/Vulkan-Headers/tar.gz/refs/heads/main" | tar -xz -C "${VK_DIR}" --strip-components=1 || \
wget -qO- "https://codeload.github.com/KhronosGroup/Vulkan-Headers/tar.gz/refs/tags/vulkan-sdk-1.4.304.0" | tar -xz -C "${VK_DIR}" --strip-components=1
mkdir -p "${SYSROOT_DIR}/usr/include" "${TOOLCHAIN}/sysroot/usr/include"
rm -rf "${SYSROOT_DIR}/usr/include/vulkan" "${TOOLCHAIN}/sysroot/usr/include/vulkan"
cp -r "${VK_DIR}/include/vulkan" "${SYSROOT_DIR}/usr/include/"
cp -r "${VK_DIR}/include/vulkan" "${TOOLCHAIN}/sysroot/usr/include/"
cp -r "${VK_DIR}/include/vk_video" "${SYSROOT_DIR}/usr/include/" 2>/dev/null || true
cp -r "${VK_DIR}/include/vk_video" "${TOOLCHAIN}/sysroot/usr/include/" 2>/dev/null || true

echo "===> Detecting C/C++ compiler for native host tools (GCC >= 14 or Clang >= 17)..."
HOST_CC=""
HOST_CXX=""
for c in clang-18 clang-17 clang gcc-14; do
    if command -v "$c" >/dev/null 2>&1; then
        HOST_CC="$c"
        HOST_CXX="${c/clang/clang++}"
        HOST_CXX="${HOST_CXX/gcc/g++}"
        break
    fi
done
if [ -z "${HOST_CC}" ]; then
    HOST_CC="gcc-14"
    HOST_CXX="g++-14"
fi
echo "Using host compilers: CC=${HOST_CC}, CXX=${HOST_CXX}"

echo "===> Ensuring OpenImageIO, Imath, and OpenEXR headers are available for host tools..."
sudo cp -r "${SYSROOT_DIR}/usr/include/OpenImageIO" /usr/local/include/ 2>/dev/null || true
sudo cp -r "${SYSROOT_DIR}/usr/include/Imath" /usr/local/include/ 2>/dev/null || true
sudo cp -r "${SYSROOT_DIR}/usr/include/Imath/"* /usr/local/include/ 2>/dev/null || true
sudo cp -r "${SYSROOT_DIR}/usr/include/OpenEXR" /usr/local/include/ 2>/dev/null || true
sudo cp -r "${SYSROOT_DIR}/usr/include/OpenEXR/"* /usr/local/include/ 2>/dev/null || true

echo "===> Building native host code generators (datatoc, shader_tool, makesdna, makesrna)..." 
HOST_TOOLS_DIR="${BUILD_TMP}/build-host-tools"
mkdir -p "${HOST_TOOLS_DIR}"
cmake -B "${HOST_TOOLS_DIR}" -S "${BLENDER_SRC}" -G Ninja \
    -DCMAKE_C_COMPILER="${HOST_CC}" \
    -DCMAKE_CXX_COMPILER="${HOST_CXX}" \
    -DCMAKE_C_FLAGS="-I${SYSROOT_DIR}/usr/include" \
    -DCMAKE_CXX_FLAGS="-I${SYSROOT_DIR}/usr/include" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_CROSSCOMPILED_TOOLS=OFF \
    -DWITH_HEADLESS=ON \
    -DWITH_CYCLES=OFF \
    -DWITH_AUDASPACE=OFF \
    -DWITH_PYTHON=OFF \
    -DWITH_INTERNATIONAL=OFF \
    -DWITH_OPENIMAGEIO=OFF \
    -DWITH_OPENCOLORIO=OFF \
    -DWITH_OPENEXR=OFF \
    -DWITH_IMAGE_OPENEXR=OFF \
    -DWITH_OPENVDB=OFF \
    -DWITH_ALEMBIC=OFF \
    -DWITH_USD=OFF \
    -DWITH_DRACO=OFF \
    -DWITH_MATERIALX=OFF \
    -DWITH_VULKAN_BACKEND=OFF \
    -DWITH_OPENGL_BACKEND=OFF \
    -DWITH_SDL=OFF \
    -DWITH_GHOST_SDL=OFF \
    -DWITH_GHOST_X11=OFF \
    -DWITH_GHOST_WAYLAND=OFF \
    -DWITH_TBB=OFF \
    -DWITH_OPENMP=OFF \
    -DWITH_LLVM=OFF \
    -DWITH_FFMPEG=OFF \
    -DWITH_IMAGE_OPENJPEG=OFF \
    -DWITH_IMAGE_TIFF=OFF \
    -DWITH_IMAGE_DDS=OFF \
    -DWITH_IMAGE_CINEON=OFF \
    -DWITH_IMAGE_HDR=OFF \
    -DWITH_IMAGE_WEBP=OFF \
    -DWITH_HARFBUZZ=OFF \
    -DWITH_FREETYPE=OFF \
    -DWITH_FRIBIDI=OFF \
    -DWITH_GMP=OFF \
    -DWITH_PUGIXML=OFF \
    -DWITH_LIBMV=OFF \
    -DWITH_MESHOPTIMIZER=OFF \
    -DWITH_FFTW3=OFF \
    -DWITH_MOD_OCEANSIM=OFF \
    -DWITH_MOD_FLUID=OFF \
    -DWITH_SYSTEM_FREETYPE=ON \
    -DHAVE_BROTLI=TRUE \
    -DHAVE_BROTLI_INC="/usr/include/freetype2" \
    -DWITH_SYSTEM_EIGEN3=ON

ninja -C "${HOST_TOOLS_DIR}" datatoc shader_tool makesdna makesrna
ls -la "${HOST_TOOLS_DIR}/bin"

