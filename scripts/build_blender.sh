#!/usr/bin/env bash
# ==============================================================================
# Blender for Android (Native ARM64 Port) — Master Build Orchestrator
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "=============================================================="
echo "Starting Modular Build for Blender Android ARM64"
echo "Working directory: ${BASE_DIR}"
echo "=============================================================="

# Run build stages sequentially
bash "${SCRIPT_DIR}/steps/01_prepare_sysroot.sh"
bash "${SCRIPT_DIR}/steps/02_build_shaderc.sh"
bash "${SCRIPT_DIR}/steps/03_fetch_sources.sh"
bash "${SCRIPT_DIR}/steps/04_fetch_assets.sh"
bash "${SCRIPT_DIR}/steps/05_patch_blender.sh"
bash "${SCRIPT_DIR}/steps/06_build_host_tools.sh"
bash "${SCRIPT_DIR}/steps/07_configure_cmake.sh"
bash "${SCRIPT_DIR}/steps/08_compile_blender.sh"
bash "${SCRIPT_DIR}/steps/09_package_apk.sh"

echo "=============================================================="
echo "Build complete! Output: Blender-Android-arm64.apk"
echo "=============================================================="
