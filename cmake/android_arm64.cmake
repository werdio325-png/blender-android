# CMake Toolchain for Blender Android ARM64
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION 29)
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)
set(CMAKE_ANDROID_NDK_TOOLCHAIN_VERSION clang)
set(CMAKE_ANDROID_STL_TYPE c++_shared)

# Compiler flags for Bionic compatibility
add_definitions(-D__ANDROID__)
add_definitions(-D_GNU_SOURCE)
add_definitions(-DWITH_VULKAN)
add_definitions(-DWITH_GHOST_SDL)
