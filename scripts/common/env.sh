#!/usr/bin/env bash
# Common environment and toolchain configuration for Blender Android ARM64 build

BASE_DIR="${BASE_DIR:-$(pwd)}"
SYSROOT_DIR="${BASE_DIR}/sysroot-android-arm64"
BUILD_TMP="${BASE_DIR}/build-tmp"
BLENDER_SRC="${BUILD_TMP}/blender"
HOST_TOOLS_DIR="${BUILD_TMP}/build-host-tools"
BLENDER_BUILD_DIR="${BUILD_TMP}/build-blender"
API_LEVEL="29"
export BASE_DIR SYSROOT_DIR BUILD_TMP BLENDER_SRC HOST_TOOLS_DIR BLENDER_BUILD_DIR API_LEVEL

if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    if [ -d "/usr/local/lib/android/sdk/ndk/27.3.13750724" ]; then
        export ANDROID_NDK_ROOT="/usr/local/lib/android/sdk/ndk/27.3.13750724"
    elif [ -d "/usr/local/lib/android/sdk/ndk/26.3.11579264" ]; then
        export ANDROID_NDK_ROOT="/usr/local/lib/android/sdk/ndk/26.3.11579264"
    fi
fi

TOOLCHAIN="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64"
CMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake"
TARGET_TRIPLE="aarch64-linux-android"
export TOOLCHAIN TARGET_TRIPLE

export CC="${TOOLCHAIN}/bin/${TARGET_TRIPLE}${API_LEVEL}-clang"
export CXX="${TOOLCHAIN}/bin/${TARGET_TRIPLE}${API_LEVEL}-clang++"
export AR="${TOOLCHAIN}/bin/llvm-ar"
export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
export READELF="${TOOLCHAIN}/bin/llvm-readelf"

# Fast compilation and safety flags
export CFLAGS="-fPIC -ftls-model=global-dynamic -fno-stack-protector"
export CXXFLAGS="-fPIC -ftls-model=global-dynamic -fno-stack-protector"
export LDFLAGS="-fPIC"

# ccache integration for lightning fast rebuilds
export CCACHE_SLOPPINESS="pch_defines,time_macros"
export CCACHE_COMPRESS="true"
export CCACHE_COMPRESSLEVEL="6"

export PKG_CONFIG_PATH="${SYSROOT_DIR}/usr/lib/pkgconfig:${SYSROOT_DIR}/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"
