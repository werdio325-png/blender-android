#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Step 09] Packaging into standalone APK..."
cd "${BASE_DIR}"
APK_DIR="${BUILD_TMP}/apk-build"
rm -rf "${APK_DIR}"
mkdir -p "${APK_DIR}/lib/arm64-v8a" "${APK_DIR}/assets/datafiles" "${APK_DIR}/assets/scripts"

# Copy libraries
cp -P ${SYSROOT_DIR}/usr/lib/*.so* "${APK_DIR}/lib/arm64-v8a/" || true
cp -P ${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so "${APK_DIR}/lib/arm64-v8a/" 2>/dev/null || true
find "${ANDROID_NDK_ROOT}" -name "libc++_shared.so" -path "*/arm64*/*" -exec cp -P {} "${APK_DIR}/lib/arm64-v8a/" \; 2>/dev/null || true
find "${APK_DIR}/lib/arm64-v8a" -type l -exec cp --remove-destination "$(readlink -f {})" {} \; 2>/dev/null || true

# Copy Blender shared libs and main binary
find "${BLENDER_BUILD_DIR}/lib" -name "*.so*" -exec cp {} "${APK_DIR}/lib/arm64-v8a/" \; 2>/dev/null || true
find "${BLENDER_BUILD_DIR}/bin" -name "*.so*" -exec cp {} "${APK_DIR}/lib/arm64-v8a/" \; 2>/dev/null || true

if [ -f "${BLENDER_BUILD_DIR}/bin/blender" ]; then
    cp "${BLENDER_BUILD_DIR}/bin/blender" "${APK_DIR}/lib/arm64-v8a/libmain.so"
elif [ -f "${BLENDER_BUILD_DIR}/bin/libblender.so" ]; then
    cp "${BLENDER_BUILD_DIR}/bin/libblender.so" "${APK_DIR}/lib/arm64-v8a/libmain.so"
elif [ -f "${BLENDER_BUILD_DIR}/lib/libblender.so" ]; then
    cp "${BLENDER_BUILD_DIR}/lib/libblender.so" "${APK_DIR}/lib/arm64-v8a/libmain.so"
else
    MAIN_LIB=$(find "${BLENDER_BUILD_DIR}" -name "libblender.so" -o -name "blender" | head -n 1)
    if [ -n "${MAIN_LIB}" ]; then
        cp "${MAIN_LIB}" "${APK_DIR}/lib/arm64-v8a/libmain.so"
    fi
fi

# Ensure libpython3.13.so is present and not deleted
if [ -f "${SYSROOT_DIR}/usr/lib/libpython3.13.so" ]; then
    cp -P "${SYSROOT_DIR}/usr/lib/libpython3.13.so"* "${APK_DIR}/lib/arm64-v8a/" || true
fi
# Remove versioned .so.* files but protect libpython3.13.so
find "${APK_DIR}/lib/arm64-v8a" -name "*.[0-9]*" ! -name "libpython3.13.so" -delete 2>/dev/null || true
# Strip unneeded symbols from all shared libraries in the APK
echo "===> Stripping shared libraries for APK size reduction..."
find "${APK_DIR}/lib/arm64-v8a" -type f -name "*.so" -exec "${TOOLCHAIN}/bin/llvm-strip" --strip-unneeded {} + 2>/dev/null || true

# Copy assets
if [ -d "${BLENDER_SRC}/release/datafiles" ]; then
    cp -r ${BLENDER_SRC}/release/datafiles/* "${APK_DIR}/assets/datafiles/" || true
fi
if [ -d "${BLENDER_SRC}/release/scripts" ]; then
    cp -r ${BLENDER_SRC}/release/scripts/* "${APK_DIR}/assets/scripts/" || true
elif [ -d "${BLENDER_SRC}/scripts" ]; then
    cp -r ${BLENDER_SRC}/scripts/* "${APK_DIR}/assets/scripts/" || true
fi

PYTHON_STDLIB=$(find "${SYSROOT_DIR}/usr/lib" -maxdepth 1 -name "python3*" -type d 2>/dev/null | head -n 1 || true)
if [ -n "${PYTHON_STDLIB}" ]; then
    mkdir -p "${APK_DIR}/assets/python/lib"
    cp -r "${PYTHON_STDLIB}" "${APK_DIR}/assets/python/lib/" 2>/dev/null || true
fi

find "${APK_DIR}/assets" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "${APK_DIR}/assets" -name "*.pyc" -delete 2>/dev/null || true

# Compile Java sources and assemble APK using android SDK build tools
AAPT2=$(find /usr/local/lib/android/sdk/build-tools -name aapt2 2>/dev/null | sort -V | tail -n 1)
ANDROID_JAR=$(find /usr/local/lib/android/sdk/platforms -name android.jar 2>/dev/null | sort -V | tail -n 1)
D8=$(find /usr/local/lib/android/sdk/build-tools -name d8 2>/dev/null | sort -V | tail -n 1)
ZIPALIGN=$(find /usr/local/lib/android/sdk/build-tools -name zipalign 2>/dev/null | sort -V | tail -n 1)
APKSIGNER=$(find /usr/local/lib/android/sdk/build-tools -name apksigner 2>/dev/null | sort -V | tail -n 1)

echo "===> Compiling Java sources for SDLActivity..."
JAVA_SRC_DIR="${BASE_DIR}/android/app/src/main/java"
JAVA_CLASSES_DIR="${BUILD_TMP}/java_classes"
rm -rf "${JAVA_CLASSES_DIR}"
mkdir -p "${JAVA_CLASSES_DIR}"

JAVA_FILES=$(find "${JAVA_SRC_DIR}" -name "*.java")
javac -source 17 -target 17 -cp "$ANDROID_JAR" -d "${JAVA_CLASSES_DIR}" ${JAVA_FILES}

echo "===> Converting class files to Dalvik DEX via d8..."
CLASS_FILES=$(find "${JAVA_CLASSES_DIR}" -name "*.class")
$D8 --output "${APK_DIR}" --min-api ${API_LEVEL} --lib "$ANDROID_JAR" ${CLASS_FILES}

echo "===> Linking resources with AAPT2..."
$AAPT2 link -o "${BUILD_TMP}/unaligned.apk" \
    -I "$ANDROID_JAR" \
    --manifest "${BASE_DIR}/android/app/src/main/AndroidManifest.xml" \
    -A "${APK_DIR}/assets" \
    --auto-add-overlay

cd "${APK_DIR}"
zip -u -r "${BUILD_TMP}/unaligned.apk" lib/ classes.dex
cd "${BASE_DIR}"

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
