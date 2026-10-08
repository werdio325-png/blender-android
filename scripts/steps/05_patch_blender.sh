#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Step 05] Applying modular patches to Blender source..."
bash "${SCRIPT_DIR}/patches/patch_blender_core.sh"
bash "${SCRIPT_DIR}/patches/patch_ghost_sdl3.sh"
bash "${SCRIPT_DIR}/patches/patch_vulkan_mali_shim.sh"
bash "${SCRIPT_DIR}/patches/patch_fixes_and_python.sh"
bash "${SCRIPT_DIR}/patches/patch_native_activity.sh"
bash "${SCRIPT_DIR}/patches/patch_cmake_build_targets.sh"
