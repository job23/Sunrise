#!/usr/bin/env bash
# Installs Sunrise on macOS: downloads the pinned Destiny 2 build, places the DLL, seeds a
# Mac-friendly settings file and, when CrossOver is installed, creates the bottle.
#
# Usage: scripts/macos/install.sh [options]
#   --game-dir DIR       Where the game goes (default: ~/Games/D2Legacy).
#   --username USER      Steam account that owns Destiny 2 (prompted when omitted).
#   --dll PATH           steam_api64.dll to install (default: build output, else latest release).
#   --bottle NAME        CrossOver bottle to create or reuse (default: Sunrise).
#   --skip-download      Do not run DepotDownloader; the game is already in --game-dir.
#   --skip-bottle        Do not touch CrossOver.
set -euo pipefail

readonly APP_ID=1085660
readonly DEPOT_A=1085661
readonly MANIFEST_A=7180122903232116872
readonly DEPOT_B=1085662
readonly MANIFEST_B=2210332166360342287
readonly SUNRISE_REPO="stanuwu/Sunrise"
readonly DEPOT_DOWNLOADER_REPO="SteamRE/DepotDownloader"
readonly CROSSOVER_BIN="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/../.." && pwd)"
game_dir="${HOME}/Games/D2Legacy"
username=""
dll_path=""
bottle="Sunrise"
skip_download=0
skip_bottle=0

# Progress goes to stderr so functions whose stdout is captured can still report.
log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Reads the value after a flag, or stops with the flag's name when none follows.
option_value() {
    [[ -n "${2:-}" ]] || die "$1 needs a value"
    echo "$2"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --game-dir) game_dir="$(option_value "$@")"; shift 2 ;;
        --username) username="$(option_value "$@")"; shift 2 ;;
        --dll) dll_path="$(option_value "$@")"; shift 2 ;;
        --bottle) bottle="$(option_value "$@")"; shift 2 ;;
        --skip-download) skip_download=1; shift ;;
        --skip-bottle) skip_bottle=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

check_host() {
    [[ "$(uname -s)" == "Darwin" ]] || die "this installer is for macOS"
    local arch; arch="$(uname -m)"
    if [[ "${arch}" == "arm64" ]]; then
        if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
            die "Rosetta 2 is required: run 'softwareupdate --install-rosetta --agree-to-license'"
        fi
    fi
    command -v curl >/dev/null || die "curl is required"
    command -v python3 >/dev/null || die "python3 is required (xcode-select --install)"
}

# Prints the browser_download_url of the first release asset whose name matches a pattern.
release_asset_url() {
    local repo="$1" pattern="$2"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | python3 -c 'import json,re,sys
pattern=sys.argv[1]
for asset in json.load(sys.stdin)["assets"]:
    if re.search(pattern, asset["name"]):
        print(asset["browser_download_url"]); break' "${pattern}"
}

ensure_depot_downloader() {
    local tools="${game_dir}/.tools"
    if [[ -x "${tools}/DepotDownloader" ]]; then
        echo "${tools}/DepotDownloader"; return
    fi
    local arch="x64"; [[ "$(uname -m)" == "arm64" ]] && arch="arm64"
    local url; url="$(release_asset_url "${DEPOT_DOWNLOADER_REPO}" "macos-${arch}\\.zip$")"
    [[ -n "${url}" ]] || die "could not find a DepotDownloader macOS ${arch} release"
    log "Downloading DepotDownloader (${url##*/})"
    mkdir -p "${tools}"
    curl -fsSL "${url}" -o "${tools}/DepotDownloader.zip"
    ditto -x -k "${tools}/DepotDownloader.zip" "${tools}"
    rm -f "${tools}/DepotDownloader.zip"
    chmod +x "${tools}/DepotDownloader"
    xattr -dr com.apple.quarantine "${tools}" 2>/dev/null || true
    echo "${tools}/DepotDownloader"
}

download_game() {
    local downloader; downloader="$(ensure_depot_downloader)"
    if [[ -z "${username}" ]]; then
        read -r -p "Steam username (account that owns Destiny 2): " username
    fi
    [[ -n "${username}" ]] || die "a Steam username is required for the depot download"
    log "Downloading depot ${DEPOT_A} (this is most of the game; expect a long wait)"
    "${downloader}" -app "${APP_ID}" -depot "${DEPOT_A}" -manifest "${MANIFEST_A}" \
        -username "${username}" -remember-password -dir "${game_dir}"
    log "Downloading depot ${DEPOT_B}"
    "${downloader}" -app "${APP_ID}" -depot "${DEPOT_B}" -manifest "${MANIFEST_B}" \
        -username "${username}" -remember-password -dir "${game_dir}"
}

resolve_dll() {
    if [[ -n "${dll_path}" ]]; then
        [[ -f "${dll_path}" ]] || die "no such DLL: ${dll_path}"
        echo "${dll_path}"; return
    fi
    local built="${repo_dir}/build/x64/Release/steam_api64.dll"
    if [[ -f "${built}" ]]; then
        echo "${built}"; return
    fi
    local url; url="$(release_asset_url "${SUNRISE_REPO}" '^steam_api64\.dll$')"
    [[ -n "${url}" ]] || die "could not find a Sunrise release DLL; build one or pass --dll"
    log "Downloading the latest Sunrise release DLL"
    mkdir -p "${game_dir}/.tools"
    curl -fsSL "${url}" -o "${game_dir}/.tools/steam_api64.dll"
    echo "${game_dir}/.tools/steam_api64.dll"
}

install_dll() {
    local target_dir="${game_dir}/bin/x64"
    [[ -f "${game_dir}/destiny2.exe" ]] || die "destiny2.exe not found in ${game_dir}"
    [[ -d "${target_dir}" ]] || die "${target_dir} is missing; the depot download is incomplete"
    local source; source="$(resolve_dll)"
    if [[ -f "${target_dir}/steam_api64.dll" && ! -f "${target_dir}/steam_api64.dll.orig" ]]; then
        cp "${target_dir}/steam_api64.dll" "${target_dir}/steam_api64.dll.orig"
    fi
    cp "${source}" "${target_dir}/steam_api64.dll"
    log "Installed $(basename "${source}") from ${source}"
}

# Seeds settings with a hotkey Mac keyboards have and the file log on, so the first bug report
# already carries a log. An existing settings file is left alone.
seed_settings() {
    local settings_dir="${game_dir}/bin/x64/Sunrise"
    local settings="${settings_dir}/settings.json"
    local defaults="${repo_dir}/Sunrise/resources/default_settings.json"
    if [[ -f "${settings}" ]]; then
        log "Keeping existing ${settings}"; return
    fi
    [[ -f "${defaults}" ]] || { warn "default_settings.json not found; skipping settings seed"; return; }
    mkdir -p "${settings_dir}"
    python3 - "${defaults}" "${settings}" <<'PY'
import json, sys
defaults, target = sys.argv[1], sys.argv[2]
settings = json.load(open(defaults))
# Mac keyboards have no Insert key. Home is Fn+Left on laptops and a real key on full keyboards.
settings["client"]["ui"]["toggle_key"] = "home"
settings["core"]["logging"]["file_sink"] = True
json.dump(settings, open(target, "w"), indent=2)
PY
    log "Seeded ${settings} (toggle_key=home, file_sink=true)"
}

setup_bottle() {
    if [[ ! -x "${CROSSOVER_BIN}/cxbottle" ]]; then
        warn "CrossOver not found; create a 64-bit Windows 10 bottle in Whisky or Kegworks and run"
        warn "  ${game_dir}/destiny2.exe"
        warn "inside it, with D3DMetal enabled. See scripts/macos/README.md."
        return
    fi
    if [[ -d "${HOME}/Library/Application Support/CrossOver/Bottles/${bottle}" ]]; then
        log "Reusing CrossOver bottle '${bottle}'"
    else
        log "Creating CrossOver bottle '${bottle}' (Windows 10, 64-bit, D3DMetal)"
        # CrossOver stores the graphics backend as a bottle environment variable; d3dmetal and
        # dxvk are the values its own templates write.
        "${CROSSOVER_BIN}/cxbottle" --create --bottle "${bottle}" --template win10_64 \
            --description "Sunrise (Destiny 2 offline)" \
            --param "EnvironmentVariables:CX_GRAPHICS_BACKEND=d3dmetal"
    fi
    cat <<MSG

Bottle '${bottle}' is ready with D3DMetal on. Launch the game with:

  "${CROSSOVER_BIN}/wine" --bottle "${bottle}" --cx-app "${game_dir}/destiny2.exe"

or open CrossOver, pick the bottle, and run destiny2.exe from "Run Command".

MSG
}

main() {
    check_host
    mkdir -p "${game_dir}"
    if [[ "${skip_download}" -eq 0 ]]; then
        download_game
    fi
    install_dll
    seed_settings
    if [[ "${skip_bottle}" -eq 0 ]]; then
        setup_bottle
    fi
    log "Done. Logs land in ${game_dir}/bin/x64/Sunrise/logs/ once the game has run."
}

main "$@"
