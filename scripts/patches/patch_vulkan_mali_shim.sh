#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Patch] Applying Vulkan Mali GPU hybrid compatibility shim..."

python3 - << 'PYEOF'
import os

blender_src = os.environ.get('BLENDER_SRC', '')

# -----------------------------------------------------------------------------
# 1. Patch vk_backend.cc: dynamically detect geometryShader and add mobile workarounds
# -----------------------------------------------------------------------------
p_backend = os.path.join(blender_src, 'source/blender/gpu/vulkan/vk_backend.cc')
if os.path.exists(p_backend):
    with open(p_backend, 'r') as f:
        c = f.read()

    # Capabilities: don't unconditionally force geometry_shader_support on Android
    t_geom = 'GCaps.geometry_shader_support = true;'
    rep_geom = '''#ifdef __ANDROID__
  GCaps.geometry_shader_support = device.physical_device_features_get().geometryShader;
#else
  GCaps.geometry_shader_support = true;
#endif'''
    if t_geom in c:
        c = c.replace(t_geom, rep_geom)
        print('Patched vk_backend.cc: geometry_shader_support query')

    # Workarounds: enable static viewport/scissor workaround on Android (Mali/Adreno)
    t_work = 'if (GPU_type_matches(GPU_DEVICE_QUALCOMM, GPU_OS_ANY, GPU_DRIVER_ANY)) {\n    workarounds.static_viewport_scissor = true;\n  }'
    rep_work = '''#ifdef __ANDROID__
  /* Force mobile TBDR workarounds for Mali and mobile GPU drivers */
  workarounds.static_viewport_scissor = true;
#endif
  ''' + t_work
    if t_work in c and 'Force mobile TBDR workarounds' not in c:
        c = c.replace(t_work, rep_work)
        print('Patched vk_backend.cc: mobile TBDR workarounds')

    with open(p_backend, 'w') as f:
        f.write(c)

# -----------------------------------------------------------------------------
# 2. Patch vk_graphics_pipeline.hh: safe fallback for dualSrcBlend on Mali
# -----------------------------------------------------------------------------
p_gp = os.path.join(blender_src, 'source/blender/gpu/vulkan/vk_graphics_pipeline.hh')
if os.path.exists(p_gp):
    with open(p_gp, 'r') as f:
        c = f.read()

    t_custom_blend = '''      case GPU_BLEND_CUSTOM:
        attachment_state.srcColorBlendFactor = VK_BLEND_FACTOR_ONE;
        attachment_state.dstColorBlendFactor = VK_BLEND_FACTOR_SRC1_COLOR;
        attachment_state.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        attachment_state.dstAlphaBlendFactor = VK_BLEND_FACTOR_SRC1_ALPHA;
        break;'''

    rep_custom_blend = '''      case GPU_BLEND_CUSTOM:
#ifdef __ANDROID__
        if (!VKBackend::get().device.physical_device_features_get().dualSrcBlend) {
          /* Fallback for mobile GPUs (Mali) without dual-source blending */
          attachment_state.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
          attachment_state.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
          attachment_state.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
          attachment_state.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        }
        else
#endif
        {
          attachment_state.srcColorBlendFactor = VK_BLEND_FACTOR_ONE;
          attachment_state.dstColorBlendFactor = VK_BLEND_FACTOR_SRC1_COLOR;
          attachment_state.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
          attachment_state.dstAlphaBlendFactor = VK_BLEND_FACTOR_SRC1_ALPHA;
        }
        break;'''

    if t_custom_blend in c:
        c = c.replace(t_custom_blend, rep_custom_blend)
        with open(p_gp, 'w') as f:
            f.write(c)
        print('Patched vk_graphics_pipeline.hh: dualSrcBlend fallback')

# -----------------------------------------------------------------------------
# 3. Patch vk_texture.cc: BCn texture format compatibility for Mali
# -----------------------------------------------------------------------------
p_tex = os.path.join(blender_src, 'source/blender/gpu/vulkan/vk_texture.cc')
if os.path.exists(p_tex):
    with open(p_tex, 'r') as f:
        c = f.read()

    t_init_fmt = '''  if (device_format_ == TextureFormat::SFLOAT_32_32_32) {
    device_format_ = TextureFormat::SFLOAT_32_32_32_32;
  }'''

    rep_init_fmt = '''  if (device_format_ == TextureFormat::SFLOAT_32_32_32) {
    device_format_ = TextureFormat::SFLOAT_32_32_32_32;
  }
#ifdef __ANDROID__
  /* Fallback unsupported compressed formats (BCn) on Mali to RGBA8 */
  if (format_flag_ & GPU_FORMAT_COMPRESSED) {
    const VKDevice &dev = VKBackend::get().device;
    VkFormat vk_fmt = to_vk_format(device_format_);
    VkFormatProperties format_props = {};
    vkGetPhysicalDeviceFormatProperties(dev.physical_device_get(), vk_fmt, &format_props);
    if ((format_props.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT) == 0) {
      device_format_ = (format_ == TextureFormat::SRGB_DXT1 ||
                        format_ == TextureFormat::SRGB_DXT3 ||
                        format_ == TextureFormat::SRGB_DXT5) ?
                           TextureFormat::SRGBA_8_8_8_8 :
                           TextureFormat::UNORM_8_8_8_8;
    }
  }
#endif'''

    if t_init_fmt in c and 'Fallback unsupported compressed formats' not in c:
        c = c.replace(t_init_fmt, rep_init_fmt)
        with open(p_tex, 'w') as f:
            f.write(c)
        print('Patched vk_texture.cc: BCn compressed texture format fallback')

# -----------------------------------------------------------------------------
# 4. Patch threads.cc: 8MB thread stack size on Android to prevent Mali driver overflow
# -----------------------------------------------------------------------------
p_th = os.path.join(blender_src, 'source/blender/blenlib/intern/threads.cc')
if os.path.exists(p_th):
    with open(p_th, 'r') as f:
        c = f.read()

    t_th = 'pthread_create(&tslot.pthread, nullptr, tslot_thread_start, &tslot);'
    rep_th = '''#ifdef __ANDROID__
      pthread_attr_t t_attr;
      pthread_attr_init(&t_attr);
      pthread_attr_setstacksize(&t_attr, 8 * 1024 * 1024);
      pthread_create(&tslot.pthread, &t_attr, tslot_thread_start, &tslot);
      pthread_attr_destroy(&t_attr);
#else
      pthread_create(&tslot.pthread, nullptr, tslot_thread_start, &tslot);
#endif'''

    if t_th in c:
        c = c.replace(t_th, rep_th)
        with open(p_th, 'w') as f:
            f.write(c)
        print('Patched threads.cc: 8MB thread stack size on Android')

print('Vulkan Mali compatibility shim patch applied successfully.')
PYEOF
