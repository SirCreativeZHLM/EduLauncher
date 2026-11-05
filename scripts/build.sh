#!/usr/bin/env bash
# Builds EduLauncher into a staging prefix.
#
#   scripts/build.sh [--prefix /usr] [--destdir DIR] [--jobs N]
#
# Environment:
#   EDU_SRC        where upstream sources are checked out   (default: build/src)
#   EDU_BUILD      cmake build directory                     (default: build/cmake)
#   EDU_OWN_CURL   ON to build curl from source              (default: OFF)
#   EDU_CMAKE_ARGS extra cmake arguments for the game client
#   EDU_GAME_APK   game .apk/.apks/.xapk/.apkm to ship inside the package (private builds only)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Upstream mcpelauncher-manifest commit this release is tested against
UPSTREAM_REPO="https://github.com/minecraft-linux/mcpelauncher-manifest.git"
UPSTREAM_COMMIT="fb58aa2dbd966573844fc3fe53dadcddb6719009"

PREFIX="/usr"
DESTDIR="$ROOT/build/stage"
JOBS="$(nproc 2>/dev/null || echo 4)"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --destdir) DESTDIR="$2"; shift 2 ;;
        --jobs|-j) JOBS="$2"; shift 2 ;;
        *) echo "Unknown option $1" >&2; exit 2 ;;
    esac
done

SRC="${EDU_SRC:-$ROOT/build/src}"
BUILD="${EDU_BUILD:-$ROOT/build/cmake}"
LIBDIR="$PREFIX/lib/edulauncher"

if [[ ! -f "$SRC/CMakeLists.txt" ]]; then
    echo "==> Fetching mcpelauncher sources"
    git init -q "$SRC"
    git -C "$SRC" remote add origin "$UPSTREAM_REPO"
    git -C "$SRC" fetch -q --depth 1 origin "$UPSTREAM_COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
    git -C "$SRC" submodule update -q --init --recursive --depth 1 --jobs 8
fi

echo "==> Applying Minecraft Education patches"
CLIENT="$SRC/mcpelauncher-client"
if git -C "$CLIENT" apply --check -R "$ROOT/patches/mcpelauncher-client-education.patch" 2>/dev/null; then
    echo "    already applied"
elif git -C "$CLIENT" apply --check "$ROOT/patches/mcpelauncher-client-education.patch" 2>/dev/null; then
    git -C "$CLIENT" apply "$ROOT/patches/mcpelauncher-client-education.patch"
else
    echo "Patch does not apply to $CLIENT" >&2
    exit 1
fi

echo "==> Building game client"
# shellcheck disable=SC2086
cmake -S "$SRC" -B "$BUILD/client" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$LIBDIR" \
    -DBUILD_UI=OFF \
    -DBUILD_WEBVIEW=OFF \
    -DXAL_WEBVIEW_USE_QT=OFF \
    -DXAL_WEBVIEW_USE_CLI=ON \
    -DENABLE_ERROR_WINDOW=OFF \
    -DENABLE_DEV_PATHS=OFF \
    -DGAMEWINDOW_SYSTEM=SDL3 \
    -DJNI_USE_JNIVM=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DUSE_OWN_CURL="${EDU_OWN_CURL:-OFF}" \
    ${EDU_CMAKE_ARGS:-}
cmake --build "$BUILD/client" -j "$JOBS"
DESTDIR="$DESTDIR" cmake --install "$BUILD/client"

echo "==> Building sign-in helper"
cmake -S "$ROOT/signin" -B "$BUILD/signin" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$LIBDIR"
cmake --build "$BUILD/signin" -j "$JOBS"
DESTDIR="$DESTDIR" cmake --install "$BUILD/signin"

echo "==> Installing launcher"
install -Dm755 "$ROOT/launcher/edulauncher" "$DESTDIR$PREFIX/bin/edulauncher"
install -Dm644 "$ROOT/data/io.github.sircreativezhlm.EduLauncher.desktop" "$DESTDIR$PREFIX/share/applications/io.github.sircreativezhlm.EduLauncher.desktop"
install -Dm644 "$ROOT/data/io.github.sircreativezhlm.EduLauncher.svg" "$DESTDIR$PREFIX/share/icons/hicolor/scalable/apps/io.github.sircreativezhlm.EduLauncher.svg"
install -Dm644 "$ROOT/data/io.github.sircreativezhlm.EduLauncher.png" "$DESTDIR$PREFIX/share/icons/hicolor/256x256/apps/io.github.sircreativezhlm.EduLauncher.png"
install -Dm644 "$ROOT/data/io.github.sircreativezhlm.EduLauncher.metainfo.xml" "$DESTDIR$PREFIX/share/metainfo/io.github.sircreativezhlm.EduLauncher.metainfo.xml"

if [[ -n "${EDU_GAME_APK:-}" ]]; then
    echo "==> Bundling the game from $EDU_GAME_APK"
    tmp="$(mktemp -d)"
    XDG_DATA_HOME="$tmp" EDULAUNCHER_LIBEXEC="$DESTDIR$LIBDIR/bin" "$ROOT/launcher/edulauncher" import "$EDU_GAME_APK"
    rm -rf "$DESTDIR$PREFIX/share/edulauncher/game"
    mkdir -p "$DESTDIR$PREFIX/share/edulauncher"
    mv "$tmp/edulauncher/game" "$DESTDIR$PREFIX/share/edulauncher/game"
    rm -rf "$tmp"
fi

echo "==> Done: $DESTDIR$PREFIX"
