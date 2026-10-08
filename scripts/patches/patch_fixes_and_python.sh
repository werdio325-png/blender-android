#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Patch] Applying window, Python, allocator and crash handler patches..."
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

