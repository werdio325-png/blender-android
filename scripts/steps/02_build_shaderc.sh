#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> Setting up Shaderc headers and libraries for Android ARM64..."
mkdir -p "${SYSROOT_DIR}/usr/include/shaderc" "${SYSROOT_DIR}/usr/lib"
if [ -d "${ANDROID_NDK_ROOT}/sources/third_party/shaderc/include" ]; then
    cp -r "${ANDROID_NDK_ROOT}/sources/third_party/shaderc/include"/* "${SYSROOT_DIR}/usr/include/"
fi
if [ -d "/usr/include/shaderc" ]; then
    cp -r /usr/include/shaderc/* "${SYSROOT_DIR}/usr/include/shaderc/" 2>/dev/null || true
fi
mkdir -p "${TOOLCHAIN}/sysroot/usr/include/shaderc"
cp -r "${SYSROOT_DIR}/usr/include/shaderc"/* "${TOOLCHAIN}/sysroot/usr/include/shaderc/" 2>/dev/null || true

if [ -d "${ANDROID_NDK_ROOT}/sources/third_party/shaderc" ]; then
    echo "Building Shaderc for Android ARM64 via ndk-build..."
    cd "${ANDROID_NDK_ROOT}/sources/third_party/shaderc"
    ${ANDROID_NDK_ROOT}/ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=Android.mk APP_ABI=arm64-v8a APP_STL=c++_shared APP_PLATFORM=android-29 libshaderc_combined -j$(nproc) || true
    ${ANDROID_NDK_ROOT}/ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=Android.mk APP_ABI=arm64-v8a APP_STL=c++_shared APP_PLATFORM=android-29 -j$(nproc) || true
    cd "${BASE_DIR}"
fi

echo "===> Combining and installing Shaderc libraries..."
SHADERC_OBJ_DIR=$(mktemp -d)
idx=0
find "${ANDROID_NDK_ROOT}/sources/third_party/shaderc" -name "*.a" -path "*/arm64-v8a/*" | while read -r arc; do
    idx=$((idx+1))
    sub="${SHADERC_OBJ_DIR}/${idx}"
    mkdir -p "${sub}"
    (cd "${sub}" && ${TOOLCHAIN}/bin/llvm-ar x "${arc}" 2>/dev/null || true)
done
OBJ_FILES=$(find "${SHADERC_OBJ_DIR}" -name "*.o" 2>/dev/null || true)
if [ -n "${OBJ_FILES}" ]; then
    ${TOOLCHAIN}/bin/llvm-ar rcs "${SYSROOT_DIR}/usr/lib/libshaderc.a" ${OBJ_FILES}
    cp -f "${SYSROOT_DIR}/usr/lib/libshaderc.a" "${SYSROOT_DIR}/usr/lib/libshaderc_combined.a"
fi
rm -rf "${SHADERC_OBJ_DIR}"

if [ ! -f "${SYSROOT_DIR}/usr/lib/libshaderc.a" ]; then
    SHADERC_FALLBACK=$(find "${ANDROID_NDK_ROOT}" -name "libshaderc*.a" 2>/dev/null | grep -i "arm64" | head -n 1 || true)
    if [ -n "${SHADERC_FALLBACK}" ]; then
        cp -f "${SHADERC_FALLBACK}" "${SYSROOT_DIR}/usr/lib/libshaderc.a"
        cp -f "${SHADERC_FALLBACK}" "${SYSROOT_DIR}/usr/lib/libshaderc_combined.a"
    fi
fi

find "${ANDROID_NDK_ROOT}/sources/third_party/shaderc" -name "*.a" -path "*/arm64-v8a/*" -exec cp -f {} "${SYSROOT_DIR}/usr/lib/" \; 2>/dev/null || true

for d in "${TOOLCHAIN}/sysroot/usr/lib" \
         "${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android" \
         "${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL}"; do
    mkdir -p "$d"
    cp -f "${SYSROOT_DIR}/usr/lib/libshaderc"* "$d/" 2>/dev/null || true
    cp -f "${SYSROOT_DIR}/usr/lib/libglslang"* "$d/" 2>/dev/null || true
    cp -f "${SYSROOT_DIR}/usr/lib/libSPIRV"* "$d/" 2>/dev/null || true
    cp -f "${SYSROOT_DIR}/usr/lib/libOGLCompiler"* "$d/" 2>/dev/null || true
    cp -f "${SYSROOT_DIR}/usr/lib/libOSDependent"* "$d/" 2>/dev/null || true
    cp -f "${SYSROOT_DIR}/usr/lib/libHLSL"* "$d/" 2>/dev/null || true
done

export PKG_CONFIG_PATH="${SYSROOT_DIR}/usr/lib/pkgconfig:${SYSROOT_DIR}/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"

