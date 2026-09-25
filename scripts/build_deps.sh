#!/usr/bin/env bash
set -euo pipefail

# Configuration
NDK_VERSION="r26d"
API_LEVEL="29"
ARCH="aarch64"
TARGET_TRIPLE="aarch64-linux-android"
BASE_DIR="$(pwd)"
SYSROOT_DIR="${BASE_DIR}/sysroot-android-arm64"
BUILD_TMP="${BASE_DIR}/build-tmp"

mkdir -p "${SYSROOT_DIR}/usr/include" "${SYSROOT_DIR}/usr/lib" "${SYSROOT_DIR}/usr/lib/pkgconfig" "${SYSROOT_DIR}/usr/share" "${BUILD_TMP}"

echo "===> Checking Android NDK..."
if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    if [ -d "/usr/local/lib/android/sdk/ndk/27.3.13750724" ]; then
        export ANDROID_NDK_ROOT="/usr/local/lib/android/sdk/ndk/27.3.13750724"
    elif [ -d "/usr/local/lib/android/sdk/ndk/26.3.11579264" ]; then
        export ANDROID_NDK_ROOT="/usr/local/lib/android/sdk/ndk/26.3.11579264"
    else
        echo "Downloading Android NDK ${NDK_VERSION}..."
        wget -q "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" -O ndk.zip
        unzip -q ndk.zip -d "${BUILD_TMP}"
        export ANDROID_NDK_ROOT="${BUILD_TMP}/android-ndk-${NDK_VERSION}"
    fi
fi

echo "Using Android NDK at: ${ANDROID_NDK_ROOT}"
TOOLCHAIN="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64"
export CC="${TOOLCHAIN}/bin/${TARGET_TRIPLE}${API_LEVEL}-clang"
export CXX="${TOOLCHAIN}/bin/${TARGET_TRIPLE}${API_LEVEL}-clang++"
export AR="${TOOLCHAIN}/bin/llvm-ar"
export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
export READELF="${TOOLCHAIN}/bin/llvm-readelf"
export CFLAGS="-fPIC -ftls-model=global-dynamic"
export CXXFLAGS="-fPIC -ftls-model=global-dynamic"
export LDFLAGS="-fPIC"
export CMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake"
export PKG_CONFIG_PATH="${SYSROOT_DIR}/usr/lib/pkgconfig:${SYSROOT_DIR}/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"

echo "===> Building mimalloc (Fast memory allocator)..."
cd "${BUILD_TMP}"
if [ ! -d "mimalloc" ]; then
    git clone --depth 1 https://github.com/microsoft/mimalloc.git
fi
cmake -B build-mimalloc -S mimalloc -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DMI_BUILD_TESTS=OFF \
    -DMI_BUILD_SHARED=ON
ninja -C build-mimalloc install

echo "===> Building oneTBB (Thread Building Blocks)..."
cd "${BUILD_TMP}"
if [ ! -d "oneTBB" ]; then
    git clone --depth 1 https://github.com/oneapi-src/oneTBB.git
fi
cmake -B build-onetbb -S oneTBB -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DTBB_TEST=OFF \
    -DTBBMALLOC_BUILD=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"
ninja -C build-onetbb install

echo "===> Building fmt (Formatting Library)..."
cd "${BUILD_TMP}"
if [ ! -d "fmt" ]; then
    git clone --depth 1 https://github.com/fmtlib/fmt.git
fi
cmake -B build-fmt -S fmt -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DFMT_TEST=OFF \
    -DBUILD_SHARED_LIBS=ON
ninja -C build-fmt install

echo "===> Building zstd (Compression Library)..."
cd "${BUILD_TMP}"
if [ ! -d "zstd" ]; then
    git clone --depth 1 https://github.com/facebook/zstd.git
fi
cmake -B build-zstd -S zstd/build/cmake -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DZSTD_BUILD_PROGRAMS=OFF \
    -DZSTD_BUILD_TESTS=OFF \
    -DZSTD_BUILD_SHARED=ON
ninja -C build-zstd install

echo "===> Building libjpeg-turbo..."
cd "${BUILD_TMP}"
if [ ! -d "libjpeg-turbo" ]; then
    git clone --depth 1 https://github.com/libjpeg-turbo/libjpeg-turbo.git
fi
cmake -B build-jpeg -S libjpeg-turbo -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DWITH_SIMD=OFF \
    -DENABLE_SHARED=ON
ninja -C build-jpeg install

echo "===> Building libpng..."
cd "${BUILD_TMP}"
if [ ! -d "libpng" ]; then
    git clone --depth 1 https://github.com/pnggroup/libpng.git
fi
cmake -B build-png -S libpng -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DPNG_SHARED=ON \
    -DPNG_TESTS=OFF
ninja -C build-png install

echo "===> Building libepoxy..."
cd "${BUILD_TMP}"
if [ ! -d "libepoxy" ]; then
    git clone --depth 1 https://github.com/anholt/libepoxy.git
fi
cat << MEOF > cross_android_epoxy.txt
[binaries]
c = '${CC}'
cpp = '${CXX}'
ar = '${AR}'
strip = '${TOOLCHAIN}/bin/llvm-strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'arm64-v8a'
endian = 'little'
MEOF
rm -rf build-epoxy
meson setup build-epoxy libepoxy \
    --cross-file cross_android_epoxy.txt \
    --prefix="${SYSROOT_DIR}/usr" \
    -Degl=yes -Dglx=no -Dx11=false -Dtests=false -Ddocs=false \
    --default-library=shared
ninja -C build-epoxy install

echo "===> Installing and building shaderc (SPIR-V shader compiler)..."
SHADERC_NDK_DIR="${ANDROID_NDK_ROOT}/sources/third_party/shaderc"
SHADERC_BUILD_DIR="${BUILD_TMP}/shaderc-build"
mkdir -p "${SHADERC_BUILD_DIR}/jni"

cat << 'AMK_EOF' > "${SHADERC_BUILD_DIR}/jni/Android.mk"
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := shaderc
LOCAL_WHOLE_STATIC_LIBRARIES := shaderc
include $(BUILD_SHARED_LIBRARY)
$(call import-module,third_party/shaderc)
AMK_EOF

cat << 'APP_EOF' > "${SHADERC_BUILD_DIR}/jni/Application.mk"
APP_ABI := arm64-v8a
APP_PLATFORM := android-${API_LEVEL}
APP_STL := c++_shared
APP_EOF

"${ANDROID_NDK_ROOT}/ndk-build" -C "${SHADERC_BUILD_DIR}" \
    NDK_MODULE_PATH="${ANDROID_NDK_ROOT}/sources" \
    -j$(nproc) || true

mkdir -p "${SYSROOT_DIR}/usr/include" "${SYSROOT_DIR}/usr/lib" "${SYSROOT_DIR}/usr/lib/pkgconfig"
cp -r "${SHADERC_NDK_DIR}/include/"* "${SYSROOT_DIR}/usr/include/" || true
find "${SHADERC_BUILD_DIR}" -name "*.so" -exec cp {} "${SYSROOT_DIR}/usr/lib/" \; || true
find "${SHADERC_BUILD_DIR}" -name "*.a" -exec cp {} "${SYSROOT_DIR}/usr/lib/" \; || true
find "${SHADERC_NDK_DIR}" -name "*.a" -exec cp {} "${SYSROOT_DIR}/usr/lib/" \; || true

if [ ! -f "${SYSROOT_DIR}/usr/lib/libshaderc.so" ]; then
    SHADERC_A=$(find "${SYSROOT_DIR}/usr/lib" -name "libshaderc*.a" | head -n 1 || true)
    if [ -n "${SHADERC_A}" ]; then
        ${CXX} -shared -Wl,--whole-archive "${SHADERC_A}" -Wl,--no-whole-archive -o "${SYSROOT_DIR}/usr/lib/libshaderc.so" || true
    fi
fi

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

echo "===> Installing sse2neon.h..."
mkdir -p "${SYSROOT_DIR}/usr/include"
wget -qO "${SYSROOT_DIR}/usr/include/sse2neon.h" https://raw.githubusercontent.com/DLTcollab/sse2neon/master/sse2neon.h

echo "===> Installing Eigen3 headers..."
mkdir -p "${SYSROOT_DIR}/usr/include/eigen3" "${SYSROOT_DIR}/usr/lib/cmake/eigen3" "${SYSROOT_DIR}/usr/share/eigen3/cmake"
if [ -d "/usr/include/eigen3" ]; then
    cp -r /usr/include/eigen3/* "${SYSROOT_DIR}/usr/include/eigen3/"
    cp -r /usr/include/eigen3/* "${SYSROOT_DIR}/usr/include/" || true
fi
if [ -d "/usr/share/eigen3/cmake" ]; then
    cp -r /usr/share/eigen3/cmake/* "${SYSROOT_DIR}/usr/share/eigen3/cmake/" || true
    cp -r /usr/share/eigen3/cmake/* "${SYSROOT_DIR}/usr/lib/cmake/eigen3/" || true
elif [ -d "/usr/lib/cmake/eigen3" ]; then
    cp -r /usr/lib/cmake/eigen3/* "${SYSROOT_DIR}/usr/lib/cmake/eigen3/" || true
fi

echo "===> Building Imath..."
cd "${BUILD_TMP}"
if [ ! -d "Imath" ]; then
    git clone --depth 1 -b v3.1.11 https://github.com/AcademySoftwareFoundation/Imath.git
fi
cmake -B build-imath -S Imath -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF
ninja -C build-imath install

echo "===> Building OpenEXR..."
cd "${BUILD_TMP}"
if [ ! -d "openexr" ]; then
    git clone --depth 1 -b v3.2.4 https://github.com/AcademySoftwareFoundation/openexr.git
fi
cmake -B build-openexr -S openexr -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DCMAKE_PREFIX_PATH="${SYSROOT_DIR}/usr" \
    -DBUILD_SHARED_LIBS=ON \
    -DOPENEXR_INSTALL_TOOLS=OFF \
    -DBUILD_TESTING=OFF
ninja -C build-openexr install

echo "===> Building OpenColorIO..."
cd "${BUILD_TMP}"
if [ ! -d "OpenColorIO" ]; then
    git clone --depth 1 -b v2.3.2 https://github.com/AcademySoftwareFoundation/OpenColorIO.git
fi
cmake -B build-ocio -S OpenColorIO -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DCMAKE_PREFIX_PATH="${SYSROOT_DIR}/usr" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version" \
    -DBUILD_SHARED_LIBS=ON \
    -DOCIO_BUILD_APPS=OFF \
    -DOCIO_BUILD_TESTS=OFF \
    -DOCIO_BUILD_GPU_TESTS=OFF \
    -DOCIO_BUILD_PYTHON=OFF \
    -DOCIO_BUILD_DOCS=OFF \
    -DOCIO_INSTALL_EXT_PACKAGES=MISSING
ninja -C build-ocio install

echo "===> Building libtiff..."
cd "${BUILD_TMP}"
if [ ! -d "libtiff" ]; then
    git clone --depth 1 -b v4.6.0 https://gitlab.com/libtiff/libtiff.git
fi
cmake -B build-tiff -S libtiff -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DCMAKE_PREFIX_PATH="${SYSROOT_DIR}/usr" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version" \
    -DBUILD_SHARED_LIBS=ON \
    -Dtiff-tools=OFF \
    -Dtiff-tests=OFF \
    -Dtiff-docs=OFF
ninja -C build-tiff install

echo "===> Merging lib64 to lib if exists..."
if [ -d "${SYSROOT_DIR}/usr/lib64" ]; then
    cp -r "${SYSROOT_DIR}/usr/lib64/"* "${SYSROOT_DIR}/usr/lib/" || true
fi
IMATH_DIR=$(find "${SYSROOT_DIR}/usr" -name "ImathConfig.cmake" | head -n 1 | xargs -r dirname || true)
OPENEXR_DIR=$(find "${SYSROOT_DIR}/usr" -name "OpenEXRConfig.cmake" | head -n 1 | xargs -r dirname || true)
OCIO_DIR=$(find "${SYSROOT_DIR}/usr" -name "OpenColorIOConfig.cmake" | head -n 1 | xargs -r dirname || true)
JPEG_DIR=$(find "${SYSROOT_DIR}/usr" -name "*jpeg*Config.cmake" -o -name "*jpeg*-config.cmake" | head -n 1 | xargs -r dirname || true)
TIFF_DIR=$(find "${SYSROOT_DIR}/usr" -name "*tiff*Config.cmake" -o -name "*tiff*-config.cmake" | head -n 1 | xargs -r dirname || true)

echo "===> Installing robin-map..."
cd "${BUILD_TMP}"
if [ ! -d "robin-map" ]; then
    git clone --depth 1 https://github.com/Tessil/robin-map.git
fi
mkdir -p "${SYSROOT_DIR}/usr/include"
cp -r robin-map/include/* "${SYSROOT_DIR}/usr/include/"

echo "===> Building OpenImageIO (v3.0.4.0 without Boost)..."
cd "${BUILD_TMP}"
if [ ! -d "OpenImageIO" ]; then
    git clone --depth 1 -b v3.0.4.0 https://github.com/AcademySoftwareFoundation/OpenImageIO.git
fi
cmake -B build-oiio -S OpenImageIO -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DCMAKE_PREFIX_PATH="${SYSROOT_DIR}/usr;${IMATH_DIR};${OPENEXR_DIR};${OCIO_DIR};${JPEG_DIR};${TIFF_DIR}" \
    -DImath_DIR="${IMATH_DIR}" \
    -DOpenEXR_DIR="${OPENEXR_DIR}" \
    -DOpenColorIO_DIR="${OCIO_DIR}" \
    -Dlibjpeg-turbo_DIR="${JPEG_DIR}" \
    -Dlibjpeg-turbo_ROOT="${SYSROOT_DIR}/usr" \
    -DJPEG_ROOT="${SYSROOT_DIR}/usr" \
    -DJPEG_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DJPEG_LIBRARY="${SYSROOT_DIR}/usr/lib/libjpeg.so" \
    -DTIFF_DIR="${TIFF_DIR}" \
    -DTIFF_ROOT="${SYSROOT_DIR}/usr" \
    -DTIFF_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DTIFF_LIBRARY="${SYSROOT_DIR}/usr/lib/libtiff.so" \
    -DPNG_ROOT="${SYSROOT_DIR}/usr" \
    -DPNG_PNG_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DPNG_LIBRARY="${SYSROOT_DIR}/usr/lib/libpng16.so" \
    -DROBINMAP_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DRobinmap_ROOT="${SYSROOT_DIR}/usr" \
    -Dfmt_DIR="${SYSROOT_DIR}/usr/lib/cmake/fmt" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version" \
    -DBUILD_SHARED_LIBS=ON \
    -DOIIO_BUILD_TESTS=OFF \
    -DOIIO_BUILD_TOOLS=OFF \
    -DUSE_PYTHON=OFF \
    -DUSE_FFMPEG=OFF \
    -DUSE_OPENGL=OFF \
    -DUSE_LIBRAW=OFF \
    -DUSE_OPENCV=OFF \
    -DUSE_FREETYPE=OFF \
    -DUSE_GIF=OFF \
    -DUSE_HEIF=OFF \
    -DUSE_WEBP=OFF \
    -DUSE_DICOM=OFF \
    -DUSE_FONTCONFIG=OFF \
    -DUSE_JXL=OFF \
    -DUSE_LIBUHDR=OFF \
    -DSTOP_ON_WARNING=OFF
ninja -C build-oiio install

echo "===> Building FreeType..."
cd "${BUILD_TMP}"
if [ ! -d "freetype" ]; then
    git clone --depth 1 https://gitlab.freedesktop.org/freetype/freetype.git
fi
cmake -B build-freetype -S freetype -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DFT_DISABLE_ZLIB=ON \
    -DFT_DISABLE_PNG=ON \
    -DFT_DISABLE_BZIP2=ON \
    -DFT_DISABLE_BROTLI=ON \
    -DFT_DISABLE_HARFBUZZ=ON \
    -DBUILD_SHARED_LIBS=ON
ninja -C build-freetype install

echo "===> Building SDL3 (Windowing, Audio, Vulkan Surface)..."
cd "${BUILD_TMP}"
if [ ! -d "SDL" ]; then
    git clone --depth 1 https://github.com/libsdl-org/SDL.git
fi
cmake -B build-sdl -S SDL -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DSDL_VULKAN=ON \
    -DSDL_STATIC=OFF \
    -DSDL_SHARED=ON
ninja -C build-sdl install

echo "===> Building CPython 3.12 for Android NDK..."
cd "${BUILD_TMP}"
if [ ! -d "cpython" ]; then
    git clone --depth 1 -b 3.12 https://github.com/python/cpython.git
fi
cd cpython
echo "*disabled*" > Modules/Setup.local
echo "_ctypes" >> Modules/Setup.local
echo "_ctypes_test" >> Modules/Setup.local
echo "_tkinter" >> Modules/Setup.local
rm -rf build-android
mkdir -p build-android
cd build-android
../configure \
    --host=${TARGET_TRIPLE} \
    --build=$(../config.guess) \
    --with-build-python=python3 \
    --prefix="${SYSROOT_DIR}/usr" \
    --enable-shared \
    --without-ensurepip \
    --disable-test-modules \
    --disable-ipv6 \
    CFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS}" \
    py_cv_module__ctypes=n/a \
    ac_cv_buggy_getaddrinfo=no \
    ac_cv_file__dev_ptmx=no \
    ac_cv_file__dev_ptc=no
make -j$(nproc)
make install

echo "===> Packaging Sysroot..."
cd "${BASE_DIR}"
tar -czf blender-deps-android-arm64.tar.gz -C "${SYSROOT_DIR}" .
echo "===> Done! Created blender-deps-android-arm64.tar.gz"
