#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Patch] Applying Blender core Android compatibility patches..."
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


