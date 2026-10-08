#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Patch] Injecting NativeActivity lifecycle into creator.cc..."
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



