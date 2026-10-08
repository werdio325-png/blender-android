#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/common/env.sh"

echo "===> Downloading critical runtime datafiles, icons and fonts..."
echo "Downloading complete studiolights and matcaps from projects.blender.org media..."
mkdir -p "${BLENDER_SRC}/release/datafiles/studiolights/world" "${BLENDER_SRC}/release/datafiles/studiolights/matcap"
python3 -c '
import urllib.request, os
base_world = "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/studiolights/world/"
base_matcap = "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/studiolights/matcap/"
src = os.environ.get("BLENDER_SRC", "")

worlds = ["city.exr", "courtyard.exr", "forest.exr", "interior.exr", "night.exr", "studio.exr", "sunrise.exr", "sunset.exr"]
matcaps = ["basic_bright.exr", "basic_dark.exr", "basic_grey.exr", "basic_side.exr", "ceramic_dark.exr", "ceramic_lightbulb.exr", "clay_brown.exr", "clay_studio.exr", "red_wax.exr", "resin.exr"]

for w in worlds:
    try:
        p = os.path.join(src, "release/datafiles/studiolights/world", w)
        urllib.request.urlretrieve(base_world + w, p)
        print("Downloaded world:", w, os.path.getsize(p))
    except Exception as e:
        print("Failed world", w, e)

for m in matcaps:
    try:
        p = os.path.join(src, "release/datafiles/studiolights/matcap", m)
        urllib.request.urlretrieve(base_matcap + m, p)
        print("Downloaded matcap:", m, os.path.getsize(p))
    except Exception as e:
        print("Failed matcap", m, e)
' || true

echo "Downloading OpenColorIO fallback config v2.3..."
mkdir -p "${BLENDER_SRC}/release/datafiles/colormanagement"
curl -sL "https://projects.blender.org/blender/blender/media/branch/blender-v4.2-release/release/datafiles/colormanagement/config.ocio" -o "${BLENDER_SRC}/release/datafiles/colormanagement/config.ocio" || true

echo "Downloading vector icons from projects.blender.org media..."
mkdir -p "${BLENDER_SRC}/release/datafiles/icons"
python3 -c '
import urllib.request, os
base_url = "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/icons/"
target_dir = os.environ.get("BLENDER_SRC", "") + "/release/datafiles/icons"
if os.path.exists(target_dir):
    for icon in os.listdir(target_dir):
        p = os.path.join(target_dir, icon)
        if os.path.isfile(p) and os.path.getsize(p) < 200:
            try:
                url = base_url + icon
                urllib.request.urlretrieve(url, p)
            except Exception:
                pass
    print("Downloaded real icons successfully.")
' || true

mkdir -p "${BLENDER_SRC}/release/datafiles/fonts"
for f in startup.blend preview.blend preview_grease_pencil.blend splash.png; do
    echo "Downloading ${f}..."
    curl -sL "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/${f}" -o "${BLENDER_SRC}/release/datafiles/${f}" || true
done
for f in Inter.woff2 DejaVuSansMono.woff2; do
    echo "Downloading font ${f}..."
    curl -sL "https://projects.blender.org/blender/blender/media/branch/main/release/datafiles/fonts/${f}" -o "${BLENDER_SRC}/release/datafiles/fonts/${f}" || true
done

echo "===> Converting fonts to raw TrueType format for Android FreeType..."
python3 -m pip install fonttools brotli || true
python3 -c "
import os
try:
    from fontTools.ttLib import woff2
    font_dir = '${BLENDER_SRC}/release/datafiles/fonts'
    for f in ['Inter', 'DejaVuSansMono']:
        w_path = os.path.join(font_dir, f + '.woff2')
        t_path = os.path.join(font_dir, f + '.ttf')
        if os.path.exists(w_path):
            print('Decompressing ' + f + '.woff2 to ' + t_path + '...')
            woff2.decompress(w_path, t_path)
            with open(t_path, 'rb') as src, open(w_path, 'wb') as dst:
                dst.write(src.read())
            print('Successfully updated ' + f + '.woff2 with uncompressed TTF bytes.')
except Exception as e:
    print('fonttools decompress failed: ' + str(e))
" || true

for f in Inter DejaVuSansMono; do
    w_file="${BLENDER_SRC}/release/datafiles/fonts/${f}.woff2"
    t_file="${BLENDER_SRC}/release/datafiles/fonts/${f}.ttf"
    if [ ! -f "${t_file}" ] && [ -f "${w_file}" ]; then
        if command -v woff2_decompress >/dev/null 2>&1; then
            echo "Decompressing with woff2_decompress: ${f}.woff2"
            woff2_decompress "${w_file}" || true
            if [ -f "${t_file}" ]; then
                cp -f "${t_file}" "${w_file}"
            fi
        fi
    fi
done

if [ ! -f "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" ]; then
    echo "Downloading fallback Inter TTF from Google Fonts..."
    curl -sL "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf" -o "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" || true
    cp -f "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" "${BLENDER_SRC}/release/datafiles/fonts/Inter.woff2"
    cp -f "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" "${BLENDER_SRC}/release/datafiles/fonts/DejaVuSansMono.woff2"
    cp -f "${BLENDER_SRC}/release/datafiles/fonts/Inter.ttf" "${BLENDER_SRC}/release/datafiles/fonts/DejaVuSansMono.ttf"
fi

