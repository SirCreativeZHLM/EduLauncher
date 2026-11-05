# EduLauncher

Run **Minecraft Education** on Linux natively, the way [Sober](https://sober.vinegarhq.org/) runs Roblox:
the Android build of the game is loaded directly into a Linux process. There is no Android container,
emulator or Wine.

EduLauncher is a small layer on top of [mcpelauncher](https://github.com/minecraft-linux/mcpelauncher-manifest),
the open source runtime that does the same for Minecraft Bedrock. mcpelauncher provides the Android linker, the
bionic libc shim and the fake JNI. EduLauncher adds what is specific to Education Edition:

| Piece | What it does |
| --- | --- |
| `ActiveDirectorySignIn` JNI class | The game's school account sign-in. Opens a Microsoft sign-in window (OAuth code flow with PKCE, the game's own client id), keeps the refresh token so you only sign in once, and hands the token back to the game. |
| Sign-in request rewrite | `login.minecrafteduservices.com` rejects the `Linux()` platform the game reports under mcpelauncher (HTTP 400). Sign-in requests are rewritten to report an Android device. |
| Secure storage | `MainActivity.getSecureStorageKey/setSecureStorageKey`, persisted in the profile (0600). |
| Package identity | Reports `com.mojang.minecraftedu` and maps its `/data/data` path. |
| Telemetry hook | Parks the 1DS telemetry uploader thread, which otherwise kills the game seconds after start. |
| `edulauncher` | Front end. Imports the APK, then starts the game. |
| `edulauncher-signin` | Tiny Qt6 WebEngine window for the Microsoft sign-in, plus the file picker and dialogs. |

All game changes are in [`patches/mcpelauncher-client-education.patch`](patches/mcpelauncher-client-education.patch)
against a pinned upstream commit (see `scripts/build.sh`).

## Status

**Experimental.** What has been verified, and what has not:

| | |
| --- | --- |
| Arch package (`makepkg`) | Builds from a clean upstream checkout. Installs with `pacman -U` on a clean Arch, no missing libraries. |
| AppImage | Builds. The sign-in window from it opens Microsoft's real *"Sign in to continue to Minecraft: Education Edition"* page. Built on Arch, so it needs a recent glibc. |
| Flatpak | Manifest builds and runs end to end (checked natively on arm64). Build the x86_64 one on your machine (see below). |
| APK import | Single APKs and split bundles, tested with dummy bundles. |
| Starting the game | Minecraft Education 1.26.33 (x86_64, from Google Play) boots to the title screen and asks for the school sign-in (tested on Arch x86_64 with software rendering). |
| Signing in and playing | **Not tested yet.** Needs a school account. |

Earlier community work ([mceelinux](https://github.com/orgs/mceelinux/discussions/1)) reached these points:
the window opens and stays open with the telemetry hook, sign-in gets a valid token once the platform is
rewritten, but some builds then showed *"demo not possible"* and some GPUs a black screen. If you hit one of
those, see [Debugging](#debugging) and open an issue with the log.

## Getting the game

`edulauncher download` (also run automatically on first start) fetches the game for your CPU straight from Google
Play, using [apkeep](https://github.com/EFForg/apkeep) and an anonymous account from Aurora Store's token dispenser.
Nothing is downloaded from mirrors.

To use a copy you already have instead, you need the **x86_64** Android build of Minecraft Education (`com.mojang.minecraftedu`), the one Google Play
installs on Chromebooks. EduLauncher never ships the game itself. Any of these
formats works:

- `.apk` (single APK)
- `.apks`, `.xapk` or `.apkm` (split bundle: base plus `split_config.x86_64`)

An ARM (`arm64-v8a`) APK only works on an ARM Linux machine.

## Install

### Arch Linux (makepkg)

```sh
git clone https://github.com/SirCreativeZHLM/EduLauncher
cd EduLauncher/packaging/arch
makepkg -si
```

### Prebuilt Arch package (EndeavourOS, Manjaro, Arch)

Download the `.pkg.tar.zst` from the [latest release](https://github.com/SirCreativeZHLM/EduLauncher/releases/tag/latest), then:

```sh
sudo pacman -U edulauncher-*.pkg.tar.zst
edulauncher
```

The first start downloads the game from Google Play (about 1 GB). GitHub Actions builds the package on every push.

### Arch package with the game inside (private use)

```sh
EDU_GAME_APK=/path/to/MinecraftEducation.apks makepkg -si
```

The game is installed to `/usr/share/edulauncher/game` and used until you `edulauncher import` your own copy.
Never share a package built this way, the game files belong to Microsoft.

### AppImage

```sh
chmod +x EduLauncher-x86_64.AppImage
./EduLauncher-x86_64.AppImage import ~/Downloads/MinecraftEducation.apks
./EduLauncher-x86_64.AppImage
```

To build it yourself, run `packaging/appimage/build-appimage.sh` (needs the same dependencies as the PKGBUILD,
or use `docker/Dockerfile.arch`).

### Flatpak

```sh
flatpak install flathub org.kde.Sdk//6.10 org.kde.Platform//6.10 io.qt.qtwebengine.BaseApp//6.10 org.freedesktop.Sdk.Extension.llvm21//25.08
flatpak-builder --user --install --force-clean build/flatpak packaging/flatpak/io.github.sircreativezhlm.EduLauncher.yml
flatpak run io.github.sircreativezhlm.EduLauncher
```

Building takes about 15 to 30 minutes the first time. The result shows up in your app menu.

## Use

```sh
edulauncher download                          # get or update the game from Google Play
edulauncher import MinecraftEducation.apks   # or use your own copy
edulauncher                                   # play
edulauncher signout                           # forget the school account
edulauncher info                              # paths and state
```

Starting **Minecraft Education (EduLauncher)** from the app menu does the same thing. If the game is not
installed yet, a file picker asks for the APK.

Files are stored under `~/.local/share/edulauncher/` (`game/` holds the extracted game, `profile/` holds
worlds, settings and the saved sign-in). In the Flatpak this lives under `~/.var/app/io.github.sircreativezhlm.EduLauncher/`.

## Debugging

```sh
edulauncher -- -v                     # version info
MCEE_PLATFORM='Android(x86_64)' edulauncher   # try a different platform string for sign-in
MCEE_ACCESS_TOKEN=... edulauncher     # skip the sign-in window and use this token
LIBGL_ALWAYS_SOFTWARE=1 edulauncher   # rule out GPU driver problems on a black screen
```

For full JNI traces, rebuild with `EDU_CMAKE_ARGS=-DJNIVM_ENABLE_TRACE=ON scripts/build.sh`. Every Java call
the game makes then shows up on stdout, which is how missing Education classes are found.

## Legal

Unofficial. Not affiliated with, endorsed or approved by Mojang or Microsoft. "Minecraft" is a trademark of
Mojang Synergies AB. You need a Minecraft Education licence through your school, and you supply the game files
yourself. EduLauncher is GPL-3.0, like mcpelauncher it is built on.
