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

CMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake"

echo "===> Unpacking dependencies sysroot..."
if [ -f "blender-deps-android-arm64.tar.gz" ]; then
    mkdir -p "${SYSROOT_DIR}"
    tar -xzf blender-deps-android-arm64.tar.gz -C "${SYSROOT_DIR}"
fi

echo "===> Cloning Blender source (v5.2.0)..."
mkdir -p "${BUILD_TMP}"
cd "${BUILD_TMP}"
if [ ! -d "blender" ]; then
    git clone --depth 1 --branch v5.2.0 https://projects.blender.org/blender/blender.git
fi

echo "===> Configuring Blender for Android ARM64..."
cmake -B build-blender -S blender -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-${API_LEVEL} \
    -DCMAKE_PREFIX_PATH="${SYSROOT_DIR}/usr" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,--undefined-version" \
    -DWITH_VULKAN=ON \
    -DWITH_GHOST_SDL=ON \
    -DWITH_PYTHON=ON \
    -DPYTHON_INCLUDE_DIR="${SYSROOT_DIR}/usr/include/python3.12" \
    -DPYTHON_LIBRARY="${SYSROOT_DIR}/usr/lib/libpython3.12.so" \
    -DTBB_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DTBB_LIBRARY="${SYSROOT_DIR}/usr/lib/libtbb.so" \
    -DFREETYPE_INCLUDE_DIRS="${SYSROOT_DIR}/usr/include/freetype2" \
    -DFREETYPE_LIBRARY="${SYSROOT_DIR}/usr/lib/libfreetype.so" \
    -DJPEG_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DJPEG_LIBRARY="${SYSROOT_DIR}/usr/lib/libjpeg.so" \
    -DPNG_PNG_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DPNG_LIBRARY="${SYSROOT_DIR}/usr/lib/libpng16.so" \
    -DZSTD_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DZSTD_LIBRARY="${SYSROOT_DIR}/usr/lib/libzstd.so" \
    -DEPOXY_INCLUDE_DIR="${SYSROOT_DIR}/usr/include" \
    -DEPOXY_LIBRARY="${SYSROOT_DIR}/usr/lib/libepoxy.so" \
    -DWITH_MEM_JEMALLOC=OFF \
    -DWITH_CYCLES=OFF \
    -DWITH_OPENIMAGEIO=OFF \
    -DWITH_OPENCOLORIO=OFF \
    -DWITH_OPENSUBDIV=OFF \
    -DWITH_OPENVDB=OFF \
    -DWITH_ALEMBIC=OFF \
    -DWITH_USD=OFF \
    -DWITH_CODEC_FFMPEG=OFF \
    -DWITH_DRACO=OFF \
    -DWITH_IMAGE_OPENEXR=OFF \
    -DWITH_IMAGE_TIFF=OFF \
    -DWITH_IMAGE_OPENJPEG=OFF \
    -DWITH_IMAGE_CINEON=OFF \
    -DWITH_IMAGE_HDR=OFF \
    -DWITH_IMAGE_DDS=OFF \
    -DWITH_INTERNATIONAL=OFF \
    -DWITH_BUILDINFO=OFF

echo "===> Building Blender core..."
ninja -C build-blender -j$(nproc)

echo "===> Packaging into standalone APK..."
APK_DIR="${BUILD_TMP}/apk-build"
rm -rf "${APK_DIR}"
mkdir -p "${APK_DIR}/lib/arm64-v8a" "${APK_DIR}/assets/datafiles" "${APK_DIR}/assets/scripts"

# Copy libraries
cp ${SYSROOT_DIR}/usr/lib/*.so* "${APK_DIR}/lib/arm64-v8a/" || true
find build-blender/lib -name "*.so" -exec cp {} "${APK_DIR}/lib/arm64-v8a/" \; 2>/dev/null || true
if [ -f "build-blender/bin/blender" ]; then
    cp build-blender/bin/blender "${APK_DIR}/lib/arm64-v8a/libmain.so"
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
