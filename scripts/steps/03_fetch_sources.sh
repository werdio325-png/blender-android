#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> Disabling Git LFS filters..."
git lfs uninstall --system 2>/dev/null || true
git lfs uninstall 2>/dev/null || true
git config --global filter.lfs.smudge "cat" 2>/dev/null || true
git config --global filter.lfs.clean "cat" 2>/dev/null || true
git config --global filter.lfs.process "" 2>/dev/null || true
git config --global filter.lfs.required false 2>/dev/null || true
git config --global http.version HTTP/1.1 2>/dev/null || true
git config --global http.postBuffer 524288000 2>/dev/null || true
export GIT_LFS_SKIP_SMUDGE=1

echo "===> Cloning Blender source (v5.2.0)..."
mkdir -p "${BUILD_TMP}"
cd "${BUILD_TMP}"
if [ ! -f "blender/build_files/cmake/platform/platform_unix.cmake" ]; then
    rm -rf blender
    for attempt in 1 2 3; do
        echo "Cloning Blender source (attempt $attempt)..."
        rm -rf blender
        if git -c filter.lfs.smudge=cat -c filter.lfs.clean=cat -c filter.lfs.process= -c filter.lfs.required=false clone --depth 1 --branch v5.2.0 https://github.com/blender/blender.git blender; then
            break
        fi
        rm -rf blender
        if git -c filter.lfs.smudge=cat -c filter.lfs.clean=cat -c filter.lfs.process= -c filter.lfs.required=false clone --depth 1 --branch v5.2.0 https://projects.blender.org/blender/blender.git blender; then
            break
        fi
        sleep 5
    done
fi

if [ -d "blender/.git" ] && [ ! -f "blender/build_files/cmake/platform/platform_unix.cmake" ]; then
    echo "Forcing checkout in blender repo..."
    (cd blender && git -c filter.lfs.smudge=cat -c filter.lfs.clean=cat -c filter.lfs.process= -c filter.lfs.required=false checkout -f HEAD || true)
fi

if [ ! -f "${BLENDER_SRC}/build_files/cmake/platform/platform_unix.cmake" ]; then
    echo "ERROR: Failed to clone and checkout Blender source code!"
    exit 1
fi

