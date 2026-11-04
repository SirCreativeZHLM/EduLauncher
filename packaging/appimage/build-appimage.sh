#!/usr/bin/env bash
# Builds EduLauncher-<arch>.AppImage. Run inside the docker/Dockerfile.arch image
# (or any distro with the build dependencies), from the repository root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCH="$(uname -m)"
OUT="${APPIMAGE_WORK:-$ROOT/build/appimage}"
DIST="$ROOT/build"
APPDIR="$OUT/AppDir"
TOOLS="$OUT/tools"
mkdir -p "$TOOLS"

rm -rf "$APPDIR"
"$ROOT/scripts/build.sh" --prefix /usr --destdir "$APPDIR"

# Downloads an AppImage tool and unpacks it, so it runs without FUSE (and under emulation)
fetch() {
    local file="$TOOLS/$1" dir="$TOOLS/${1%.AppImage}"
    [[ -f "$file" ]] || curl -fsSL -o "$file" "$2"
    if [[ ! -x "$dir/AppRun" ]]; then
        # The squashfs image starts right after the ELF runtime: e_shoff + e_shentsize * e_shnum
        local shoff shentsize shnum
        shoff=$(od -An -j 40 -N 8 -t u8 "$file" | tr -d ' ')
        shentsize=$(od -An -j 58 -N 2 -t u2 "$file" | tr -d ' ')
        shnum=$(od -An -j 60 -N 2 -t u2 "$file" | tr -d ' ')
        rm -rf "$dir"
        unsquashfs -q -o $((shoff + shentsize * shnum)) -d "$dir" "$file" >/dev/null
    fi
}
fetch "linuxdeploy-$ARCH.AppImage" "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage"
fetch "linuxdeploy-plugin-qt-$ARCH.AppImage" "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-$ARCH.AppImage"
fetch "appimagetool-$ARCH.AppImage" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"

# AppRun: start the launcher script from inside the image
cat > "$OUT/AppRun" <<'RUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export EDULAUNCHER_LIBEXEC="$HERE/usr/lib/edulauncher/bin"
export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QTWEBENGINEPROCESS_PATH="$HERE/usr/libexec/QtWebEngineProcess"
export QT_PLUGIN_PATH="$HERE/usr/plugins"
export QTWEBENGINE_RESOURCES_PATH="$HERE/usr/resources"
export QTWEBENGINE_LOCALES_PATH="$HERE/usr/translations/qtwebengine_locales"
exec "$HERE/usr/bin/edulauncher" "$@"
RUN
chmod +x "$OUT/AppRun"

# linuxdeploy finds plugins on PATH by name
mkdir -p "$TOOLS/bin"
ln -sf "$TOOLS/linuxdeploy-plugin-qt-$ARCH/AppRun" "$TOOLS/bin/linuxdeploy-plugin-qt"
export PATH="$TOOLS/bin:$PATH"
export NO_STRIP=1
export QMAKE="$(command -v qmake6 || command -v qmake)"
export EXTRA_QT_MODULES="webenginecore;webenginewidgets"
# Android libraries shipped for the game are not host ELF files, keep them away from linuxdeploy
ANDROID_LIBS="$APPDIR/usr/lib/edulauncher/share/mcpelauncher/lib"
rm -rf "$OUT/android-libs"
mv "$ANDROID_LIBS" "$OUT/android-libs"
"$TOOLS/linuxdeploy-$ARCH/AppRun" --appdir "$APPDIR" \
    --executable "$APPDIR/usr/lib/edulauncher/bin/mcpelauncher-client" \
    --executable "$APPDIR/usr/lib/edulauncher/bin/edulauncher-signin" \
    --desktop-file "$APPDIR/usr/share/applications/io.github.sircreativezhlm.EduLauncher.desktop" \
    --icon-file "$ROOT/data/io.github.sircreativezhlm.EduLauncher.png" \
    --custom-apprun "$OUT/AppRun" \
    --plugin qt

mv "$OUT/android-libs" "$ANDROID_LIBS"

# Qt reads qt.conf next to the executable, ours live in usr/lib/edulauncher/bin
printf '[Paths]\nPrefix = ../../../\nPlugins = plugins\n' > "$APPDIR/usr/lib/edulauncher/bin/qt.conf"
rm -f "$APPDIR/.DirIcon" "$APPDIR/io.github.sircreativezhlm.EduLauncher.svg"
cp "$ROOT/data/io.github.sircreativezhlm.EduLauncher.png" "$APPDIR/.DirIcon"

# GL/EGL/Vulkan drivers and libc must come from the host
find "$APPDIR/usr/lib" -maxdepth 1 \( -name 'libGL*' -o -name 'libEGL*' -o -name 'libvulkan*' -o -name 'libgbm*' -o -name 'libdrm*' \) -delete

ARCH="$ARCH" "$TOOLS/appimagetool-$ARCH/AppRun" --no-appstream "$APPDIR" "$OUT/EduLauncher-$ARCH.AppImage"
mkdir -p "$DIST"
cp "$OUT/EduLauncher-$ARCH.AppImage" "$DIST/"
echo "==> $DIST/EduLauncher-$ARCH.AppImage"
