#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> [Step 08] Compiling Blender core with Ninja..."
cd "${BUILD_TMP}"

# Maximize parallel jobs for faster build speed
PARALLEL_JOBS="$(nproc 2>/dev/null || echo 4)"
ninja -C "${BLENDER_BUILD_DIR}" -j"${PARALLEL_JOBS}"

echo "===> Freeing build disk space before packaging..."
find "${BLENDER_BUILD_DIR}" -name "*.o" -delete 2>/dev/null || true
