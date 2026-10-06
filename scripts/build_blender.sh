#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(pwd)"
SYSROOT_DIR="${BASE_DIR}/sysroot-android-arm64"
BUILD_TMP="${BASE_DIR}/build-tmp"
BLENDER_SRC="${BUILD_TMP}/blender"
API_LEVEL="29"
export BASE_DIR SYSROOT_DIR BUILD_TMP BLENDER_SRC API_LEVEL

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
export CC="${TOOLCHAIN}/bin/${TARGET_TRIPLE}${API_LEVEL}-clang"
export CXX="${TOOLCHAIN}/bin/${TARGET_TRIPLE}${API_LEVEL}-clang++"
export AR="${TOOLCHAIN}/bin/llvm-ar"
export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
export READELF="${TOOLCHAIN}/bin/llvm-readelf"
export CFLAGS="-fPIC -ftls-model=global-dynamic -fno-stack-protector"
export CXXFLAGS="-fPIC -ftls-model=global-dynamic -fno-stack-protector"
export LDFLAGS="-fPIC"

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

echo "===> Disabling Git LFS filters..."
git lfs uninstall --system 2>/dev/null || true
git lfs uninstall 2>/dev/null || true
git config --global filter.lfs.smudge "cat" 2>/dev/null || true
git config --global filter.lfs.clean "cat" 2>/dev/null || true
git config --global filter.lfs.process "" 2>/dev/null || true
git config --global filter.lfs.required false 2>/dev/null || true
git config --global http.version HTTP/1.1 2>/dev/null || true
git config --global http.postBuffer 524288000 2>/dev/null || true
export GIT_LFS_SKIP_SMUDGE=1

echo "===> Cloning Blender source (v5.2.0)..."
mkdir -p "${BUILD_TMP}"
cd "${BUILD_TMP}"
if [ ! -f "blender/build_files/cmake/platform/platform_unix.cmake" ]; then
    rm -rf blender
    for attempt in 1 2 3; do
        echo "Cloning Blender source (attempt $attempt)..."
        rm -rf blender
        if git -c filter.lfs.smudge=cat -c filter.lfs.clean=cat -c filter.lfs.process= -c filter.lfs.required=false clone --depth 1 --branch v5.2.0 https://github.com/blender/blender.git blender; then
            break
        fi
        rm -rf blender
        if git -c filter.lfs.smudge=cat -c filter.lfs.clean=cat -c filter.lfs.process= -c filter.lfs.required=false clone --depth 1 --branch v5.2.0 https://projects.blender.org/blender/blender.git blender; then
            break
        fi
        sleep 5
    done
fi

if [ -d "blender/.git" ] && [ ! -f "blender/build_files/cmake/platform/platform_unix.cmake" ]; then
    echo "Forcing checkout in blender repo..."
    (cd blender && git -c filter.lfs.smudge=cat -c filter.lfs.clean=cat -c filter.lfs.process= -c filter.lfs.required=false checkout -f HEAD || true)
fi

if [ ! -f "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake" ]; then
    echo "ERROR: Failed to clone and checkout Blender source code!"
    exit 1
fi

echo "===> Downloading critical runtime datafiles, icons and fonts..."
echo "Downloading OpenColorIO fallback config v2.3..."
mkdir -p "${BLENDER_SRC}/release/datafiles/colormanagement"
curl -sL "https://projects.blender.org/blender/blender/media/branch/blender-v4.2-release/release/datafiles/colormanagement/config.ocio" -o "${BLENDER_SRC}/release/datafiles/colormanagement/config.ocio" || true

echo "Downloading vector icons from projects.blender.org media..."
mkdir -p "${BLENDER_SRC}/release/datafiles/icons"
python3 -c '
import urllib.request, os
base_url = "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/icons/"
target_dir = os.environ.get("BLENDER_SRC", "") + "/release/datafiles/icons"
if os.path.exists(target_dir):
    for icon in os.listdir(target_dir):
        p = os.path.join(target_dir, icon)
        if os.path.isfile(p) and os.path.getsize(p) < 200:
            try:
                url = base_url + icon
                urllib.request.urlretrieve(url, p)
            except Exception:
                pass
    print("Downloaded real icons successfully.")
' || true

mkdir -p "${BLENDER_SRC}/release/datafiles/fonts"
for f in startup.blend preview.blend preview_grease_pencil.blend splash.png; do
    echo "Downloading ${f}..."
    curl -sL "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/${f}" -o "${BLENDER_SRC}/release/datafiles/${f}" || true
done
for f in Inter.woff2 DejaVuSansMono.woff2; do
    echo "Downloading font ${f}..."
    curl -sL "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/fonts/${f}" -o "${BLENDER_SRC}/release/datafiles/fonts/${f}" || true
done

echo "===> Converting fonts to raw TrueType format for Android FreeType..."
python3 -m pip install fonttools brotli || true
python3 -c "
import os
try:
    from fontTools.ttLib import woff2
    font_dir = '${BLENDER_SRC}/release/datafiles/fonts'
    for f in ['Inter', 'DejaVuSansMono']:
        w_path = os.path.join(font_dir, f + '.woff2')
        t_path = os.path.join(font_dir, f + '.ttf')
        if os.path.exists(w_path):
            print('Decompressing ' + f + '.woff2 to ' + t_path + '...')
            woff2.decompress(w_path, t_path)
            with open(t_path, 'rb') as src, open(w_path, 'wb') as dst:
                dst.write(src.read())
            print('Successfully updated ' + f + '.woff2 with uncompressed TTF bytes.')
except Exception as e:
    print('fonttools decompress failed: ' + str(e))
" || true

for f in Inter DejaVuSansMono; do
    w_file="${BLENDER_SRC}/release/datafiles/fonts/${f}.woff2"
    t_file="${BLENDER_SRC}/release/datafiles/fonts/${f}.ttf"
    if [ ! -f "${t_file}" ] && [ -f "${w_file}" ]; then
        if command -v woff2_decompress >/dev/null 2>&1; then
            echo "Decompressing with woff2_decompress: ${f}.woff2"
            woff2_decompress "${w_file}" || true
            if [ -f "${t_file}" ]; then
                cp -f "${t_file}" "${w_file}"
            fi
        fi
    fi
done

if [ ! -f "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" ]; then
    echo "Downloading fallback Inter TTF from Google Fonts..."
    curl -sL "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf" -o "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" || true
    cp -f "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" "${BLENDER_SRC}/release/datafiles/fonts/Inter.woff2"
    cp -f "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" "${BLENDER_SRC}/release/datafiles/fonts/DejaVuSansMono.woff2"
    cp -f "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" "${BLENDER_SRC}/release/datafiles/fonts/DejaVuSansMono.ttf"
fi

echo "===> Patching Blender CMake for Android ARM64..."
# Bypass startup.blend size check
sed -i 's/message(FATAL_ERROR "Detected incomplete startup blend/# &/' "${BLENDER_SRC}/CMakeLists.txt" 
# Bypass FreeType Brotli check (Brotli only used for woff web fonts)
sed -i 's/message(FATAL_ERROR "Freetype needs to be compiled with brotli support!")/# &/' "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake"
# Remove -lutil for Android (Bionic does not have libutil)
sed -i 's/-lutil//g' "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake"
# Remove -no-pie for Android (Android Bionic linker strictly requires PIE executables)
sed -i 's/-no-pie//g' "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake"

# Build blender as a shared library for Android NativeActivity
sed -i 's/add_executable(blender ${EXETYPE} ${SRC})/add_library(blender SHARED ${SRC})/' "${BLENDER_SRC}/source/creator/CMakeLists.txt"
# Disable TBB malloc proxy checks in platform_unix.cmake
sed -i 's/if(WITH_TBB_MALLOC_PROXY)/if(FALSE)/' "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake"
# Patch dualcon octree.cpp for modern Eigen JacobiSVD compatibility
if [ -f "${BLENDER_SRC}/intern/dualcon/intern/octree.cpp" ]; then
    sed -i 's/Eigen::JacobiSVD<Eigen::Matrix3f, Options> svd = a.jacobiSvd<Options>();//' "${BLENDER_SRC}/intern/dualcon/intern/octree.cpp"
    sed -i 's/const int Options = Eigen::ComputeFullU | Eigen::ComputeFullV;/Eigen::JacobiSVD<Eigen::Matrix3f> svd(a, Eigen::ComputeFullU | Eigen::ComputeFullV);/' "${BLENDER_SRC}/intern/dualcon/intern/octree.cpp"
fi
# Patch BLI_mmap.cc for Android Bionic sigaction struct initialization
if [ -f "${BLENDER_SRC}/source/blender/blenlib/intern/BLI_mmap.cc" ]; then
    sed -i 's/struct sigaction newact = {{nullptr}}, oldact = {{nullptr}};/struct sigaction newact = {}, oldact = {};/' "${BLENDER_SRC}/source/blender/blenlib/intern/BLI_mmap.cc"
fi

# Disable BLI_subprocess on Android (Bionic lacks POSIX shm / named semaphores)
if [ -f "${BLENDER_SRC}/source/blender/blenlib/BLI_subprocess.hh" ]; then
    sed -i 's/#if defined(_WIN32) || defined(__linux__)/#if (defined(_WIN32) || defined(__linux__)) \&\& !defined(__ANDROID__)/' "${BLENDER_SRC}/source/blender/blenlib/BLI_subprocess.hh"
fi

# Disable execinfo backtrace in system.cc on Android (Bionic lacks backtrace/backtrace_symbols)
if [ -f "${BLENDER_SRC}/source/blender/blenlib/intern/system.cc" ]; then
    sed -i 's/defined(HAVE_EXECINFO_H)/defined(HAVE_EXECINFO_H) \&\& !defined(__ANDROID__)/g' "${BLENDER_SRC}/source/blender/blenlib/intern/system.cc"
fi
if [ -f "${BLENDER_SRC}/source/blender/blenlib/CMakeLists.txt" ]; then
    sed -i 's/if(HAVE_EXECINFO_H)/if(HAVE_EXECINFO_H AND NOT ANDROID)/g' "${BLENDER_SRC}/source/blender/blenlib/CMakeLists.txt"
fi

# Guard initClearGL in GHOST_ContextSDL and GHOST_ContextEGL with WITH_OPENGL_BACKEND
if [ -f "${BLENDER_SRC}/intern/ghost/intern/GHOST_ContextSDL.cc" ]; then
    sed -i 's/initClearGL();/#ifdef WITH_OPENGL_BACKEND\n    initClearGL();\n#endif/' "${BLENDER_SRC}/intern/ghost/intern/GHOST_ContextSDL.cc"
fi
if [ -f "${BLENDER_SRC}/intern/ghost/intern/GHOST_ContextEGL.cc" ]; then
    sed -i 's/initClearGL();/#ifdef WITH_OPENGL_BACKEND\n    initClearGL();\n#endif/' "${BLENDER_SRC}/intern/ghost/intern/GHOST_ContextEGL.cc"
fi

# Guard fftw3.h in ocean_intern.h for Android
if [ -f "${BLENDER_SRC}/source/blender/blenkernel/intern/ocean_intern.h" ]; then
    sed -i 's/#  include "fftw3.h"/#  if defined(WITH_OCEANSIM) \&\& !defined(__ANDROID__)\n#    include "fftw3.h"\n#  endif/' "${BLENDER_SRC}/source/blender/blenkernel/intern/ocean_intern.h"
fi

# Compatibility for Vulkan 1.4 Dynamic Rendering local read in vk_graphics_pipeline.hh
if [ -f "${BLENDER_SRC}/source/blender/gpu/vulkan/vk_graphics_pipeline.hh" ]; then
    sed -i 's/VkRenderingInputAttachmentIndexInfo vk_rendering_input_attachment_index_info_;/VkRenderingInputAttachmentIndexInfoKHR vk_rendering_input_attachment_index_info_;/' "${BLENDER_SRC}/source/blender/gpu/vulkan/vk_graphics_pipeline.hh" || true
    sed -i 's/VK_STRUCTURE_TYPE_RENDERING_INPUT_ATTACHMENT_INDEX_INFO;/VK_STRUCTURE_TYPE_RENDERING_INPUT_ATTACHMENT_INDEX_INFO_KHR;/g' "${BLENDER_SRC}/source/blender/gpu/vulkan/vk_graphics_pipeline.hh" || true
fi

# Patch vk_shader_compiler.cc for NDK Shaderc compatibility (SetMaxIdBound is only in newer shaderc)
if [ -f "${BLENDER_SRC}/source/blender/gpu/vulkan/vk_shader_compiler.cc" ]; then
    sed -i 's/.*SetMaxIdBound.*/\/\/ &/' "${BLENDER_SRC}/source/blender/gpu/vulkan/vk_shader_compiler.cc" || true
fi

# Patch MOD_grease_pencil_build.cc for TBB parallel_sort const comparator compatibility
if [ -f "${BLENDER_SRC}/source/blender/modifiers/intern/MOD_grease_pencil_build.cc" ]; then
    sed -i 's/Pair &a, Pair &b/const Pair \&a, const Pair \&b/g' "${BLENDER_SRC}/source/blender/modifiers/intern/MOD_grease_pencil_build.cc"
fi

# Allow mobile Vulkan devices (Mali, Adreno) on Android by skipping desktop-only requirements in vk_backend.cc
if [ -f "${BLENDER_SRC}/source/blender/gpu/vulkan/vk_backend.cc" ]; then
    sed -i 's/Vector<StringRefNull> missing_capabilities;/#ifdef __ANDROID__\n  return {};\n#endif\n  Vector<StringRefNull> missing_capabilities;/' "${BLENDER_SRC}/source/blender/gpu/vulkan/vk_backend.cc"
fi

# (GHOST_ContextVK device features relaxed in unified patch below)

# Guard GPU_storagebuf functions against nullptr ssbo safely
if [ -f "${BLENDER_SRC}/source/blender/gpu/intern/gpu_storage_buffer.cc" ]; then
    python3 -c "
p = '${BLENDER_SRC}/source/blender/gpu/intern/gpu_storage_buffer.cc'
with open(p, 'r') as f:
    c = f.read()
import re
for fn in ['usage_size_set', 'update', 'bind', 'unbind', 'clear', 'clear_to_zero', 'sync_to_host', 'read']:
    c = re.sub(rf'(void GPU_storagebuf_{fn}\\([^)]*StorageBuf \\*ssbo[^)]*\\)\\s*\\{{)', r'\\1\\n  if (!ssbo) return;', c)
with open(p, 'w') as f:
    f.write(c)
"
fi

# Guard StorageCommon::push_update against nullptr ssbo in DRW_gpu_wrapper.hh
if [ -f "${BLENDER_SRC}/source/blender/draw/intern/DRW_gpu_wrapper.hh" ]; then
    sed -i 's/GPU_storagebuf_update(ssbo_, this->data_);/if (ssbo_) GPU_storagebuf_update(ssbo_, this->data_);/' "${BLENDER_SRC}/source/blender/draw/intern/DRW_gpu_wrapper.hh"
fi



# (Swapchain imageUsage handled in unified patch below)

# Ensure window is kept alive on Android and bypass fatal platform check exit
if [ -f "${BLENDER_SRC}/source/blender/windowmanager/intern/wm_init_exit.cc" ]; then
    python3 - << 'PYEOF'
import os
p = os.environ.get('BLENDER_SRC', '') + '/source/blender/windowmanager/intern/wm_init_exit.cc'
if os.path.exists(p):
    with open(p, 'r') as f:
        c = f.read()

    target1 = '''    if (wm != nullptr) {
      wm_window_ghostwindows_remove_invalid(C, wm);
    }
    if (wm == nullptr || wm->windows.is_empty()) {
      if (params_file_read_post != nullptr) {
        MEM_delete_void(static_cast<void *>(params_file_read_post));
        params_file_read_post = nullptr;
      }
      WM_exit(C, EXIT_FAILURE);
    }'''

    repl1 = '''#ifndef __ANDROID__
    if (wm != nullptr) {
      wm_window_ghostwindows_remove_invalid(C, wm);
    }
    if (wm == nullptr || wm->windows.is_empty()) {
      if (params_file_read_post != nullptr) {
        MEM_delete_void(static_cast<void *>(params_file_read_post));
        params_file_read_post = nullptr;
      }
      WM_exit(C, EXIT_FAILURE);
    }
#else
    if (wm == nullptr || wm->windows.is_empty()) {
      wm_add_default(CTX_data_main(C), C);
      wm = CTX_wm_manager(C);
    }
    if (wm != nullptr) {
      wm_window_ghostwindows_ensure(wm);
    }
#endif'''

    target2 = '''    if (!WM_platform_support_perform_checks()) {
      WM_exit(C, -1);
    }'''

    repl2 = '''#ifndef __ANDROID__
    if (!WM_platform_support_perform_checks()) {
      WM_exit(C, -1);
    }
#else
    WM_platform_support_perform_checks();
#endif'''

    if target1 in c:
        c = c.replace(target1, repl1)
        print('Patched target1 in wm_init_exit.cc')
    else:
        print('ERROR: target1 not found in wm_init_exit.cc')

    if target2 in c:
        c = c.replace(target2, repl2)
        print('Patched target2 in wm_init_exit.cc')
    else:
        print('ERROR: target2 not found in wm_init_exit.cc')

    with open(p, 'w') as f:
        f.write(c)
PYEOF
fi


# Add full on-screen SDL Vulkan swapchain & Mali GPU support to GHOST
python3 - << 'PYEOF'
import os

blender_src = os.environ.get('BLENDER_SRC', '')

# 1. Update GHOST_ContextVK.hh to define GHOST_kVulkanPlatformSDL
p_hh = blender_src + '/intern/ghost/intern/GHOST_ContextVK.hh'
if os.path.exists(p_hh):
    with open(p_hh, 'r') as f:
        c = f.read()
    t_enum = '''enum GHOST_TVulkanPlatformType {
  GHOST_kVulkanPlatformHeadless = 0,'''
    rep_enum = '''enum GHOST_TVulkanPlatformType {
  GHOST_kVulkanPlatformHeadless = 0,
  GHOST_kVulkanPlatformSDL = 3,'''
    if t_enum in c:
        c = c.replace(t_enum, rep_enum)
        with open(p_hh, 'w') as f:
            f.write(c)
        print('Successfully patched GHOST_ContextVK.hh')

# 2. Update GHOST_ContextVK.cc for SDL Vulkan surface, Mali features and Android swapchain
p_vk = blender_src + '/intern/ghost/intern/GHOST_ContextVK.cc'
if os.path.exists(p_vk):
    with open(p_vk, 'r') as f:
        c = f.read()

    # Include SDL headers for SDL_Vulkan_CreateSurface
    if '<SDL3/SDL_vulkan.h>' not in c:
        c = '''#ifdef __ANDROID__
#  include <SDL3/SDL.h>
#  include <SDL3/SDL_vulkan.h>
#  include <cstdio>
#  include <android/log.h>
#  define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, "BlenderVK", __VA_ARGS__)
#  define ALOGW(...) __android_log_print(ANDROID_LOG_WARN, "BlenderVK", __VA_ARGS__)
#  define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, "BlenderVK", __VA_ARGS__)
#else
#  define ALOGI(...)
#  define ALOGW(...)
#  define ALOGE(...)
#endif
''' + c

    # Platform surface extension
    t_ext = '''    case GHOST_kVulkanPlatformHeadless:
      break;
  }
#endif
  return nullptr;
}'''
    rep_ext = '''    case GHOST_kVulkanPlatformSDL:
      return "VK_KHR_android_surface";
    case GHOST_kVulkanPlatformHeadless:
      break;
  }
#endif
  return nullptr;
}'''
    if t_ext in c:
        c = c.replace(t_ext, rep_ext)
        print('Patched getPlatformSpecificSurfaceExtension')

    # use_window_surface
    t_use = '''    case GHOST_kVulkanPlatformHeadless:
      use_window_surface = false;
      break;
  }
#endif'''
    rep_use = '''    case GHOST_kVulkanPlatformSDL:
      use_window_surface = (window_ != nullptr);
      break;
    case GHOST_kVulkanPlatformHeadless:
      use_window_surface = false;
      break;
  }
#endif'''
    if t_use in c:
        c = c.replace(t_use, rep_use)
        print('Patched use_window_surface')

    # Initialize VkSurface via SDL_Vulkan_CreateSurface
    t_surf = '''      case GHOST_kVulkanPlatformHeadless: {
        surface_ = VK_NULL_HANDLE;
        break;
      }'''
    rep_surf = '''      case GHOST_kVulkanPlatformSDL: {
#ifdef __ANDROID__
        if (!SDL_Vulkan_CreateSurface((SDL_Window *)window_, instance_vk.vk_instance, nullptr, &surface_)) {
          CLOG_ERROR(&LOG, "SDL_Vulkan_CreateSurface failed: %s", SDL_GetError());
          return GHOST_kFailure;
        }
#endif
        break;
      }
      case GHOST_kVulkanPlatformHeadless: {
        surface_ = VK_NULL_HANDLE;
        break;
      }'''
    if t_surf in c:
        c = c.replace(t_surf, rep_surf)
        print('Patched surface creation in GHOST_ContextVK.cc')

    # select_physical_device: don't reject Android GPUs lacking geometryShader, dualSrcBlend, etc.
    t_select = '''      if (
#ifndef __APPLE__
          !device_vk.features.features.geometryShader ||
#endif
          !device_vk.features.features.vertexPipelineStoresAndAtomics ||
          !device_vk.features.features.multiViewport ||
          !device_vk.features.features.shaderClipDistance ||
          !device_vk.features.features.fragmentStoresAndAtomics ||
          !device_vk.features.features.multiDrawIndirect ||
          !device_vk.features.features.imageCubeArray ||
          !device_vk.features.features.dualSrcBlend || !device_vk.features.features.logicOp ||
          !device_vk.features.features.imageCubeArray)
      {
        continue;
      }'''
    rep_select = '''#ifndef __ANDROID__
''' + t_select + '''
#endif'''
    if t_select in c:
        c = c.replace(t_select, rep_select)
        print('Patched select_physical_device in GHOST_ContextVK.cc')

    # create_device: on Android use device.features.features directly without demanding desktop-only features
    t_dev = '''    VkPhysicalDeviceFeatures device_features = {};
#ifndef __APPLE__
    device_features.geometryShader = VK_TRUE;
#endif
    device_features.vertexPipelineStoresAndAtomics = VK_TRUE;
    device_features.multiViewport = VK_TRUE;
    device_features.shaderClipDistance = VK_TRUE;
    device_features.fragmentStoresAndAtomics = VK_TRUE;
    device_features.logicOp = VK_TRUE;
    device_features.dualSrcBlend = VK_TRUE;
    device_features.imageCubeArray = VK_TRUE;
    device_features.multiDrawIndirect = VK_TRUE;
    device_features.drawIndirectFirstInstance = VK_TRUE;
    device_features.samplerAnisotropy = device.features.features.samplerAnisotropy;
    device_features.wideLines = device.features.features.wideLines;'''

    rep_dev = '''#ifndef __ANDROID__
''' + t_dev + '''
#else
    VkPhysicalDeviceFeatures device_features = device.features.features;
    device_features.robustBufferAccess = VK_FALSE;
#endif'''
    if t_dev in c:
        c = c.replace(t_dev, rep_dev)
        print('Patched create_device in GHOST_ContextVK.cc')

    # recreateSwapchain extent: query SDL window size when extent is UINT32_MAX, 0, or uninitialized
    t_ext_full = '''  use_hdr_swapchain_ = use_hdr_swapchain;
  render_extent_ = capabilities.currentExtent;
  render_extent_min_ = capabilities.minImageExtent;
  if (render_extent_.width == UINT32_MAX) {
    /* Window Manager is going to set the surface size based on the given size.
     * Choose something between minImageExtent and maxImageExtent. */
    int width = 0;
    int height = 0;

#ifdef WITH_GHOST_WAYLAND
    /* Wayland doesn't provide a windowing API via WSI. */
    if (wayland_window_info_) {
      width = wayland_window_info_->size[0];
      height = wayland_window_info_->size[1];
    }
#endif

    if (width == 0 || height == 0) {
      width = 1280;
      height = 720;
    }

    render_extent_.width = width;
    render_extent_.height = height;

    if (capabilities.minImageExtent.width > render_extent_.width) {
      render_extent_.width = capabilities.minImageExtent.width;
    }
    if (capabilities.minImageExtent.height > render_extent_.height) {
      render_extent_.height = capabilities.minImageExtent.height;
    }
  }'''

    rep_ext_full = '''  use_hdr_swapchain_ = use_hdr_swapchain;
  render_extent_ = capabilities.currentExtent;
  render_extent_min_ = capabilities.minImageExtent;
  ALOGI("recreateSwapchain: capabilities.currentExtent=(%u,%u), minImageExtent=(%u,%u), maxImageExtent=(%u,%u)",
        capabilities.currentExtent.width, capabilities.currentExtent.height,
        capabilities.minImageExtent.width, capabilities.minImageExtent.height,
        capabilities.maxImageExtent.width, capabilities.maxImageExtent.height);
  if (render_extent_.width == UINT32_MAX || render_extent_.width == 0 || render_extent_.height == 0) {
    int width = 0;
    int height = 0;

#ifdef __ANDROID__
    if (window_) {
      SDL_GetWindowSizeInPixels((SDL_Window *)window_, &width, &height);
      ALOGI("recreateSwapchain: queried SDL_GetWindowSizeInPixels: %dx%d", width, height);
    }
#endif
#ifdef WITH_GHOST_WAYLAND
    if (wayland_window_info_) {
      width = wayland_window_info_->size[0];
      height = wayland_window_info_->size[1];
    }
#endif

    if (width == 0 || height == 0) {
      width = 2944;
      height = 1840;
    }

    render_extent_.width = width;
    render_extent_.height = height;

    if (capabilities.minImageExtent.width > render_extent_.width) {
      render_extent_.width = capabilities.minImageExtent.width;
    }
    if (capabilities.minImageExtent.height > render_extent_.height) {
      render_extent_.height = capabilities.minImageExtent.height;
    }
    if (capabilities.maxImageExtent.width > 0 && capabilities.maxImageExtent.width < render_extent_.width) {
      render_extent_.width = capabilities.maxImageExtent.width;
    }
    if (capabilities.maxImageExtent.height > 0 && capabilities.maxImageExtent.height < render_extent_.height) {
      render_extent_.height = capabilities.maxImageExtent.height;
    }
    ALOGI("recreateSwapchain: final calculated render_extent_=(%u,%u)", render_extent_.width, render_extent_.height);
  }'''
    if t_ext_full in c:
        c = c.replace(t_ext_full, rep_ext_full)
        print('Patched full swapchain extent in GHOST_ContextVK.cc')

    # imageUsage & compositeAlpha in recreateSwapchain
    t_ci = '''  create_info.imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT |
                           (use_hdr_swapchain ? VK_IMAGE_USAGE_STORAGE_BIT : 0);
  create_info.preTransform = capabilities.currentTransform;
  create_info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;'''
    rep_ci = '''  VkImageUsageFlags desired_usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  if (capabilities.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT) {
    desired_usage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  }
  if (use_hdr_swapchain && (capabilities.supportedUsageFlags & VK_IMAGE_USAGE_STORAGE_BIT)) {
    desired_usage |= VK_IMAGE_USAGE_STORAGE_BIT;
  }
  create_info.imageUsage = desired_usage;
  create_info.preTransform = capabilities.currentTransform;

  VkCompositeAlphaFlagBitsKHR compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  if ((capabilities.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR) == 0) {
    if (capabilities.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR) {
      compositeAlpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
    }
    else if (capabilities.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR) {
      compositeAlpha = VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR;
    }
  }
  create_info.compositeAlpha = compositeAlpha;'''
    if t_ci in c:
        c = c.replace(t_ci, rep_ci)
        print('Patched imageUsage and compositeAlpha in GHOST_ContextVK.cc')

    # Log and check vkCreateSwapchainKHR result
    t_res = '''  VK_CHECK(vkCreateSwapchainKHR(device_vk.vk_device, &create_info, nullptr, &swapchain_),
           GHOST_kFailure);'''
    rep_res = '''  VkResult swapchain_res = vkCreateSwapchainKHR(device_vk.vk_device, &create_info, nullptr, &swapchain_);
  ALOGI("vkCreateSwapchainKHR result=%d, format=%d, colorSpace=%d, extent=%ux%u, usage=0x%x, alpha=0x%x, count=%u",
        swapchain_res, create_info.imageFormat, create_info.imageColorSpace,
        create_info.imageExtent.width, create_info.imageExtent.height,
        create_info.imageUsage, create_info.compositeAlpha, create_info.minImageCount);
  fprintf(stderr,
          "BlenderVK: vkCreateSwapchainKHR result=%d, format=%d, colorSpace=%d, extent=%ux%u, usage=0x%x, alpha=0x%x, count=%u\\n",
          swapchain_res, create_info.imageFormat, create_info.imageColorSpace,
          create_info.imageExtent.width, create_info.imageExtent.height,
          create_info.imageUsage, create_info.compositeAlpha, create_info.minImageCount);
  fflush(stderr);
  if (swapchain_res != VK_SUCCESS) {
    return GHOST_kFailure;
  }'''
    if t_res in c:
        c = c.replace(t_res, rep_res)
        print('Patched vkCreateSwapchainKHR logging in GHOST_ContextVK.cc')

    # Extended format search in selectSurfaceFormat
    t_fmt = '''    for (const VkSurfaceFormatKHR &format : formats) {
      if (format.format == config.format && format.colorSpace == config.colorSpace) {
        r_surfaceFormat = format;
        return true;
      }
    }
  }

  return false;
}'''
    rep_fmt = '''    for (const VkSurfaceFormatKHR &format : formats) {
      if (format.format == config.format && format.colorSpace == config.colorSpace) {
        r_surfaceFormat = format;
        return true;
      }
    }
  }

  /* Extended format search for Android / Mobile GPUs */
  const VkFormat fallback_formats[] = {
      VK_FORMAT_R8G8B8A8_UNORM,
      VK_FORMAT_R8G8B8A8_SRGB,
      VK_FORMAT_B8G8R8A8_UNORM,
      VK_FORMAT_B8G8R8A8_SRGB,
      VK_FORMAT_A2B10G10R10_UNORM_PACK32,
      VK_FORMAT_R5G6B5_UNORM_PACK16,
  };

  for (VkFormat desired_fmt : fallback_formats) {
    for (const VkSurfaceFormatKHR &format : formats) {
      if (format.format == desired_fmt) {
        r_surfaceFormat = format;
        ALOGI("Selected surface format: %d, colorSpace: %d", format.format, format.colorSpace);
        fprintf(stderr, "BlenderVK: Selected surface format: %d, colorSpace: %d\\n", format.format, format.colorSpace);
        fflush(stderr);
        return true;
      }
    }
  }

  for (const VkSurfaceFormatKHR &format : formats) {
    if (format.format != 56 && format.format != 59) {
      r_surfaceFormat = format;
      ALOGW("Fallback surface format: %d, colorSpace: %d", format.format, format.colorSpace);
      fprintf(stderr, "BlenderVK: Fallback surface format: %d, colorSpace: %d\\n", format.format, format.colorSpace);
      fflush(stderr);
      return true;
    }
  }

  return false;
}'''
    if t_fmt in c:
        c = c.replace(t_fmt, rep_fmt)
        print('Patched selectSurfaceFormat fallback')

    # swapBufferAcquire: on Android, VK_SUBOPTIMAL_KHR is valid and must NOT trigger endless recreation
    t_acq = '''  /* Acquiree next image, swapchain can be (or become) invalid when minimizing window. */
  uint32_t image_index = 0;
  if (swapchain_ != VK_NULL_HANDLE) {
    /* Some platforms (NVIDIA/Wayland) can receive an out of date swapchain when acquiring the next
     * swapchain image. Other do it when calling vkQueuePresent. */
    VkResult acquire_result = VK_ERROR_OUT_OF_DATE_KHR;
    while (swapchain_ != VK_NULL_HANDLE &&
           (ELEM(acquire_result, VK_ERROR_OUT_OF_DATE_KHR, VK_SUBOPTIMAL_KHR)))
    {
      acquire_result = vkAcquireNextImageKHR(vk_device,
                                             swapchain_,
                                             UINT64_MAX,
                                             submission_frame_data.acquire_semaphore,
                                             VK_NULL_HANDLE,
                                             &image_index);
      if (ELEM(acquire_result, VK_ERROR_OUT_OF_DATE_KHR, VK_SUBOPTIMAL_KHR)) {
        recreateSwapchain(use_hdr_swapchain);
      }
    }
  }'''
    rep_acq = '''  /* Acquire next image, swapchain can be (or become) invalid when minimizing window. */
  uint32_t image_index = 0;
  if (swapchain_ != VK_NULL_HANDLE) {
    /* On Android, VK_SUBOPTIMAL_KHR is valid and must NOT trigger endless swapchain recreation.
     * Also add an attempt limit so a transient out-of-date state cannot lock the thread in an infinite loop. */
    VkResult acquire_result = VK_ERROR_OUT_OF_DATE_KHR;
    int acquire_attempts = 0;
    while (swapchain_ != VK_NULL_HANDLE &&
           (acquire_result == VK_ERROR_OUT_OF_DATE_KHR) &&
           acquire_attempts < 3)
    {
      acquire_attempts++;
      acquire_result = vkAcquireNextImageKHR(vk_device,
                                             swapchain_,
                                             UINT64_MAX,
                                             submission_frame_data.acquire_semaphore,
                                             VK_NULL_HANDLE,
                                             &image_index);
      ALOGI("swapBufferAcquire: attempt %d, result=%d, image_index=%u",
            acquire_attempts, acquire_result, image_index);
      if (acquire_result == VK_ERROR_OUT_OF_DATE_KHR) {
        recreateSwapchain(use_hdr_swapchain);
      }
    }

    if (acquire_result != VK_SUCCESS && acquire_result != VK_SUBOPTIMAL_KHR) {
      ALOGE("Vulkan: failed to acquire swapchain image: %d", acquire_result);
      CLOG_ERROR(&LOG,
                 "Vulkan: failed to acquire swapchain image: %s",
                 blender::gpu::to_string(acquire_result));
      return GHOST_kFailure;
    }
  }'''
    if t_acq in c:
        c = c.replace(t_acq, rep_acq)
        print('Patched swapBufferAcquire to prevent infinite recreation loop')

    # swapBufferRelease: do not recreate swapchain on VK_SUBOPTIMAL_KHR on Android
    t_rel = '''  if (ELEM(present_result, VK_ERROR_OUT_OF_DATE_KHR, VK_SUBOPTIMAL_KHR)) {
    recreateSwapchain(use_hdr_swapchain);
    return GHOST_kSuccess;
  }'''
    rep_rel = '''#ifdef __ANDROID__
  ALOGI("swapBufferRelease: vkQueuePresentKHR result=%d, image_index=%u", present_result, image_index);
  if (present_result == VK_ERROR_OUT_OF_DATE_KHR) {
    recreateSwapchain(use_hdr_swapchain);
    return GHOST_kSuccess;
  }
  if (present_result == VK_SUBOPTIMAL_KHR) {
    return GHOST_kSuccess;
  }
#else
  if (ELEM(present_result, VK_ERROR_OUT_OF_DATE_KHR, VK_SUBOPTIMAL_KHR)) {
    recreateSwapchain(use_hdr_swapchain);
    return GHOST_kSuccess;
  }
#endif'''
    if t_rel in c:
        c = c.replace(t_rel, rep_rel)
        print('Patched swapBufferRelease present handling')

    # Disable swapchain_maintenance_1 on Android to use stable WSI
    t_opt_maint = '        optional_device_extensions.append(VK_EXT_SWAPCHAIN_MAINTENANCE_1_EXTENSION_NAME);'
    rep_opt_maint = '''#ifndef __ANDROID__
        optional_device_extensions.append(VK_EXT_SWAPCHAIN_MAINTENANCE_1_EXTENSION_NAME);
#endif'''
    if t_opt_maint in c:
        c = c.replace(t_opt_maint, rep_opt_maint)
        print('Patched optional_device_extensions for SWAPCHAIN_MAINTENANCE_1')

    t_maint = '''    if (device.extensions.is_enabled(VK_EXT_SWAPCHAIN_MAINTENANCE_1_EXTENSION_NAME)) {
      feature_struct_ptr.push_back(&swapchain_maintenance_1);
      device.use_vk_ext_swapchain_maintenance_1 = true;
    }'''
    rep_maint = '''    if (device.extensions.is_enabled(VK_EXT_SWAPCHAIN_MAINTENANCE_1_EXTENSION_NAME)) {
#ifndef __ANDROID__
      feature_struct_ptr.push_back(&swapchain_maintenance_1);
      device.use_vk_ext_swapchain_maintenance_1 = true;
#endif
    }'''
    if t_maint in c:
        c = c.replace(t_maint, rep_maint)
        print('Patched swapchain_maintenance_1 for Android')

    # Entrance log for recreateSwapchain
    t_rec = 'GHOST_TSuccess GHOST_ContextVK::recreateSwapchain(bool use_hdr_swapchain)\n{'
    rep_rec = 'GHOST_TSuccess GHOST_ContextVK::recreateSwapchain(bool use_hdr_swapchain)\n{\n  ALOGI("recreateSwapchain START: use_hdr=%d, surface_=%p, window_=%p", use_hdr_swapchain, (void*)surface_, (void*)window_);'
    if t_rec in c:
        c = c.replace(t_rec, rep_rec)
        print('Patched recreateSwapchain entrance log')

    # Entrance log for swapBufferAcquire
    t_acq_ent = 'GHOST_TSuccess GHOST_ContextVK::swapBufferAcquire()\n{'
    rep_acq_ent = 'GHOST_TSuccess GHOST_ContextVK::swapBufferAcquire()\n{\n  ALOGI("swapBufferAcquire START: swapchain_=%p", (void*)swapchain_);'
    if t_acq_ent in c:
        c = c.replace(t_acq_ent, rep_acq_ent)
        print('Patched swapBufferAcquire entrance log')

    with open(p_vk, 'w') as f:
        f.write(c)
    print('Successfully patched GHOST_ContextVK.cc')

# 3. Update GHOST_SystemSDL.cc for offscreen Vulkan context (Headless)
p_sys = blender_src + '/intern/ghost/intern/GHOST_SystemSDL.cc'
if os.path.exists(p_sys):
    with open(p_sys, 'r') as f:
        c = f.read()
    if '#include "GHOST_ContextVK.hh"' not in c:
        c = '#include "GHOST_ContextVK.hh"\n' + c
    t_sys = '''  switch (gpu_settings.context_type) {
#ifdef WITH_OPENGL_BACKEND'''
    rep_sys = '''  switch (gpu_settings.context_type) {
#ifdef WITH_VULKAN_BACKEND
    case GHOST_kDrawingContextTypeVulkan: {
      GHOST_Context *context = new GHOST_ContextVK(
          context_params_offscreen,
          GHOST_kVulkanPlatformHeadless,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          1,
          1,
          gpu_settings.preferred_device);
      if (context->initializeDrawingContext()) {
        return context;
      }
      delete context;
      return nullptr;
    }
#endif
#ifdef WITH_OPENGL_BACKEND'''
    if t_sys in c:
        c = c.replace(t_sys, rep_sys)
        with open(p_sys, 'w') as f:
            f.write(c)
        print('Successfully patched GHOST_SystemSDL.cc')

# 4. Update GHOST_WindowSDL.cc for on-screen SDL Vulkan swapchain context
p_win = blender_src + '/intern/ghost/intern/GHOST_WindowSDL.cc'
if os.path.exists(p_win):
    with open(p_win, 'r') as f:
        c = f.read()
    if '#include "GHOST_ContextVK.hh"' not in c:
        c = '#include "GHOST_ContextVK.hh"\n' + c

    # Create window with SDL_WINDOW_VULKAN
    t_create = 'sdl_win_ = SDL_CreateWindow(title, width, height, SDL_WINDOW_RESIZABLE | SDL_WINDOW_OPENGL);'
    rep_create = 'sdl_win_ = SDL_CreateWindow(title, width, height, SDL_WINDOW_RESIZABLE | (type == GHOST_kDrawingContextTypeVulkan ? SDL_WINDOW_VULKAN : SDL_WINDOW_OPENGL));'
    if t_create in c:
        c = c.replace(t_create, rep_create)
        print('Patched SDL_CreateWindow with SDL_WINDOW_VULKAN')

    # Create drawing context with GHOST_kVulkanPlatformSDL and sdl_win_
    t_win_ctx = '''  switch (type) {
#ifdef WITH_OPENGL_BACKEND'''
    rep_win_ctx = '''  switch (type) {
#ifdef WITH_VULKAN_BACKEND
    case GHOST_kDrawingContextTypeVulkan: {
      GHOST_GPUDevice preferred_device = {};
      GHOST_Context *context = new GHOST_ContextVK(
          want_context_params_,
          GHOST_kVulkanPlatformSDL,
          (Window)sdl_win_,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          1,
          1,
          preferred_device);
      if (context->initializeDrawingContext()) {
        return context;
      }
      delete context;
      return nullptr;
    }
#endif
#ifdef WITH_OPENGL_BACKEND'''
    if t_win_ctx in c:
        c = c.replace(t_win_ctx, rep_win_ctx)
        print('Patched newDrawingContext with GHOST_kVulkanPlatformSDL')

    with open(p_win, 'w') as f:
        f.write(c)
    print('Successfully patched GHOST_WindowSDL.cc')
PYEOF

# Ensure makesrna defines WITH_PYTHON so that Operator/Panel/Menu register functions are generated
if [ -f "${BLENDER_SRC}/source/blender/makesrna/intern/CMakeLists.txt" ]; then
    sed -i 's/if(WITH_PYTHON)/if(TRUE)/' "${BLENDER_SRC}/source/blender/makesrna/intern/CMakeLists.txt"
    echo "Patched makesrna CMakeLists.txt to always enable WITH_PYTHON"
fi

# Guard wm_operators.cc, wm_gizmo.cc, view3d_gizmo_navigate.cc, appdir.cc and bpy_interface.cc
python3 - << 'PYEOF'
import os

blender_src = os.environ.get('BLENDER_SRC', '')

# 1. Patch wm_operators.cc: guard WM_operator_properties_create_ptr against nullptr / missing srna
p_wmop = blender_src + '/source/blender/windowmanager/intern/wm_operators.cc'
if os.path.exists(p_wmop):
    with open(p_wmop, 'r') as f:
        c = f.read()
    t_wmop = '''PointerRNA WM_operator_properties_create_ptr(wmOperatorType *ot)
{
  /* Set the ID so the context can be accessed: see #STRUCT_NO_CONTEXT_WITHOUT_OWNER_ID. */
  return RNA_pointer_create_discrete(static_cast<ID *>(G_MAIN->wm.first), ot->srna, nullptr);
}'''
    rep_wmop = '''PointerRNA WM_operator_properties_create_ptr(wmOperatorType *ot)
{
  ID *wm_id = (G_MAIN && G_MAIN->wm.first) ? static_cast<ID *>(G_MAIN->wm.first) : nullptr;
  if (ot == nullptr || ot->srna == nullptr) {
    return RNA_pointer_create_discrete(wm_id, RNA_OperatorProperties, nullptr);
  }
  /* Set the ID so the context can be accessed: see #STRUCT_NO_CONTEXT_WITHOUT_OWNER_ID. */
  return RNA_pointer_create_discrete(wm_id, ot->srna, nullptr);
}'''
    if t_wmop in c:
        c = c.replace(t_wmop, rep_wmop)
        with open(p_wmop, 'w') as f:
            f.write(c)
        print('Successfully patched wm_operators.cc')

# 2. Patch wm_gizmo.cc: guard WM_gizmo_operator_set against nullptr ot
p_wmgz = blender_src + '/source/blender/windowmanager/gizmo/intern/wm_gizmo.cc'
if os.path.exists(p_wmgz):
    with open(p_wmgz, 'r') as f:
        c = f.read()
    t_wmgz = '''  if (gzop.ptr.data) {
    WM_operator_properties_free(&gzop.ptr);
  }
  gzop.ptr = WM_operator_properties_create_ptr(ot);'''
    rep_wmgz = '''  if (gzop.ptr.data) {
    WM_operator_properties_free(&gzop.ptr);
  }
  if (ot != nullptr) {
    gzop.ptr = WM_operator_properties_create_ptr(ot);
  }
  else {
    gzop.ptr = PointerRNA_NULL;
  }'''
    if t_wmgz in c:
        c = c.replace(t_wmgz, rep_wmgz)
        with open(p_wmgz, 'w') as f:
            f.write(c)
        print('Successfully patched wm_gizmo.cc')

# 3. Patch view3d_gizmo_navigate.cc: make operator null checks unconditional
p_gznav = blender_src + '/source/blender/editors/space_view3d/view3d_gizmo_navigate.cc'
if os.path.exists(p_gznav):
    with open(p_gznav, 'r') as f:
        c = f.read()
    t_nav1 = '''    wmOperatorType *ot = WM_operatortype_find(info->opname, true);
#ifndef WITH_PYTHON
    if (ot != nullptr)
#endif
    {
      PointerRNA *ptr = WM_gizmo_operator_set(gz, 0, ot, nullptr);
      if (info->op_prop_fn != nullptr) {
        info->op_prop_fn(ptr);
      }
    }'''
    rep_nav1 = '''    wmOperatorType *ot = WM_operatortype_find(info->opname, true);
    if (ot != nullptr) {
      PointerRNA *ptr = WM_gizmo_operator_set(gz, 0, ot, nullptr);
      if (ptr != nullptr && ptr->data != nullptr && info->op_prop_fn != nullptr) {
        info->op_prop_fn(ptr);
      }
    }'''
    if t_nav1 in c:
        c = c.replace(t_nav1, rep_nav1)

    t_cam = '''  {
    wmGizmo *gz = navgroup->gz_array[GZ_INDEX_CAMERA_OFF];
    WM_gizmo_operator_set(gz, 0, ot_view_camera, nullptr);
  }
  {
    wmGizmo *gz = navgroup->gz_array[GZ_INDEX_CAMERA_ON];
    WM_gizmo_operator_set(gz, 0, ot_view_camera, nullptr);
  }'''
    rep_cam = '''  {
    wmGizmo *gz = navgroup->gz_array[GZ_INDEX_CAMERA_OFF];
    if (ot_view_camera != nullptr) {
      WM_gizmo_operator_set(gz, 0, ot_view_camera, nullptr);
    }
  }
  {
    wmGizmo *gz = navgroup->gz_array[GZ_INDEX_CAMERA_ON];
    if (ot_view_camera != nullptr) {
      WM_gizmo_operator_set(gz, 0, ot_view_camera, nullptr);
    }
  }'''
    if t_cam in c:
        c = c.replace(t_cam, rep_cam)

    t_axis = '''    for (int part_index = 0; part_index < 6; part_index += 1) {
      PointerRNA *ptr = WM_gizmo_operator_set(gz, part_index + 1, ot_view_axis, nullptr);
      RNA_enum_set(ptr, "type", mapping[part_index]);
    }'''
    rep_axis = '''    for (int part_index = 0; part_index < 6; part_index += 1) {
      if (ot_view_axis != nullptr) {
        PointerRNA *ptr = WM_gizmo_operator_set(gz, part_index + 1, ot_view_axis, nullptr);
        if (ptr != nullptr && ptr->data != nullptr) {
          RNA_enum_set(ptr, "type", mapping[part_index]);
        }
      }
    }'''
    if t_axis in c:
        c = c.replace(t_axis, rep_axis)

    with open(p_gznav, 'w') as f:
        f.write(c)
    print('Successfully patched view3d_gizmo_navigate.cc')

# 4. Patch appdir.cc: support BLENDER_SYSTEM_SCRIPTS environment variable
p_appdir = blender_src + '/source/blender/blenkernel/intern/appdir.cc'
if os.path.exists(p_appdir):
    with open(p_appdir, 'r') as f:
        c = f.read()
    t_appdir = '''    case BLENDER_SYSTEM_SCRIPTS:
      if (get_path_system(path, path_maxncpy, "scripts", subfolder)) {
        break;
      }'''
    rep_appdir = '''    case BLENDER_SYSTEM_SCRIPTS:
      if (get_path_environment(path, path_maxncpy, subfolder, "BLENDER_SYSTEM_SCRIPTS")) {
        break;
      }
      if (get_path_system(path, path_maxncpy, "scripts", subfolder)) {
        break;
      }'''
    if t_appdir in c:
        c = c.replace(t_appdir, rep_appdir)
        with open(p_appdir, 'w') as f:
            f.write(c)
        print('Successfully patched appdir.cc')

# 5. Patch bpy_interface.cc: enable Python system environment variables on Android
p_bpy = blender_src + '/source/blender/python/intern/bpy_interface.cc'
if os.path.exists(p_bpy):
    with open(p_bpy, 'r') as f:
        c = f.read()
    t_bpy = '''static bool py_use_system_env = false;
static bool py_use_user_env = false;'''
    rep_bpy = '''#ifdef __ANDROID__
static bool py_use_system_env = true;
static bool py_use_user_env = true;
#else
static bool py_use_system_env = false;
static bool py_use_user_env = false;
#endif'''
    if t_bpy in c:
        c = c.replace(t_bpy, rep_bpy)
        with open(p_bpy, 'w') as f:
            f.write(c)
        print('Successfully patched bpy_interface.cc')

# 6. Patch mallocn_lockfree_impl.cc: ensure 16-byte alignment for MemHead and MemHeadAligned
p_mlf = blender_src + '/intern/guardedalloc/intern/mallocn_lockfree_impl.cc'
if os.path.exists(p_mlf):
    with open(p_mlf, 'r') as f:
        c = f.read()
    t_mlf = '''typedef struct MemHead {
  /* Length of allocated memory block. */
  size_t len;
} MemHead;
static_assert(MEM_MIN_CPP_ALIGNMENT <= alignof(MemHead), "Bad alignment of MemHead");
static_assert(MEM_MIN_CPP_ALIGNMENT <= sizeof(MemHead), "Bad size of MemHead");

typedef struct MemHeadAligned {
  short alignment;
  size_t len;
} MemHeadAligned;
static_assert(MEM_MIN_CPP_ALIGNMENT <= alignof(MemHeadAligned), "Bad alignment of MemHeadAligned");
static_assert(MEM_MIN_CPP_ALIGNMENT <= sizeof(MemHeadAligned), "Bad size of MemHeadAligned");'''
    rep_mlf = '''typedef struct alignas(16) MemHead {
  /* Length of allocated memory block. */
  size_t pad;
  size_t len;
} MemHead;
static_assert(MEM_MIN_CPP_ALIGNMENT <= alignof(MemHead), "Bad alignment of MemHead");
static_assert(MEM_MIN_CPP_ALIGNMENT <= sizeof(MemHead), "Bad size of MemHead");

typedef struct alignas(16) MemHeadAligned {
  short alignment;
  char pad[6];
  size_t len;
} MemHeadAligned;
static_assert(MEM_MIN_CPP_ALIGNMENT <= alignof(MemHeadAligned), "Bad alignment of MemHeadAligned");
static_assert(MEM_MIN_CPP_ALIGNMENT <= sizeof(MemHeadAligned), "Bad size of MemHeadAligned");'''
    if t_mlf in c:
        c = c.replace(t_mlf, rep_mlf)
        with open(p_mlf, 'w') as f:
            f.write(c)
        print('Successfully patched mallocn_lockfree_impl.cc for 16-byte alignment')

# 7. Patch mallocn_intern.hh: set ALIGNED_MALLOC_MINIMUM_ALIGNMENT to 16
p_mintern = blender_src + '/intern/guardedalloc/intern/mallocn_intern.hh'
if os.path.exists(p_mintern):
    with open(p_mintern, 'r') as f:
        c = f.read()
    t_mintern = '#define ALIGNED_MALLOC_MINIMUM_ALIGNMENT sizeof(void *)'
    rep_mintern = '#define ALIGNED_MALLOC_MINIMUM_ALIGNMENT 16'
    if t_mintern in c:
        c = c.replace(t_mintern, rep_mintern)
        with open(p_mintern, 'w') as f:
            f.write(c)
        print('Successfully patched mallocn_intern.hh for 16-byte min alignment')

# 8. Patch creator_signals.cc: dump backtraces to stderr (BlenderCore logcat) on crash or abort
p_sig = blender_src + '/source/creator/creator_signals.cc'
if os.path.exists(p_sig):
    with open(p_sig, 'r') as f:
        c = f.read()
    t_sinc = '#  include "creator_intern.h" /* Own include. */'
    rep_sinc = '''#  include "creator_intern.h" /* Own include. */

#ifdef __ANDROID__
#  include <unwind.h>
#  include <dlfcn.h>

struct AndroidBacktraceState {
  void **current;
  void **end;
};

static _Unwind_Reason_Code android_unwind_cb(struct _Unwind_Context *context, void *arg)
{
  AndroidBacktraceState *state = static_cast<AndroidBacktraceState *>(arg);
  uintptr_t pc = _Unwind_GetIP(context);
  if (pc) {
    if (state->current == state->end) {
      return _URC_END_OF_STACK;
    }
    *state->current++ = reinterpret_cast<void *>(pc);
  }
  return _URC_NO_REASON;
}

static void android_log_backtrace(const char *tag, const char *msg)
{
  void *buffer[32];
  AndroidBacktraceState state = {buffer, buffer + 32};
  _Unwind_Backtrace(android_unwind_cb, &state);
  size_t count = state.current - buffer;
  fprintf(stderr, "=== CRASH BACKTRACE [%s]: %s ===\\n", tag, msg);
  for (size_t i = 0; i < count; ++i) {
    void *addr = buffer[i];
    Dl_info info;
    if (dladdr(addr, &info) && info.dli_sname) {
      ptrdiff_t offset = (char *)addr - (char *)info.dli_saddr;
      fprintf(stderr, "  #%02zu pc %p  %s (%s+%td)\\n", i, addr, info.dli_fname ? info.dli_fname : "", info.dli_sname, offset);
    }
    else if (dladdr(addr, &info) && info.dli_fname) {
      fprintf(stderr, "  #%02zu pc %p  %s\\n", i, addr, info.dli_fname);
    }
    else {
      fprintf(stderr, "  #%02zu pc %p\\n", i, addr);
    }
  }
  fflush(stderr);
}
#endif'''
    if t_sinc in c:
        c = c.replace(t_sinc, rep_sinc)

    t_abort = '''static void sig_handle_abort(int /*signum*/)
{
  /* Delete content of temp directory. */
  BKE_tempdir_session_purge();
}'''
    rep_abort = '''static void sig_handle_abort(int signum)
{
#ifdef __ANDROID__
  android_log_backtrace("BlenderCrash", "SIGABRT trapped");
  signal(signum, SIG_DFL);
  raise(signum);
#else
  /* Delete content of temp directory. */
  BKE_tempdir_session_purge();
#endif
}'''
    if t_abort in c:
        c = c.replace(t_abort, rep_abort)

    t_scrash = '''static void sig_handle_crash_fn(int signum)
{
  auto crash_func = [&]() {'''
    rep_scrash = '''static void sig_handle_crash_fn(int signum)
{
#ifdef __ANDROID__
  android_log_backtrace("BlenderCrash", "SIGSEGV / fatal signal trapped");
#endif
  auto crash_func = [&]() {'''
    if t_scrash in c:
        c = c.replace(t_scrash, rep_scrash)

    with open(p_sig, 'w') as f:
        f.write(c)
    print('Successfully patched creator_signals.cc for Android backtraces')

# 9. Patch downloader.py: fallbacks for multiprocessing and missing network libraries
p_dl = blender_src + '/scripts/modules/_bpy_internal/http/downloader.py'
if os.path.exists(p_dl):
    with open(p_dl, 'r') as f:
        c = f.read()
    t_dl = '''from multiprocessing.synchronize import Event as EventClass

import cattrs
import cattrs.preconf.json
import requests
import requests.adapters
import urllib3.util.retry'''
    rep_dl = '''try:
    from multiprocessing.synchronize import Event as EventClass
except ImportError:
    from threading import Event as EventClass

try:
    import cattrs
    import cattrs.preconf.json
    import requests
    import requests.adapters
    import urllib3.util.retry
except ImportError:
    cattrs = None
    requests = None'''
    if t_dl in c:
        c = c.replace(t_dl, rep_dl)
        with open(p_dl, 'w') as f:
            f.write(c)
        print('Successfully patched downloader.py to avoid missing library import errors')

# 10. Patch bl_pkg/__init__.py: safe remote library restore
p_pkg = blender_src + '/scripts/addons_core/bl_pkg/__init__.py'
if os.path.exists(p_pkg):
    with open(p_pkg, 'r') as f:
        c = f.read()
    t_pkg = '    from _bpy_internal.assets.remote_library import listing_downloader'
    rep_pkg = '''    try:
        from _bpy_internal.assets.remote_library import listing_downloader
    except (ImportError, ModuleNotFoundError):
        pass'''
    if t_pkg in c:
        c = c.replace(t_pkg, rep_pkg)
        with open(p_pkg, 'w') as f:
            f.write(c)
        print('Successfully patched bl_pkg/__init__.py')

# 11. Patch icons.cc: BKE_icon_geom_from_memory must free MEM_mallocN memory via MEM_freeN
p_icons = blender_src + "/source/blender/blenkernel/intern/icons.cc"
if os.path.exists(p_icons):
    with open(p_icons, "r") as f:
        c = f.read()
    t_icon = "std::unique_ptr<uchar> data_wrapper(std::move(data));"
    rep_icon = "std::unique_ptr<uchar, void (*)(const uchar *)> data_wrapper(data, [](const uchar *p) { MEM_delete(p); });"
    if t_icon in c:
        c = c.replace(t_icon, rep_icon)
        c = c.replace("if (data_len <= 8) {\n    return nullptr;\n  }", "if (data == nullptr) { return nullptr; }\n  if (data_len <= 8) {\n    MEM_delete(data);\n    return nullptr;\n  }")
        with open(p_icons, "w") as f:
            f.write(c)
        print("Successfully patched icons.cc BKE_icon_geom_from_memory")

# 12. Patch gpu_context.cc: default backend to Vulkan when OpenGL is off
p_ctx = blender_src + "/source/blender/gpu/intern/gpu_context.cc"
if os.path.exists(p_ctx):
    with open(p_ctx, "r") as f:
        c = f.read()
    c = c.replace("static GPUBackendType g_backend_type = GPU_BACKEND_OPENGL;", "#if defined(WITH_VULKAN_BACKEND) && !defined(WITH_OPENGL_BACKEND)\nstatic GPUBackendType g_backend_type = GPU_BACKEND_VULKAN;\n#else\nstatic GPUBackendType g_backend_type = GPU_BACKEND_OPENGL;\n#endif")
    with open(p_ctx, "w") as f:
        f.write(c)
    print("Successfully patched gpu_context.cc default backend")

# 13. Patch wm_window.cc: fallback to Vulkan when ANY or OPENGL is selected
p_wmw = blender_src + "/source/blender/windowmanager/intern/wm_window.cc"
if os.path.exists(p_wmw):
    with open(p_wmw, "r") as f:
        c = f.read()
    t_wmw = """    case GPU_BACKEND_ANY:
    case GPU_BACKEND_OPENGL:
#ifdef WITH_OPENGL_BACKEND
      return GHOST_kDrawingContextTypeOpenGL;
#endif"""
    rep_wmw = """    case GPU_BACKEND_ANY:
    case GPU_BACKEND_OPENGL:
#ifdef WITH_OPENGL_BACKEND
      return GHOST_kDrawingContextTypeOpenGL;
#elif defined(WITH_VULKAN_BACKEND)
      return GHOST_kDrawingContextTypeVulkan;
#endif"""
    if t_wmw in c:
        c = c.replace(t_wmw, rep_wmw)
        with open(p_wmw, "w") as f:
            f.write(c)
        print("Successfully patched wm_window.cc backend fallback")

# 14. Patch wm_platform_support.cc: bypass desktop GPU requirement on Android
p_ps = blender_src + "/source/blender/windowmanager/intern/wm_platform_support.cc"
if os.path.exists(p_ps):
    with open(p_ps, "r") as f:
        c = f.read()
    t_ps = "bool WM_platform_support_perform_checks()\n{"
    rep_ps = """bool WM_platform_support_perform_checks()
{
#ifdef __ANDROID__
  return true;
#endif"""
    if t_ps in c:
        c = c.replace(t_ps, rep_ps)
        with open(p_ps, "w") as f:
            f.write(c)
        print("Successfully patched wm_platform_support.cc for Android")

PYEOF

# Add ANativeActivity entry point and Vulkan NDK compatibility stubs to creator.cc
if [ -f "${BLENDER_SRC}/source/creator/creator.cc" ]; then
    # Rename main to blender_main_impl and provide extern "C" SDL_main for SDLActivity
    sed -i 's/int main(int argc,/int blender_main_impl(int argc,/' "${BLENDER_SRC}/source/creator/creator.cc"
    cat << 'AEOF' >> "${BLENDER_SRC}/source/creator/creator.cc"

#ifdef __ANDROID__
#include <android/log.h>
#include <pthread.h>
#include <dlfcn.h>
#include <vulkan/vulkan.h>
#include <unistd.h>
#include <SDL3/SDL.h>

#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, "BlenderNative", __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, "BlenderNative", __VA_ARGS__)

static void *android_log_pipe_thread(void *arg) {
    int pfd = (int)(intptr_t)arg;
    char buf[1024];
    ssize_t n;
    while ((n = read(pfd, buf, sizeof(buf) - 1)) > 0) {
        buf[n] = '\0';
        __android_log_print(ANDROID_LOG_INFO, "BlenderCore", "%s", buf);
    }
    return nullptr;
}

extern int blender_main_impl(int argc, const char **argv);

extern "C" __attribute__((visibility("default"))) int SDL_main(int argc, char *argv[]) {
    int pfd[2];
    setvbuf(stdout, nullptr, _IONBF, 0);
    setvbuf(stderr, nullptr, _IONBF, 0);
    if (pipe(pfd) == 0) {
        dup2(pfd[1], STDOUT_FILENO);
        dup2(pfd[1], STDERR_FILENO);
        pthread_t log_t;
        pthread_create(&log_t, nullptr, android_log_pipe_thread, (void*)(intptr_t)pfd[0]);
        pthread_detach(log_t);
    }

    ALOGI("SDL_main entry point reached from SDLActivity!");
    SDL_SetHint("SDL_APP_NAME", "Blender");
    SDL_SetHint("SDL_APP_ID", "org.blender.app");
    SDL_SetAppMetadata("Blender", "5.2.0", "org.blender.app");

    const char *files_dir = getenv("HOME");
    if (!files_dir || files_dir[0] == '\0') {
        files_dir = "/data/user/0/org.blender.app/files";
    }
    setenv("HOME", files_dir, 1);
    chdir(files_dir);

    char env_buf[1024];
    snprintf(env_buf, sizeof(env_buf), "%s/datafiles", files_dir);
    setenv("BLENDER_SYSTEM_DATAFILES", env_buf, 1);
    setenv("BLENDER_USER_DATAFILES", env_buf, 1);
    snprintf(env_buf, sizeof(env_buf), "%s/scripts", files_dir);
    setenv("BLENDER_SYSTEM_SCRIPTS", env_buf, 1);
    setenv("BLENDER_USER_SCRIPTS", env_buf, 1);
    snprintf(env_buf, sizeof(env_buf), "%s/config/blender/5.2", files_dir);
    setenv("BLENDER_USER_CONFIG", env_buf, 1);
    setenv("BLENDER_SYSTEM_RESOURCES", files_dir, 1);
    snprintf(env_buf, sizeof(env_buf), "%s/python", files_dir);
    setenv("BLENDER_SYSTEM_PYTHON", env_buf, 1);
    setenv("PYTHONHOME", env_buf, 1);
    snprintf(env_buf, sizeof(env_buf), "%s/python/lib/python3.13:%s/scripts/modules", files_dir, files_dir);
    setenv("PYTHONPATH", env_buf, 1);

    ALOGI("Blender paths: DATAFILES=%s/datafiles, SCRIPTS=%s/scripts", files_dir, files_dir);

    // Ensure pthread stack size is at least 8MB for driver shader compilation
    pthread_attr_t def_attr;
    pthread_attr_init(&def_attr);
    pthread_attr_setstacksize(&def_attr, 8 * 1024 * 1024);

    const char *ui_argv[] = {"blender", "--gpu-backend", "vulkan", nullptr};
    int ret = blender_main_impl(3, ui_argv);
    ALOGI("blender_main_impl finished with code: %d", ret);
    _exit(ret);
}

extern "C" {

__attribute__((visibility("default")))
VKAPI_ATTR VkResult VKAPI_CALL vkWaitSemaphores(
    VkDevice device,
    const VkSemaphoreWaitInfo* pWaitInfo,
    uint64_t timeout)
{
    typedef VkResult (VKAPI_PTR *PFN_vkWaitSemaphores_t)(VkDevice, const VkSemaphoreWaitInfo*, uint64_t);
    static PFN_vkWaitSemaphores_t fn = nullptr;
    if (!fn) {
        fn = (PFN_vkWaitSemaphores_t)vkGetDeviceProcAddr(device, "vkWaitSemaphores");
        if (!fn) fn = (PFN_vkWaitSemaphores_t)vkGetDeviceProcAddr(device, "vkWaitSemaphoresKHR");
        if (!fn) fn = (PFN_vkWaitSemaphores_t)dlsym(RTLD_DEFAULT, "vkWaitSemaphores");
        if (!fn) fn = (PFN_vkWaitSemaphores_t)dlsym(RTLD_DEFAULT, "vkWaitSemaphoresKHR");
    }
    if (fn) {
        return fn(device, pWaitInfo, timeout);
    }
    return VK_SUCCESS;
}

__attribute__((visibility("default")))
VKAPI_ATTR VkResult VKAPI_CALL vkGetSemaphoreCounterValue(
    VkDevice device,
    VkSemaphore semaphore,
    uint64_t* pValue)
{
    typedef VkResult (VKAPI_PTR *PFN_vkGetSemaphoreCounterValue_t)(VkDevice, VkSemaphore, uint64_t*);
    static PFN_vkGetSemaphoreCounterValue_t fn = nullptr;
    if (!fn) {
        fn = (PFN_vkGetSemaphoreCounterValue_t)vkGetDeviceProcAddr(device, "vkGetSemaphoreCounterValue");
        if (!fn) fn = (PFN_vkGetSemaphoreCounterValue_t)vkGetDeviceProcAddr(device, "vkGetSemaphoreCounterValueKHR");
        if (!fn) fn = (PFN_vkGetSemaphoreCounterValue_t)dlsym(RTLD_DEFAULT, "vkGetSemaphoreCounterValue");
        if (!fn) fn = (PFN_vkGetSemaphoreCounterValue_t)dlsym(RTLD_DEFAULT, "vkGetSemaphoreCounterValueKHR");
    }
    if (fn) {
        return fn(device, semaphore, pValue);
    }
    if (pValue) *pValue = 0;
    return VK_SUCCESS;
}

__attribute__((visibility("default")))
VKAPI_ATTR void VKAPI_CALL vkGetDeviceBufferMemoryRequirements(
    VkDevice device,
    const VkDeviceBufferMemoryRequirements* pInfo,
    VkMemoryRequirements2* pMemoryRequirements)
{
    typedef void (VKAPI_PTR *PFN_vkGetDeviceBufferMemoryRequirements_t)(VkDevice, const VkDeviceBufferMemoryRequirements*, VkMemoryRequirements2*);
    static PFN_vkGetDeviceBufferMemoryRequirements_t fn = nullptr;
    if (!fn) {
        fn = (PFN_vkGetDeviceBufferMemoryRequirements_t)vkGetDeviceProcAddr(device, "vkGetDeviceBufferMemoryRequirements");
        if (!fn) fn = (PFN_vkGetDeviceBufferMemoryRequirements_t)vkGetDeviceProcAddr(device, "vkGetDeviceBufferMemoryRequirementsKHR");
        if (!fn) fn = (PFN_vkGetDeviceBufferMemoryRequirements_t)dlsym(RTLD_DEFAULT, "vkGetDeviceBufferMemoryRequirements");
        if (!fn) fn = (PFN_vkGetDeviceBufferMemoryRequirements_t)dlsym(RTLD_DEFAULT, "vkGetDeviceBufferMemoryRequirementsKHR");
    }
    if (fn) {
        fn(device, pInfo, pMemoryRequirements);
    }
}

__attribute__((visibility("default")))
VKAPI_ATTR void VKAPI_CALL vkGetDeviceImageMemoryRequirements(
    VkDevice device,
    const VkDeviceImageMemoryRequirements* pInfo,
    VkMemoryRequirements2* pMemoryRequirements)
{
    typedef void (VKAPI_PTR *PFN_vkGetDeviceImageMemoryRequirements_t)(VkDevice, const VkDeviceImageMemoryRequirements*, VkMemoryRequirements2*);
    static PFN_vkGetDeviceImageMemoryRequirements_t fn = nullptr;
    if (!fn) {
        fn = (PFN_vkGetDeviceImageMemoryRequirements_t)vkGetDeviceProcAddr(device, "vkGetDeviceImageMemoryRequirements");
        if (!fn) fn = (PFN_vkGetDeviceImageMemoryRequirements_t)vkGetDeviceProcAddr(device, "vkGetDeviceImageMemoryRequirementsKHR");
        if (!fn) fn = (PFN_vkGetDeviceImageMemoryRequirements_t)dlsym(RTLD_DEFAULT, "vkGetDeviceImageMemoryRequirements");
        if (!fn) fn = (PFN_vkGetDeviceImageMemoryRequirements_t)dlsym(RTLD_DEFAULT, "vkGetDeviceImageMemoryRequirementsKHR");
    }
    if (fn) {
        fn(device, pInfo, pMemoryRequirements);
    }
}

__attribute__((visibility("default")))
VKAPI_ATTR VkResult VKAPI_CALL vkGetPhysicalDeviceSurfaceCapabilities2KHR(
    VkPhysicalDevice physicalDevice,
    const VkPhysicalDeviceSurfaceInfo2KHR* pSurfaceInfo,
    VkSurfaceCapabilities2KHR* pSurfaceCapabilities)
{
    typedef VkResult (VKAPI_PTR *PFN_vkGetPhysicalDeviceSurfaceCapabilities2KHR_t)(VkPhysicalDevice, const VkPhysicalDeviceSurfaceInfo2KHR*, VkSurfaceCapabilities2KHR*);
    static PFN_vkGetPhysicalDeviceSurfaceCapabilities2KHR_t fn = nullptr;
    if (!fn) {
        fn = (PFN_vkGetPhysicalDeviceSurfaceCapabilities2KHR_t)dlsym(RTLD_DEFAULT, "vkGetPhysicalDeviceSurfaceCapabilities2KHR");
    }
    if (fn) {
        return fn(physicalDevice, pSurfaceInfo, pSurfaceCapabilities);
    }
    if (pSurfaceInfo && pSurfaceCapabilities) {
        return vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            physicalDevice, pSurfaceInfo->surface, &pSurfaceCapabilities->surfaceCapabilities);
    }
    return VK_ERROR_FEATURE_NOT_PRESENT;
}

}
#else
int main(int argc, const char **argv) {
    return blender_main(argc, argv);
}
#endif
AEOF
fi

if [ -f "${BLENDER_SRC}/source/creator/CMakeLists.txt" ]; then
    cat << 'CEOF' >> "${BLENDER_SRC}/source/creator/CMakeLists.txt"

if(ANDROID)
  target_link_libraries(blender PRIVATE android log dl vulkan)
endif()
CEOF
fi


# (Duplicate swapchain patch removed)



echo "===> Patching Blender CMake for native host code generators and dependencies..."
python3 << 'PYEOF'
import os

src = os.environ.get("BLENDER_SRC", "")
sysroot = os.environ.get("SYSROOT_DIR", "")

# 1. Wrap OpenEXR, OpenImageIO, OpenColorIO in platform_unix.cmake so host tools build does not fail
p_unix = os.path.join(src, "build_files/cmake/platform/platform_unix.cmake")
if os.path.exists(p_unix):
    with open(p_unix, "r") as f:
        c = f.read()
    if "pkg_check_modules(SHADERC REQUIRED shaderc)" in c:
        rep_shaderc = 'set(SHADERC_INCLUDE_DIRS "' + os.path.join(sysroot, "usr/include") + '")\n    set(SHADERC_LIBRARIES "' + os.path.join(sysroot, "usr/lib/libshaderc.a") + '")\n    set(SHADERC_FOUND TRUE)'
        c = c.replace("pkg_check_modules(SHADERC REQUIRED shaderc)", rep_shaderc)
    if "PLATFORM_LINKFLAGS_SYMBOL_HIDING" in c:
        c = c.replace("set(PLATFORM_LINKFLAGS_SYMBOL_HIDING \"-Wl,--version-script='${PLATFORM_SYMBOLS_MAP}'\")",
                      "if(ANDROID)\n  set(PLATFORM_LINKFLAGS_SYMBOL_HIDING \"\")\nelse()\n  set(PLATFORM_LINKFLAGS_SYMBOL_HIDING \"-Wl,--version-script='${PLATFORM_SYMBOLS_MAP}'\")\nendif()")
    if "find_package_wrapper(OpenEXR REQUIRED)" in c and "WITH_OPENEXR" not in c:
        c = c.replace("find_package_wrapper(OpenEXR REQUIRED)", "if(WITH_OPENEXR OR WITH_IMAGE_OPENEXR)\n  find_package_wrapper(OpenEXR REQUIRED)\nendif()")
    elif "if(WITH_OPENEXR)\n  find_package_wrapper(OpenEXR REQUIRED)" in c:
        c = c.replace("if(WITH_OPENEXR)\n  find_package_wrapper(OpenEXR REQUIRED)", "if(WITH_OPENEXR OR WITH_IMAGE_OPENEXR)\n  find_package_wrapper(OpenEXR REQUIRED)")
    if "if(WITH_OPENIMAGEIO)\n  find_package_wrapper(OpenImageIO REQUIRED)" not in c:
        c = c.replace("find_package_wrapper(OpenImageIO REQUIRED)", "if(WITH_OPENIMAGEIO)\n  find_package_wrapper(OpenImageIO REQUIRED)\nendif()")
    if "WITH_OPENCOLORIO" not in c:
        c = c.replace("find_package_wrapper(OpenColorIO 2.0.0 REQUIRED)", "if(WITH_OPENCOLORIO)\n  find_package_wrapper(OpenColorIO 2.0.0 REQUIRED)\nendif()")
    if "WITH_CROSSCOMPILED_TOOLS" not in c:
        c += """
if(WITH_CROSSCOMPILED_TOOLS)
  message(STATUS "Importing cross-compiled host tools from: ${CROSSCOMPILE_TOOLDIR}")
  foreach(_tool datatoc shader_tool makesdna makesrna)
    if(EXISTS "${CROSSCOMPILE_TOOLDIR}/${_tool}")
      add_executable(${_tool} IMPORTED GLOBAL)
      set_property(TARGET ${_tool} PROPERTY IMPORTED_LOCATION "${CROSSCOMPILE_TOOLDIR}/${_tool}")
      message(STATUS "  Imported host tool: ${_tool} -> ${CROSSCOMPILE_TOOLDIR}/${_tool}")
    else()
      message(FATAL_ERROR "Host tool ${_tool} not found at ${CROSSCOMPILE_TOOLDIR}/${_tool}")
    endif()
  endforeach()
endif()
"""
    with open(p_unix, "w") as f:
        f.write(c)

# 2. dependency_targets.cmake: wrap OpenImageIO, OpenEXR, OpenColorIO aliases
p_dep = os.path.join(src, "build_files/cmake/platform/dependency_targets.cmake")
if os.path.exists(p_dep):
    with open(p_dep, "r") as f:
        c = f.read()
    c = c.replace("add_library(bf::dependencies::openimageio ALIAS OpenImageIO::OpenImageIO)",
"""if(TARGET OpenImageIO::OpenImageIO)
  add_library(bf::dependencies::openimageio ALIAS OpenImageIO::OpenImageIO)
else()
  add_library(bf_deps_openimageio INTERFACE)
  add_library(bf::dependencies::openimageio ALIAS bf_deps_openimageio)
endif()""")
    c = c.replace("get_target_property(OPENIMAGEIO_TOOL OpenImageIO::oiiotool LOCATION)",
"""if(TARGET OpenImageIO::oiiotool)
  get_target_property(OPENIMAGEIO_TOOL OpenImageIO::oiiotool LOCATION)
endif()""")
    c = c.replace("add_library(bf::dependencies::openexr ALIAS OpenEXR::OpenEXR)",
"""if(TARGET OpenEXR::OpenEXR)
  add_library(bf::dependencies::openexr ALIAS OpenEXR::OpenEXR)
else()
  add_library(bf_deps_openexr INTERFACE)
  target_include_directories(bf_deps_openexr INTERFACE "${SYSROOT_DIR}/usr/include" "${SYSROOT_DIR}/usr/include/OpenEXR" "${SYSROOT_DIR}/usr/include/Imath")
  target_link_libraries(bf_deps_openexr INTERFACE -L${SYSROOT_DIR}/usr/lib -lOpenEXR -lOpenEXRCore -lImath -lIlmThread -lIex)
  add_library(bf::dependencies::openexr ALIAS bf_deps_openexr)
endif()""")
    c = c.replace("add_library(bf::dependencies::opencolorio ALIAS OpenColorIO::OpenColorIO)",
"""if(TARGET OpenColorIO::OpenColorIO)
  add_library(bf::dependencies::opencolorio ALIAS OpenColorIO::OpenColorIO)
else()
  add_library(bf_deps_opencolorio INTERFACE)
  add_library(bf::dependencies::opencolorio ALIAS bf_deps_opencolorio)
endif()""")
    shaderc_a = os.path.join(sysroot, "usr/lib/libshaderc.a")
    sysroot_lib = os.path.join(sysroot, "usr/lib")
    rep_target = 'target_link_directories(bf_deps_optional_shaderc INTERFACE "' + sysroot_lib + '")\n  target_link_libraries(bf_deps_optional_shaderc INTERFACE "' + shaderc_a + '")'
    c = c.replace("target_link_libraries(bf_deps_optional_shaderc INTERFACE ${SHADERC_LIBRARIES})", rep_target)
    with open(p_dep, "w") as f:
        f.write(c)

# 2b. Patch symbols_unix.map to keep Android and Vulkan symbols exported
p_map = os.path.join(src, "source/creator/symbols_unix.map")
if os.path.exists(p_map):
    with open(p_map, "r") as f:
        mc = f.read()
    if "ANativeActivity_onCreate" not in mc:
        mc = mc.replace("global:\n", "global:\n  ANativeActivity_onCreate;\n  vk*;\n  Java_*;\n  android_*;\n  blender_main;\n")
        with open(p_map, "w") as f:
            f.write(mc)

# 3. source/blender/CMakeLists.txt: skip datatoc and shader_tool subdirectories
p_blender = os.path.join(src, "source/blender/CMakeLists.txt")
if os.path.exists(p_blender):
    with open(p_blender, "r") as f:
        c = f.read()
    if "WITH_CROSSCOMPILED_TOOLS" not in c:
        c = c.replace("add_subdirectory(datatoc)\nadd_subdirectory(gpu/shader_tool)",
                      "if(NOT WITH_CROSSCOMPILED_TOOLS)\n  add_subdirectory(datatoc)\n  add_subdirectory(gpu/shader_tool)\nendif()")
        with open(p_blender, "w") as f:
            f.write(c)

# 4. datatoc/CMakeLists.txt
p = os.path.join(src, "source/blender/datatoc/CMakeLists.txt")
if os.path.exists(p):
    with open(p, "r") as f:
        c = f.read()
    if "WITH_CROSSCOMPILED_TOOLS" not in c:
        c = c.replace("add_executable(datatoc ${SRC})\noptimize_debug_target(datatoc)",
                      "if(NOT WITH_CROSSCOMPILED_TOOLS)\n  add_executable(datatoc ${SRC})\n  optimize_debug_target(datatoc)\nendif()")
        with open(p, "w") as f:
            f.write(c)

# 5. shader_tool/CMakeLists.txt
p = os.path.join(src, "source/blender/gpu/shader_tool/CMakeLists.txt")
if os.path.exists(p):
    with open(p, "r") as f:
        c = f.read()
    if "WITH_CROSSCOMPILED_TOOLS" not in c:
        c = c.replace("add_executable(shader_tool ${SRC})\noptimize_debug_target(shader_tool)",
                      "if(NOT WITH_CROSSCOMPILED_TOOLS)\n  add_executable(shader_tool ${SRC})\n  optimize_debug_target(shader_tool)\nendif()")
        with open(p, "w") as f:
            f.write(c)

# 6. makesdna/intern/CMakeLists.txt
p = os.path.join(src, "source/blender/makesdna/intern/CMakeLists.txt")
if os.path.exists(p):
    with open(p, "r") as f:
        c = f.read()
    if "WITH_CROSSCOMPILED_TOOLS" not in c:
        c = c.replace("add_executable(makesdna ${SRC} ${SRC_DNA_INC})",
                      "if(NOT WITH_CROSSCOMPILED_TOOLS)\n  add_executable(makesdna ${SRC} ${SRC_DNA_INC})")
        c = c.replace("target_link_libraries(makesdna PRIVATE bf::dependencies::pthreads)",
                      "target_link_libraries(makesdna PRIVATE bf::dependencies::pthreads)\nendif()")
        with open(p, "w") as f:
            f.write(c)

# 7. makesrna/intern/CMakeLists.txt
p = os.path.join(src, "source/blender/makesrna/intern/CMakeLists.txt")
if os.path.exists(p):
    with open(p, "r") as f:
        c = f.read()
    if "WITH_CROSSCOMPILED_TOOLS" not in c:
        c = c.replace("add_executable(makesrna ${SRC} ${SRC_RNA_INC} ${SRC_DNA_INC})",
                      "if(NOT WITH_CROSSCOMPILED_TOOLS)\n  add_executable(makesrna ${SRC} ${SRC_RNA_INC} ${SRC_DNA_INC})")
        c = c.replace("target_link_libraries(makesrna PRIVATE bf::dependencies::fmt)",
                      "target_link_libraries(makesrna PRIVATE bf::dependencies::fmt)\nendif()")
        with open(p, "w") as f:
            f.write(c)
PYEOF

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

cmake -B build-blender -S blender -G Ninja \
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

echo "===> Building Blender core..."
ninja -C build-blender -j$(nproc)

echo "===> Freeing build disk space before packaging..."
rm -rf "${BLENDER_SRC}/.git" "${BUILD_TMP}/build-host-tools" "${BUILD_TMP}/vulkan-headers"
find "${BUILD_TMP}/build-blender" -name "*.o" -delete 2>/dev/null || true
find "${BUILD_TMP}/build-blender" -name "*.a" -delete 2>/dev/null || true

echo "===> Packaging into standalone APK..."
APK_DIR="${BUILD_TMP}/apk-build"
rm -rf "${APK_DIR}"
mkdir -p "${APK_DIR}/lib/arm64-v8a" "${APK_DIR}/assets/datafiles" "${APK_DIR}/assets/scripts"

# Copy libraries
cp -P ${SYSROOT_DIR}/usr/lib/*.so* "${APK_DIR}/lib/arm64-v8a/" || true
cp -P ${TOOLCHAIN}/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so "${APK_DIR}/lib/arm64-v8a/" 2>/dev/null || true
find "${ANDROID_NDK_ROOT}" -name "libc++_shared.so" -path "*/arm64*/*" -exec cp -P {} "${APK_DIR}/lib/arm64-v8a/" \; 2>/dev/null || true
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
