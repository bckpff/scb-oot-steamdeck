#!/usr/bin/env bash
# scb-oot for current Lichii builds on the Steam Deck (SteamOS), in one script.
#
# What it does:
#   1. checks the build tools; only if something is missing, turns off SteamOS read-only mode
#      and installs just that (the C/C++ headers SteamOS strips from glibc, linux-api-headers
#      and gcc; g++, git, python, zstd, vulkaninfo), then turns read-only mode back on
#   2. downloads scb-oot (https://github.com/rafaelsmiranda/scb-oot) and applies the patch
#      scb-oot-current-lichii.patch (next to this script), which makes it work with current
#      Lichii builds
#   3. downloads the Lichii sources of the build you play on (https://github.com/zortos293/Lichii)
#   4. runs scb-oot's tools/scb_oot.py with your options, which builds and installs the cache
#
# Run it as the normal user (not with sudo); it asks for the sudo password only when it
# has to install something. Set one with `passwd` if you never did.
#
# Usage:
#   bash scb-oot-deck.sh [script options] [scb_oot.py options]
#
# Script options (everything else goes to scb_oot.py unchanged):
#   --lichii-tag TAG   Lichii build you play on, e.g. build-228 (default: newest release)
#   --workdir PATH     where scb-oot, Lichii and the temporary files go (default: ~/scb-oot-build)
#   --skip-deps        don't check or install system packages
#   --keep-files       keep the downloaded sources afterwards (by default everything the
#                      script downloaded or created is removed at the end, also on errors)
#   --help-scb         show scb_oot.py's own options (downloads scb-oot first)
#   -h, --help         show this help
#
# Common scb_oot.py options:
#   --nup PATH         the game .nup file (required)
#   --cache-dir PATH   the game's shader cache folder
#                      (default: ~/.cache/lichii/shader/0400486024dec000)
#   --yes              don't ask before replacing an existing cache (a backup is still made)
#   --fast-start AGE   experimental quick first start (see --help-scb)
#   --lichii PATH      use these Lichii sources instead of downloading them
#
# Example:
#   bash scb-oot-deck.sh --nup "$HOME/Games/OOT.nup"
#
# Note: a SteamOS update removes installed headers again; run the script again after one.

set -euo pipefail

SCB_REPO="https://github.com/rafaelsmiranda/scb-oot"
SCB_COMMIT="4220c7c6117215e8405657241a8e246f2e32b689"   # the scb-oot version the patch is made for
LICHII_REPO="https://github.com/zortos293/Lichii"

LICHII_TAG=""
WORKDIR="$HOME/scb-oot-build"
SKIP_DEPS=0
KEEP_FILES=0
CLEANUP=0        # set once the work folder is in use
SCB_HELP=0
ARGS=()          # passed to scb_oot.py as given

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
die() { echo "ERROR: $*" >&2; exit 1; }
has_arg() {      # has_arg --name: whether the scb_oot.py options contain --name or --name=...
    local a
    for a in ${ARGS[@]+"${ARGS[@]}"}; do
        [[ "$a" == "$1" || "$a" == "$1="* ]] && return 0
    done
    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lichii-tag)   LICHII_TAG="${2:?--lichii-tag needs a tag}"; shift 2 ;;
        --lichii-tag=*) LICHII_TAG="${1#*=}"; shift ;;
        --workdir)      WORKDIR="${2:?--workdir needs a path}"; shift 2 ;;
        --workdir=*)    WORKDIR="${1#*=}"; shift ;;
        --skip-deps)    SKIP_DEPS=1; shift ;;
        --keep-files)   KEEP_FILES=1; shift ;;
        --help-scb)     SCB_HELP=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              ARGS+=("$1"); shift ;;
    esac
done

[[ $EUID -ne 0 ]] || die "run this as your normal user, not as root/sudo (it calls sudo itself)"
[[ $SCB_HELP -eq 1 ]] || has_arg --nup || die "--nup is required (see --help)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/scb-oot-current-lichii.patch"
[[ -f "$PATCH_FILE" ]] || die "scb-oot-current-lichii.patch not found next to this script (in $SCRIPT_DIR).
Copy both files, or the whole repository folder (see the README)."
mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
# scb-oot needs about 4 GB of temporary space; /tmp on SteamOS is in RAM, so use the work folder
export TMPDIR="$WORKDIR/tmp"
mkdir -p "$TMPDIR"
CLEANUP=1

# ---- 1. system dependencies --------------------------------------------------------------------
READONLY_CHANGED=0
PACMAN_CONF_CHANGED=0
cleanup() {
    [[ $CLEANUP -eq 1 ]] || return 0
    if [[ $KEEP_FILES -eq 1 ]]; then
        echo; echo "== Keeping the downloaded files (--keep-files): $WORKDIR, $HOME/.cache/scb-oot"
        return 0
    fi
    echo; echo "== Removing the downloaded and temporary files"
    # Only what this script and scb-oot created; other files in --workdir are left alone
    rm -rf "$WORKDIR/scb-oot" "$WORKDIR"/lichii-*
    if has_arg --keep-work; then
        echo "keeping the temporary files (--keep-work, they contain game code): $WORKDIR/tmp"
    else
        rm -rf "$WORKDIR/tmp"
    fi
    rmdir "$WORKDIR" 2>/dev/null || true
    rm -rf "$HOME/.cache/scb-oot"/lichii-*          # the Lichii build-125 sources scb-oot downloads
    rmdir "$HOME/.cache/scb-oot" 2>/dev/null || true
}
restore_pacman_conf() {
    if [[ $PACMAN_CONF_CHANGED -eq 1 ]]; then
        echo "== Restoring /etc/pacman.conf"
        if sudo cp /etc/pacman.conf.scb-oot.bak /etc/pacman.conf; then
            sudo rm -f /etc/pacman.conf.scb-oot.bak
            PACMAN_CONF_CHANGED=0
        else
            echo "WARNING: could not restore /etc/pacman.conf; the original is in /etc/pacman.conf.scb-oot.bak" >&2
        fi
    fi
}
restore_readonly() {
    if [[ $READONLY_CHANGED -eq 1 ]]; then
        echo; echo "== Re-enabling read-only mode"
        sudo steamos-readonly enable \
            || echo "WARNING: could not re-enable read-only mode; run: sudo steamos-readonly enable" >&2
    fi
}
on_exit() {
    local status=$?
    restore_pacman_conf
    restore_readonly
    cleanup
    exit $status
}
trap on_exit EXIT

# Packages whose header files the build compiles against (SteamOS ships them with /usr/include removed)
HEADER_PKGS=(glibc linux-api-headers gcc)
# Packages that only have to be installed
TOOL_PKGS=(gcc binutils git python zstd vulkan-tools)

if [[ $SKIP_DEPS -eq 0 && $SCB_HELP -eq 0 ]]; then
    command -v pacman >/dev/null || die "pacman not found: this script is for SteamOS (use --skip-deps elsewhere)"
    REINSTALL=() INSTALL=()
    for pkg in "${HEADER_PKGS[@]}"; do
        if ! pacman -Q "$pkg" >/dev/null 2>&1; then
            INSTALL+=("$pkg")
        elif { pacman -Qk "$pkg" 2>&1 || true; } | grep -q '/usr/include/.*No such file'; then
            REINSTALL+=("$pkg")
        fi
    done
    for pkg in "${TOOL_PKGS[@]}"; do
        pacman -Q "$pkg" >/dev/null 2>&1 || INSTALL+=("$pkg")
    done

    if [[ ${#REINSTALL[@]} -eq 0 && ${#INSTALL[@]} -eq 0 ]]; then
        echo "== Build tools and headers already installed"
    else
        [[ ${#REINSTALL[@]} -eq 0 ]] || echo "== Header files missing from: ${REINSTALL[*]}"
        [[ ${#INSTALL[@]} -eq 0 ]] || echo "== Not installed: ${INSTALL[*]}"
        command -v steamos-readonly >/dev/null || die "steamos-readonly not found: install the packages above yourself, then use --skip-deps"
        sudo -v
        echo "== Disabling read-only mode"
        sudo steamos-readonly disable
        READONLY_CHANGED=1

        echo "== Setting up the pacman keyring"
        sudo pacman-key --init
        sudo pacman-key --populate archlinux holo

        if grep -qE '^\s*NoExtract.*usr/include' /etc/pacman.conf; then
            echo "== Allowing pacman to install header files for now (backup: /etc/pacman.conf.scb-oot.bak)"
            sudo cp /etc/pacman.conf /etc/pacman.conf.scb-oot.bak
            PACMAN_CONF_CHANGED=1
            sudo sed -i -E 's|^(\s*NoExtract.*usr/include.*)$|#\1|' /etc/pacman.conf
        fi

        sudo pacman -Sy --noconfirm
        [[ ${#REINSTALL[@]} -eq 0 ]] || sudo pacman -S --noconfirm --overwrite '*' "${REINSTALL[@]}"
        [[ ${#INSTALL[@]} -eq 0 ]] || sudo pacman -S --noconfirm --needed "${INSTALL[@]}"

        restore_pacman_conf
        restore_readonly
        READONLY_CHANGED=0
    fi

    echo '#include <cstdio>
int main() { return 0; }' | g++ -std=c++20 -x c++ - -o /dev/null \
        || die "g++ still cannot build a test program; see the errors above"
fi

for tool in git python3; do
    command -v "$tool" >/dev/null || die "$tool is not installed"
done
python3 -c 'import compression.zstd' 2>/dev/null \
    || die "python3 is older than 3.14 (needed for zstd); found $(python3 --version)"

# ---- 2. scb-oot with the patch -----------------------------------------------------------------
SCB_DIR="$WORKDIR/scb-oot"

echo; echo "== Getting scb-oot"
[[ -d "$SCB_DIR/.git" ]] || git clone -q "$SCB_REPO" "$SCB_DIR"
git -C "$SCB_DIR" fetch -q origin
git -C "$SCB_DIR" -c advice.detachedHead=false checkout -q --force "$SCB_COMMIT"
git -C "$SCB_DIR" clean -q -fd harness tools      # files left by an earlier run
git -C "$SCB_DIR" apply "$PATCH_FILE"
echo "scb-oot ${SCB_COMMIT:0:7} with the current-Lichii patch: $SCB_DIR"

if [[ $SCB_HELP -eq 1 ]]; then
    python3 "$SCB_DIR/tools/scb_oot.py" --help
    exit 0
fi

# ---- 3. Lichii sources of your build -----------------------------------------------------------
if has_arg --lichii; then
    echo "== Using the Lichii sources given with --lichii"
else
    if [[ -z "$LICHII_TAG" ]]; then
        LICHII_TAG="$(python3 -c '
import json, urllib.request
try:
    with urllib.request.urlopen("https://api.github.com/repos/zortos293/Lichii/releases/latest", timeout=30) as r:
        print(json.load(r)["tag_name"])
except Exception:
    pass')"
        [[ -n "$LICHII_TAG" ]] || die "could not look up the newest Lichii release; pass --lichii-tag (e.g. build-228)"
        echo; echo "newest Lichii release: $LICHII_TAG (use --lichii-tag if you play on another build)"
    fi
    LICHII_DIR="$WORKDIR/lichii-$LICHII_TAG"
    echo "== Getting the Lichii $LICHII_TAG sources"
    if [[ ! -f "$LICHII_DIR/tools/nx2/extract_static_shaders.py" ]]; then
        rm -rf "$LICHII_DIR"
        git -c advice.detachedHead=false clone -q --depth 1 --branch "$LICHII_TAG" --filter=blob:none --sparse \
            "$LICHII_REPO" "$LICHII_DIR" \
            || die "could not download Lichii tag $LICHII_TAG (does it exist? see $LICHII_REPO/releases)"
        git -C "$LICHII_DIR" sparse-checkout set src/video_core src/common src/shader_recompiler tools/nx2
    fi
    ARGS+=(--lichii "$LICHII_DIR")
fi

# ---- 4. build and install the cache ------------------------------------------------------------
echo; echo "== Running scb_oot.py ${ARGS[*]}"
python3 "$SCB_DIR/tools/scb_oot.py" "${ARGS[@]}"
exit 0
