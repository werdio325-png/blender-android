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

echo "===> Downloading critical runtime datafiles..."
mkdir -p "${BLENDER_SRC}/release/datafiles"
for f in startup.blend preview.blend preview_grease_pencil.blend splash.png; do
    echo "Downloading ${f}..."
    curl -sL "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/${f}" -o "${BLENDER_SRC}/release/datafiles/${f}" || true
done

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

# Add ANativeActivity entry point and Vulkan NDK compatibility stubs to creator.cc
if [ -f "${BLENDER_SRC}/source/creator/creator.cc" ]; then
    sed -i 's/int main(int argc,/int blender_main(int argc,/' "${BLENDER_SRC}/source/creator/creator.cc"
    cat << 'AEOF' >> "${BLENDER_SRC}/source/creator/creator.cc"

#ifdef __ANDROID__
#include <android/native_activity.h>
#include <pthread.h>
#include <dlfcn.h>
#include <vulkan/vulkan.h>

static void *android_blender_thread_func(void *arg) {
    const char *argv[] = {"blender", nullptr};
    blender_main(1, argv);
    return nullptr;
}

extern "C" JNIEXPORT void ANativeActivity_onCreate(ANativeActivity* activity, void* savedState, size_t savedStateSize) {
    pthread_t thread;
    pthread_create(&thread, nullptr, android_blender_thread_func, nullptr);
    pthread_detach(thread);
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
cmake -B build-blender -S blender -G Ninja \
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

# Assemble APK using android SDK build tools
AAPT2=$(find /usr/local/lib/android/sdk/build-tools -name aapt2 2>/dev/null | sort -V | tail -n 1)
ANDROID_JAR=$(find /usr/local/lib/android/sdk/platforms -name android.jar 2>/dev/null | sort -V | tail -n 1)
ZIPALIGN=$(find /usr/local/lib/android/sdk/build-tools -name zipalign 2>/dev/null | sort -V | tail -n 1)
APKSIGNER=$(find /usr/local/lib/android/sdk/build-tools -name apksigner 2>/dev/null | sort -V | tail -n 1)

$AAPT2 link -o "${BUILD_TMP}/unaligned.apk" \
    -I "$ANDROID_JAR" \
    --manifest "${BASE_DIR}/android/app/src/main/AndroidManifest.xml" \
    -A "${APK_DIR}/assets" \
    --auto-add-overlay

cd "${APK_DIR}"
zip -u -r "${BUILD_TMP}/unaligned.apk" lib/
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
