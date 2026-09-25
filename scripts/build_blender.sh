#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(pwd)"
SYSROOT_DIR="${BASE_DIR}/sysroot-android-arm64"
BUILD_TMP="${BASE_DIR}/build-tmp"
BLENDER_SRC="${BUILD_TMP}/blender"
API_LEVEL="29"

if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    if [ -d "/usr/local/lib/android/sdk/ndk/27.3.13750724" ]; then
        export ANDROID_NDK_ROOT="/usr/local/lib/android/sdk/ndk/27.3.13750724"
    elif [ -d "/usr/local/lib/android/sdk/ndk/26.3.11579264" ]; then
        export ANDROID_NDK_ROOT="/usr/local/lib/android/sdk/ndk/26.3.11579264"
    fi
fi

TOOLCHAIN="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64"
CMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake"

echo "===> Unpacking dependencies sysroot..."
if [ -f "blender-deps-android-arm64.tar.gz" ]; then
    mkdir -p "${SYSROOT_DIR}"
    tar -xzf blender-deps-android-arm64.tar.gz -C "${SYSROOT_DIR}"
fi

echo "===> Ensuring Vulkan & Shaderc pkg-config..."
mkdir -p "${SYSROOT_DIR}/usr/lib/pkgconfig" "${SYSROOT_DIR}/usr/share/pkgconfig"
cat << VEOF > "${SYSROOT_DIR}/usr/lib/pkgconfig/vulkan.pc"
prefix=${SYSROOT_DIR}/usr
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Vulkan-Loader
Description: Vulkan Loader for Android NDK
Version: 1.3.290
Libs: -L${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL} -lvulkan
Cflags: -I${TOOLCHAIN}/sysroot/usr/include
VEOF

if [ ! -f "${SYSROOT_DIR}/usr/lib/pkgconfig/shaderc.pc" ]; then
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
fi

export PKG_CONFIG_PATH="${SYSROOT_DIR}/usr/lib/pkgconfig:${SYSROOT_DIR}/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"

echo "===> Cloning Blender source (v5.2.0)..."
mkdir -p "${BUILD_TMP}"
cd "${BUILD_TMP}"
if [ ! -d "blender" ]; then
    git clone --depth 1 --branch v5.2.0 https://projects.blender.org/blender/blender.git
fi

echo "===> Patching Blender CMake for Android ARM64..."
# Bypass FreeType Brotli check (Brotli only used for woff web fonts)
sed -i 's/message(FATAL_ERROR "Freetype needs to be compiled with brotli support!")/# &/' "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake"
# Remove -lutil for Android (Bionic does not have libutil)
sed -i 's/-lutil//g' "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake"
# Remove -no-pie for Android (Android Bionic linker strictly requires PIE executables)
sed -i 's/-no-pie//g' "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake"

# Build blender as a shared library for Android NativeActivity
sed -i 's/add_executable(blender ${EXETYPE} ${SRC})/add_library(blender SHARED ${SRC})/' "${BLENDER_SRC}/source/creator/CMakeLists.txt"
# Bypass oiiotool check for cross-compilation
sed -i 's/get_target_property(OPENIMAGEIO_TOOL OpenImageIO::oiiotool LOCATION)/# &/' "${BLENDER_SRC}/build_files/cmake/platform/dependency_targets.cmake"
# Disable TBB malloc proxy checks in platform_unix.cmake
sed -i 's/if(WITH_TBB_MALLOC_PROXY)/if(FALSE)/' "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake"

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

echo "===> Setting up Android Bionic environment for QEMU host tools..."
if [ -f "${BASE_DIR}/bionic-arm64.tar.gz" ]; then
    sudo tar -xzf "${BASE_DIR}/bionic-arm64.tar.gz" -C /
fi
if [ -d /system/lib64 ]; then
    sudo cp -P ${SYSROOT_DIR}/usr/lib/*.so* /system/lib64/ 2>/dev/null || true
    sudo cp -P ${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/*.so /system/lib64/ 2>/dev/null || true
    sudo cp -P ${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL}/*.so /system/lib64/ 2>/dev/null || true
fi
sudo chmod -R 755 /system 2>/dev/null || true
export QEMU_LD_PREFIX="/"
export LD_LIBRARY_PATH="/system/lib64:${SYSROOT_DIR}/usr/lib:${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL}:${LD_LIBRARY_PATH:-}"
export QEMU_SET_ENV="LD_LIBRARY_PATH=/system/lib64:${SYSROOT_DIR}/usr/lib:${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL}"

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

echo "===> Configuring Blender for Android ARM64..."
cmake -B build-blender -S blender -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_PREFIX_PATH="${SYSROOT_DIR}/usr" \
    -DCMAKE_FIND_ROOT_PATH="${SYSROOT_DIR}/usr;${TOOLCHAIN}/sysroot" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DWITH_INSTALL_PORTABLE=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version" \
    -DCMAKE_EXE_LINKER_FLAGS="-pie -Wl,--undefined-version" \
    -DWITH_VULKAN_BACKEND=ON \
    -DVulkan_INCLUDE_DIRS="${TOOLCHAIN}/sysroot/usr/include" \
    -DVulkan_LIBRARIES="${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL}/libvulkan.so" \
    -DShaderc_INCLUDE_DIRS="${SYSROOT_DIR}/usr/include" \
    -DShaderc_LIBRARIES="${SYSROOT_DIR}/usr/lib/libshaderc.so" \
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
    -DPYTHON_INCLUDE_DIR="${SYSROOT_DIR}/usr/include/python3.12" \
    -DPYTHON_LIBRARY="${SYSROOT_DIR}/usr/lib/libpython3.12.so" \
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
    -DOpenColorIO_DIR="${OCIO_DIR}" \
    -DOpenImageIO_DIR="${OIIO_DIR}" \
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
    -DWITH_BUILDINFO=OFF

echo "===> Building Blender core..."
ninja -C build-blender -j$(nproc)

echo "===> Packaging into standalone APK..."
APK_DIR="${BUILD_TMP}/apk-build"
rm -rf "${APK_DIR}"
mkdir -p "${APK_DIR}/lib/arm64-v8a" "${APK_DIR}/assets/datafiles" "${APK_DIR}/assets/scripts"

# Copy libraries
cp -P ${SYSROOT_DIR}/usr/lib/*.so* "${APK_DIR}/lib/arm64-v8a/" || true
cp -P ${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so "${APK_DIR}/lib/arm64-v8a/" 2>/dev/null || true
find "${APK_DIR}/lib/arm64-v8a" -type l -exec cp --remove-destination "$(readlink -f {})" {} \; 2>/dev/null || true

# Copy Blender shared libs and main binary
find build-blender/lib -name "*.so*" -exec cp {} "${APK_DIR}/lib/arm64-v8a/" \; 2>/dev/null || true
find build-blender/bin -name "*.so*" -exec cp {} "${APK_DIR}/lib/arm64-v8a/" \; 2>/dev/null || true

if [ -f "build-blender/bin/blender" ]; then
    cp build-blender/bin/blender "${APK_DIR}/lib/arm64-v8a/libmain.so"
elif [ -f "build-blender/bin/libblender.so" ]; then
    cp build-blender/bin/libblender.so "${APK_DIR}/lib/arm64-v8a/libmain.so"
elif [ -f "build-blender/lib/libblender.so" ]; then
    cp build-blender/lib/libblender.so "${APK_DIR}/lib/arm64-v8a/libmain.so"
else
    MAIN_LIB=$(find build-blender -name "libblender.so" -o -name "blender" | head -n 1)
    if [ -n "${MAIN_LIB}" ]; then
        cp "${MAIN_LIB}" "${APK_DIR}/lib/arm64-v8a/libmain.so"
    fi
fi

# Copy assets
cp -r ${BLENDER_SRC}/release/datafiles/* "${APK_DIR}/assets/datafiles/" || true
cp -r ${BLENDER_SRC}/release/scripts/* "${APK_DIR}/assets/scripts/" || true

# Assemble APK using android SDK build tools
AAPT2=$(find /usr/local/lib/android/sdk/build-tools -name aapt2 | head -n 1)
ANDROID_JAR=$(find /usr/local/lib/android/sdk/platforms -name android.jar | head -n 1)
ZIPALIGN=$(find /usr/local/lib/android/sdk/build-tools -name zipalign | head -n 1)
APKSIGNER=$(find /usr/local/lib/android/sdk/build-tools -name apksigner | head -n 1)

$AAPT2 link -o "${BUILD_TMP}/unaligned.apk" \
    -I "$ANDROID_JAR" \
    --manifest "${BASE_DIR}/android/app/src/main/AndroidManifest.xml" \
    -A "${APK_DIR}/assets" \
    --auto-add-overlay

cd "${APK_DIR}"
zip -u -r "${BUILD_TMP}/unaligned.apk" lib/

$ZIPALIGN -f -p 4 "${BUILD_TMP}/unaligned.apk" "${BASE_DIR}/Blender-Android-arm64.apk"

# Generate temporary debug keystore for signing
keytool -genkeypair -v -keystore "${BUILD_TMP}/debug.keystore" \
    -alias androiddebugkey -keypass android -storepass android \
    -dname "CN=Android Debug,O=Android,C=US" -validity 10000 -keyalg RSA -keysize 2048 2>/dev/null || true

$APKSIGNER sign --ks "${BUILD_TMP}/debug.keystore" \
    --ks-pass pass:android \
    --key-pass pass:android \
    "${BASE_DIR}/Blender-Android-arm64.apk"

echo "===> Done! Successfully created Blender-Android-arm64.apk"
