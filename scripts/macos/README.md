# Sunrise on macOS

Sunrise is a Windows DLL that lives inside `destiny2.exe`, so on a Mac both run under a
Wine-based compatibility layer with Rosetta 2 translating x86-64. This is the same technique the
Linux and Android setups use; only the graphics translation (Metal instead of Vulkan) and the
Wine build differ.

Tested target: Apple Silicon, macOS 26. Intel Macs follow the same steps without Rosetta.

## What you need

- A Steam account that owns Destiny 2. It is only used to download the old build.
- About 100 GB free for the game.
- Rosetta 2 on Apple Silicon: `softwareupdate --install-rosetta --agree-to-license`.
- One of:
  - **CrossOver 26 or newer** (recommended; 14-day trial). Ships Wine 11 with D3DMetal 3,
    DXMT and DXVK selectable per bottle.
  - **Whisky** or **Kegworks (Sikarugir)**: free builds of the same Wine and D3DMetal. Whisky
    is no longer maintained; it works for a first try but expect rough edges on new macOS
    versions.

## Install

The installer does the download, DLL placement, settings seed and CrossOver bottle:

```bash
git clone https://github.com/stanuwu/Sunrise
cd Sunrise
scripts/macos/install.sh --username <steam_user>
```

It uses the latest release DLL unless you built one (see the README's macOS build section), or
pass `--dll` to choose. Run with `--help` for the other options. With CrossOver installed it
creates a Windows 10 bottle named `Sunrise` with D3DMetal already selected and prints the
launch command.

Manual steps, if you prefer:

1. Download the two depots with [DepotDownloader](https://github.com/SteamRE/DepotDownloader)
   (native macOS build, no .NET install needed):
   ```bash
   ./DepotDownloader -app 1085660 -depot 1085661 -manifest 7180122903232116872 -username <user> -dir ~/Games/D2Legacy
   ./DepotDownloader -app 1085660 -depot 1085662 -manifest 2210332166360342287 -username <user> -dir ~/Games/D2Legacy
   ```
2. Copy `steam_api64.dll` over `~/Games/D2Legacy/bin/x64/steam_api64.dll`.
3. Create a 64-bit Windows 10 bottle. Do not share it with a Steam bottle.
4. Turn on D3DMetal for the bottle. Leave DXVK off for the first run.
5. Run `destiny2.exe` from the bottle.

## Before the first launch: deny the microphone

Switch CrossOver off under System Settings > Privacy & Security > Microphone before you run
the game. The game's voice-chat setup hangs its audio thread under CrossOver when it can open
the microphone; the game still boots, but the main thread later blocks the first time the
pause menu changes the audio state, and the picture freezes. With the microphone denied the
game plays normally. If macOS shows the microphone prompt on the first launch, choose Don't
Allow.

## Play

- The first launch extracts the activity SDK. Under Rosetta this takes longer than on Windows.
  If the game times out while the Sunrise popup is still up, wait for the popup to close and
  start the game again.
- The overlay hotkey defaults to **Insert**, which Mac keyboards do not have. The installer
  seeds `bin/x64/Sunrise/settings.json` with `"toggle_key": "home"`. On a laptop, Home is
  Fn+Left. Other accepted names: `end`, `delete`, `f1` to `f12` (F-keys need "Use F1, F2, etc.
  keys as standard function keys" in System Settings > Keyboard, or hold Fn).
- The installer also turns on the file log. It lands in `bin/x64/Sunrise/logs/`.
- Stay in fullscreen. Windowed mode under CrossOver is slower and was less stable in testing;
  fullscreen at the panel's native resolution ran a whole session without a stall.
- Some destinations do not load on any platform yet. Io fails with a "failed to create
  'sobject' entity" line and drops you back to the Director; Mars and the Tower load. That is
  mod content, not macOS.

## Graphics backends

Try them in this order. In CrossOver the setting is the bottle's "Graphics backend" (Advanced
settings); the installer sets D3DMetal. Change it and relaunch.

| Backend | Notes |
|---|---|
| D3DMetal | Fastest. Supports geometry shaders, so world-line markers draw at full width. |
| DXMT | Open-source Direct3D-to-Metal. Good fallback if D3DMetal misrenders. |
| DXVK (MoltenVK) | Proven path on Linux. MoltenVK has no geometry shaders; Sunrise then draws world lines one pixel wide and logs `ev=world_lines stage=geometry_shader result=fallback`. On that path the GPU clips lines at the camera plane itself, so a marker passing right through the camera can flicker for a frame. |

## If the game freezes

Run `scripts/macos/attach-debugger.sh` while it is frozen. It attaches Wine's debugger, writes
a backtrace of every thread to a file on the Desktop, and detaches. Attach that file, plus
`sunrise.log`, to a report.

## Reading the log

The first lines of `sunrise.log` name the host and the crypto providers, so include them in
bug reports:

```
ev=host wine=1 system=Darwin release=25.5.0
ev=crypto_probe result=complete
```

A `ev=crypto_probe primitive=... result=missing` line means the Wine build lacks a CNG
primitive Sunrise needs for sign-on. Report it with the CrossOver or Wine version.

## Known CrossOver issues Sunrise works around

- **wintrust null dereference.** The game calls a wintrust helper with a null signer when no
  signature chain could be built. CrossOver 26.3's wintrust crashes on it; upstream Wine fixed
  this in merge request 11545 (August 2026). Sunrise installs a null-safe guard for the two
  helpers when it runs under Wine and logs `group=wintrust_guard count=2 result=ok`.
- **Microphone.** See above. This one is avoided by a macOS permission, not by code.

## Known limitations

- No native build exists or can exist: the game is a Windows binary, and Sunrise only runs
  inside it.
- Matchmade activities are broken on every platform, not only macOS.
- The cross-compiled DLL is larger than the MSVC one (clang stores some large zeroed tables as
  initialized data). It loads and behaves the same.

## Building on macOS

See the README. In short: `brew install cmake ninja llvm lld xwin`, splat the SDK once with
`xwin`, then configure with `unix-to-win-toolchain.cmake` and build with Ninja. A full Release
build takes well under a minute on Apple Silicon.
