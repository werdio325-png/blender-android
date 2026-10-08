#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Step 07] Configuring CMake for Android ARM64..."
echo "===> Resolving dependency CMake directories..."
if [ -d "${SYSROOT_DIR}/usr/lib64" ]; then
    cp -r "${SYSROOT_DIR}/usr/lib64/"* "${SYSROOT_DIR}/usr/lib/" || true
fi
IMATH_DIR=$(find "${SYSROOT_DIR}/usr" -name "ImathConfig.cmake" -exec dirname {} \; | head -n 1 || true)
OPENEXR_DIR=$(find "${SYSROOT_DIR}/usr" -name "OpenEXRConfig.cmake" -exec dirname {} \; | head -n 1 || true)
OCIO_DIR=$(find "${SYSROOT_DIR}/usr" -name "OpenColorIOConfig.cmake" -exec dirname {} \; | head -n 1 || true)
OIIO_DIR=$(find "${SYSROOT_DIR}/usr" -name "OpenImageIOConfig.cmake" -exec dirname {} \; | head -n 1 || true)
TBB_DIR=$(find "${SYSROOT_DIR}/usr" -name "TBBConfig.cmake" -exec dirname {} \; | head -n 1 || true)
SDL3_DIR=$(find "${SYSROOT_DIR}/usr" -name "SDL3Config.cmake" -exec dirname {} \; | head -n 1 || true)
PNG_LIB=$(find "${SYSROOT_DIR}/usr/lib" -name "libpng*.so" | head -n 1 || true)
if [ -n "${PNG_LIB}" ]; then
    cp -P "${PNG_LIB}" "${SYSROOT_DIR}/usr/lib/libpng.so" 2>/dev/null || true
    cp -P "${PNG_LIB}" "${SYSROOT_DIR}/usr/lib/libpng16.so" 2>/dev/null || true
fi

PYTHON_INC=$(find "${SYSROOT_DIR}/usr/include" -maxdepth 1 -name "python3*" 2>/dev/null | head -n 1 || true)
if [ -z "${PYTHON_INC}" ]; then
    PYTHON_INC="${SYSROOT_DIR}/usr/include/python3.13"
fi
PYTHON_LIB=$(find "${SYSROOT_DIR}/usr/lib" -maxdepth 1 -name "libpython3*.so" 2>/dev/null | head -n 1 || true)
if [ -z "${PYTHON_LIB}" ]; then
    PYTHON_LIB="${SYSROOT_DIR}/usr/lib/libpython3.13.so"
fi
HOST_PYTHON=$(command -v python3.13 || command -v python3)
echo "Using Python include: ${PYTHON_INC}, library: ${PYTHON_LIB}, host executable: ${HOST_PYTHON}"

echo "===> Configuring Blender for Android ARM64..."
CCACHE_BIN=$(command -v ccache || true)
CCACHE_ARGS=()
if [ -n "${CCACHE_BIN}" ]; then
    echo "Using ccache: ${CCACHE_BIN}"
    CCACHE_ARGS=(
        -DCMAKE_C_COMPILER_LAUNCHER="${CCACHE_BIN}"
        -DCMAKE_CXX_COMPILER_LAUNCHER="${CCACHE_BIN}"
    )
fi

cmake -B "${BLENDER_BUILD_DIR}" -S "${BLENDER_SRC}" -G Ninja \
    "${CCACHE_ARGS[@]}" \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_PREFIX_PATH="${SYSROOT_DIR}/usr" \
    -DCMAKE_FIND_ROOT_PATH="${SYSROOT_DIR}/usr;${TOOLCHAIN}/sysroot" \
    -DWITH_CROSSCOMPILED_TOOLS=ON \
    -DCROSSCOMPILE_TOOLDIR="${HOST_TOOLS_DIR}/bin" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DWITH_INSTALL_PORTABLE=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-L${SYSROOT_DIR}/usr/lib -Wl,--undefined-version" \
    -DCMAKE_EXE_LINKER_FLAGS="-pie -L${SYSROOT_DIR}/usr/lib -Wl,--undefined-version" \
    -DWITH_VULKAN_BACKEND=ON \
    -DVulkan_INCLUDE_DIRS="${SYSROOT_DIR}/usr/include;${TOOLCHAIN}/sysroot/usr/include" \
    -DVulkan_LIBRARIES="${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL}/libvulkan.so" \
    -DSHADERC_ROOT_DIR="${SYSROOT_DIR}/usr" \
    -DSHADERC_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DSHADERC_INCLUDE_DIRS="${SYSROOT_DIR}/usr/include" \
    -DSHADERC_LIBRARY="${SYSROOT_DIR}/usr/lib/libshaderc.a" \
    -DSHADERC_LIBRARIES="${SYSROOT_DIR}/usr/lib/libshaderc.a" \
    -DShaderc_INCLUDE_DIRS="${SYSROOT_DIR}/usr/include" \
    -DShaderc_LIBRARIES="${SYSROOT_DIR}/usr/lib/libshaderc.a" \
    -DHAVE_BROTLI=TRUE \
    -DHAVE_BROTLI_INC="${SYSROOT_DIR}/usr/include/freetype2" \
    -DWITH_GHOST_SDL=ON \
    -DWITH_SDL=ON \
    -DSDL_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DSDL_LIBRARY="${SYSROOT_DIR}/usr/lib/libSDL3.so" \
    -DSDL3_DIR="${SDL3_DIR}" \
    -DWITH_GHOST_X11=OFF \
    -DWITH_GHOST_WAYLAND=OFF \
    -DWITH_X11=OFF \
    -DWITH_X11_XINPUT=OFF \
    -DWITH_X11_XF86VMODE=OFF \
    -DWITH_X11_XFIXES=OFF \
    -DWITH_X11_ALPHA=OFF \
    -DWITH_OPENGL_BACKEND=OFF \
    -DWITH_PYTHON=ON \
    -DPYTHON_VERSION="3.13" \
    -DPYTHON_EXECUTABLE="${HOST_PYTHON}" \
    -DPYTHON_INCLUDE_DIR="${PYTHON_INC}" \
    -DPYTHON_INCLUDE_DIRS="${PYTHON_INC}" \
    -DPYTHON_LIBRARY="${PYTHON_LIB}" \
    -DPYTHON_LIBRARIES="${PYTHON_LIB}" \
    -DTBB_DIR="${TBB_DIR}" \
    -DTBB_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DTBB_LIBRARY="${SYSROOT_DIR}/usr/lib/libtbb.so" \
    -DWITH_TBB_MALLOC_PROXY=OFF \
    -DFREETYPE_INCLUDE_DIRS="${SYSROOT_DIR}/usr/include/freetype2" \
    -DFREETYPE_LIBRARY="${SYSROOT_DIR}/usr/lib/libfreetype.so" \
    -DJPEG_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DJPEG_LIBRARY="${SYSROOT_DIR}/usr/lib/libjpeg.so" \
    -DPNG_PNG_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DPNG_LIBRARY="${PNG_LIB}" \
    -DZSTD_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DZSTD_LIBRARY="${SYSROOT_DIR}/usr/lib/libzstd.so" \
    -DEPOXY_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DEPOXY_LIBRARY="${SYSROOT_DIR}/usr/lib/libepoxy.so" \
    -Dfmt_DIR="${SYSROOT_DIR}/usr/lib/cmake/fmt" \
    -DEigen3_DIR="${SYSROOT_DIR}/usr/lib/cmake/eigen3" \
    -DImath_DIR="${IMATH_DIR}" \
    -DOpenEXR_DIR="${OPENEXR_DIR}" \
    -DWITH_OPENEXR=ON \
    -DWITH_IMAGE_OPENEXR=ON \
    -DOPENEXR_ROOT="${SYSROOT_DIR}/usr" \
    -DIMATH_ROOT="${SYSROOT_DIR}/usr" \
    -DOpenColorIO_DIR="${OCIO_DIR}" \
    -DWITH_OPENCOLORIO=ON \
    -DOpenImageIO_DIR="${OIIO_DIR}" \
    -DWITH_OPENIMAGEIO=ON \
    -DSSE2NEON_ROOT_DIR="${SYSROOT_DIR}/usr" \
    -DSSE2NEON_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DWITH_GMP=OFF \
    -DWITH_MANIFOLD=OFF \
    -DWITH_BOOST=OFF \
    -DWITH_LLVM=OFF \
    -DWITH_MEM_JEMALLOC=OFF \
    -DWITH_CYCLES=OFF \
    -DWITH_OPENSUBDIV=OFF \
    -DWITH_OPENVDB=OFF \
    -DWITH_ALEMBIC=OFF \
    -DWITH_USD=OFF \
    -DWITH_HYDRA=OFF \
    -DWITH_CODEC_FFMPEG=OFF \
    -DWITH_CODEC_SNDFILE=OFF \
    -DWITH_DRACO=OFF \
    -DWITH_MESHOPTIMIZER=OFF \
    -DWITH_LIBMV=OFF \
    -DWITH_IMAGE_OPENJPEG=OFF \
    -DWITH_IMAGE_CINEON=OFF \
    -DWITH_IMAGE_HDR=OFF \
    -DWITH_IMAGE_DDS=OFF \
    -DWITH_IMAGE_WEBP=OFF \
    -DWITH_AUDASPACE=OFF \
    -DWITH_SYSTEM_AUDASPACE=OFF \
    -DWITH_INTERNATIONAL=OFF \
    -DHAVE_EXECINFO_H=OFF \
    -DWITH_FFTW3=OFF \
    -DWITH_MOD_OCEANSIM=OFF \
    -DWITH_MOD_FLUID=OFF \
    -DWITH_BUILDINFO=OFF

