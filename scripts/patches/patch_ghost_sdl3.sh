#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Patch] Applying GHOST SDL3 and Vulkan context patches..."
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
    # Bypass strict desktop features block by replacing the whole struct setup
    if 'device_features.geometryShader = VK_TRUE;' in c:
        idx_feat = c.find('VkPhysicalDeviceFeatures device_features = {};')
        end_feat = c.find('device_create_info.pNext = feature_struct_ptr[0];', idx_feat)
        if idx_feat != -1 and end_feat != -1:
            end_feat += len('device_create_info.pNext = feature_struct_ptr[0];')
            old_chunk = c[idx_feat:end_feat]
            rep_chunk = '''#ifndef __ANDROID__
''' + old_chunk + '''
#else
    VkPhysicalDeviceFeatures device_features = device.features.features;
    device_features.robustBufferAccess = VK_FALSE;
    VkDeviceCreateInfo device_create_info = {};
    device_create_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_create_info.queueCreateInfoCount = uint32_t(queue_create_infos.size());
    device_create_info.pQueueCreateInfos = queue_create_infos.data();
    device_create_info.enabledExtensionCount = uint32_t(device.extensions.enabled.size());
    device_create_info.ppEnabledExtensionNames = device.extensions.enabled.data();
    device_create_info.pEnabledFeatures = &device_features;
    device_create_info.pNext = nullptr;
#endif'''
            c = c[:idx_feat] + rep_chunk + c[end_feat:]
            print('Successfully patched create_device in GHOST_ContextVK.cc for Android Mali!')

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

