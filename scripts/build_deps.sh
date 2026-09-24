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

mkdir -p "${SYSROOT_DIR}/usr/include" "${SYSROOT_DIR}/usr/lib" "${BUILD_TMP}"

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
    -DTBB_EXAMPLES=OFF \
    -DTBBMALLOC_BUILD=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version"
ninja -C build-onetbb install

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
    -DENABLE_SHARED=ON \
    -DENABLE_STATIC=OFF \
    -DWITH_SIMD=OFF
ninja -C build-jpeg install

echo "===> Building libpng..."
cd "${BUILD_TMP}"
if [ ! -d "libpng" ]; then
    git clone --depth 1 https://github.com/glennrp/libpng.git
fi
cmake -B build-png -S libpng -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT_DIR}/usr" \
    -DPNG_SHARED=ON \
    -DPNG_STATIC=OFF \
    -DPNG_TESTS=OFF
ninja -C build-png install

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
