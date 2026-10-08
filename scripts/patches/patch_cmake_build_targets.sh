#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Patch] Configuring CMake build targets for Android..."
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

