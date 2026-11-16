# scb-oot-steamdeck

One script that builds a ready-made shader cache for **The Legend of Zelda: Ocarina of Time Remake
(Switch 2)** in the **Lichii** emulator on a **Steam Deck**, with
[scb-oot](https://github.com/rafaelsmiranda/scb-oot) (Shader Cache Builder for OoT).

scb-oot was made for Lichii builds 119 and 125. Newer Lichii builds handle shaders differently, so plain
scb-oot either fails to build or produces a cache that newer builds mostly ignore. This script
includes a patch that makes scb-oot work with current Lichii builds, and it takes care of the SteamOS
parts: installing the compiler and the header files SteamOS leaves out, then switching read-only mode
back on.

> This repository contains no game files and no shader code. The shader code is generated on your
> Deck from your own copy of the game, and nothing is uploaded anywhere.

## Disclaimer

**Use this script at your own risk.** It is provided as is, without any warranty, as described in
sections 15 and 16 of the [GPL-3.0 license](LICENSE). The authors are not responsible for any damage,
data loss or other problems it may cause.

Before running it, be aware that it:

- **changes your system:** it turns off SteamOS read-only mode for a while, installs and reinstalls
  system packages with `sudo`, and temporarily edits `/etc/pacman.conf`. A mistake there, a failed
  download or an interrupted run can leave your system in a broken or unexpected state. If that
  happens, a SteamOS update or a reinstall resets the system partition.
- **replaces your shader cache:** scb-oot backs up the existing cache first, but keep your own copy of
  anything you can't afford to lose.
- **depends on other projects:** it downloads and runs code from scb-oot and Lichii, which can change
  at any time and aren't maintained here.

Read the script before you run it. Only use it with a copy of the game you own and have dumped
yourself.

## Contents

- [Disclaimer](#disclaimer)
- [What the script does](#what-the-script-does)
- [Requirements](#requirements)
- [Getting the script onto the Deck](#getting-the-script-onto-the-deck)
  - [Option A: download it on the Deck](#option-a-download-it-on-the-deck)
  - [Option B: copy it from a PC over SSH](#option-b-copy-it-from-a-pc-over-ssh)
- [Running it](#running-it)
- [Options](#options)
- [After the build](#after-the-build)
- [What it changes on your system](#what-it-changes-on-your-system)
- [What the patch changes in scb-oot](#what-the-patch-changes-in-scb-oot)
- [Troubleshooting](#troubleshooting)
- [Removing everything](#removing-everything)
- [Credits and license](#credits-and-license)

## What the script does

1. **Checks the build tools.** It looks for `g++`, `binutils`, `git`, `python`, `zstd` and
   `vulkan-tools`, and for the header files of `glibc`, `linux-api-headers` and `gcc`. If something is
   missing, it turns off SteamOS read-only mode, installs or reinstalls only those packages, and turns
   read-only mode back on. If nothing is missing, it changes nothing and doesn't ask for a password.
2. **Downloads scb-oot** at the version the patch was made for, and applies the patch, which is built
   into the script.
3. **Downloads the Lichii sources** for the build you play on: only the folders the build needs. By
   default that's the newest Lichii release.
4. **Runs scb-oot** with your options. scb-oot regenerates the shader code from your game file, builds
   a cache for your Deck's graphics driver, backs up any existing cache and installs the new one.
5. **Cleans up.** It deletes everything it downloaded or created: the scb-oot checkout, the Lichii
   sources, the temporary files (which contain game code) and the Lichii build-125 sources in
   `~/.cache/scb-oot`. This also happens when something fails. Use `--keep-files` to keep them.

## Requirements

**Hardware and system**

- A Steam Deck (LCD or OLED) running **SteamOS 3.x**.
- **Desktop Mode** with a terminal (Konsole), or SSH access (see [Option B](#option-b-copy-it-from-a-pc-over-ssh)).
- A **password for the `deck` user**, because installing packages needs `sudo`. If you never set one,
  open Konsole and run `passwd`.
- An **internet connection** to download packages, scb-oot and the Lichii sources.
- **Python 3.14 or newer.** Current SteamOS ships it; the script checks and stops if yours is older.

**Disk space**

- About **5 GB free in your home folder** for the downloads and temporary files. All of it is
  deleted again at the end.
- About **3.5 GB free for the cache itself**, in `~/.cache/lichii/shader/`.
- A few hundred MB on the **system partition** if packages have to be installed.

**Emulator and game**

- **Lichii** installed, with the **game started at least once**. That creates the cache folder
  `~/.cache/lichii/shader/0400486024dec000`, which scb-oot installs into.
- The **number of the Lichii build** you play on (for example `build-228`, as in the name of the
  [release](https://github.com/zortos293/Lichii/releases) you downloaded). By default the script uses
  the newest release; if you play on an older one, pass it with `--lichii-tag`. The cache only matches
  the build it was made for.
- Your copy of the game as a **`.nup` file containing update 131072** (title ID `0400486024DEC000`).
  scb-oot checks this and refuses other games and versions.
- Lichii must be **closed** while the script runs. scb-oot checks this too.

**Only for copying from a PC (Option B)**

- The **SSH server (`sshd`)** turned on on the Deck, see below.
- `ssh` and `scp` on the PC. Linux, macOS and Windows 10/11 include them.
- The Deck and PC on the same network.

## Getting the script onto the Deck

### Option A: download it on the Deck

In Desktop Mode, open Konsole and run:

```bash
git clone https://github.com/bckpff/scb-oot-steamdeck.git ~/scb-oot-steamdeck
```

The script is then at `~/scb-oot-steamdeck/scb-oot-deck.sh`. To get a newer version later:

```bash
git -C ~/scb-oot-steamdeck pull
```

### Option B: copy it from a PC over SSH

**1. Turn on the SSH server on the Deck** (Desktop Mode, Konsole):

```bash
passwd
```

(Skip `passwd` if you already set a password.)

```bash
sudo systemctl start sshd
```

To keep it on after a restart, use `sudo systemctl enable --now sshd` instead.

**2. Find the Deck's address.** Usually `steamdeck` works as the name on your network. If it doesn't,
look up the IP address on the Deck:

```bash
ip -4 addr show | grep inet
```

Use the address that isn't `127.0.0.1`, for example `192.168.1.50`.

**3. Copy the script from the PC** (in the folder where you downloaded or cloned this repository):

```bash
scp scb-oot-deck.sh deck@steamdeck:~/
```

Replace `steamdeck` with the IP address if needed. The first time, confirm the host key with `yes`,
then enter the `deck` password.

**4. Run it over SSH**, or switch to the Deck and run it in Konsole:

```bash
ssh deck@steamdeck
```

The build takes several minutes. If the SSH connection drops, the build stops; then run the script
again.

**5. Turn SSH off again when you're done**, if you don't need it:

```bash
sudo systemctl disable --now sshd
```

## Running it

```bash
bash ~/scb-oot-deck.sh --nup "/path/to/your/game.nup"
```

(With Option A the path is `~/scb-oot-steamdeck/scb-oot-deck.sh`.)

Run it as the normal `deck` user, **not** with `sudo`. It asks for the password itself, and only when
packages are missing.

If there's already a cache, scb-oot asks before replacing it and backs it up first. Add `--yes` to skip
the question; the backup is still made.

Examples:

```bash
# you play on an older Lichii build
bash ~/scb-oot-deck.sh --nup "/path/to/your/game.nup" --lichii-tag build-160

# no question before replacing, and the experimental fast first start
bash ~/scb-oot-deck.sh --nup "/path/to/your/game.nup" --yes --fast-start 0

# your Lichii keeps its cache somewhere else (portable install)
bash ~/scb-oot-deck.sh --nup "/path/to/your/game.nup" --cache-dir "/path/to/user/cache/shader/0400486024dec000"
```

## Options

The script has five options of its own. **Every other option goes to scb-oot's `scb_oot.py`
unchanged.**

| Script option | Meaning |
| --- | --- |
| `--lichii-tag TAG` | The Lichii build you play on, e.g. `build-228`. Default: the newest release. |
| `--workdir PATH` | Where scb-oot, the Lichii sources and the temporary files go. Default: `~/scb-oot-build`. |
| `--skip-deps` | Don't check or install system packages. |
| `--keep-files` | Don't delete the downloaded sources and temporary files at the end. |
| `--help-scb` | Show all of scb-oot's own options. |
| `-h`, `--help` | Show the script's help. |

The most useful scb-oot options:

| scb-oot option | Meaning |
| --- | --- |
| `--nup PATH` | The game `.nup` file. **Required.** |
| `--cache-dir PATH` | The game's cache folder. Default: `~/.cache/lichii/shader/0400486024dec000`. Must end in `0400486024dec000`. |
| `--yes` | Don't ask before replacing an existing cache (it's still backed up). |
| `--fast-start AGE` | Experimental: the first start builds only recently used pipelines (`0` = about 2,200, `1` = about 11,000) and the rest in the background. |
| `--lichii PATH` | Use Lichii sources you already have instead of downloading them. Must match the build you play on. |
| `--keep-work` | Keep scb-oot's temporary folder (in `<workdir>/tmp`), even when the rest is cleaned up. It contains game code, so delete it yourself afterwards. |
| `--no-remap` | Use the hints unchanged. Only right for Lichii build 125. |

## After the build

1. Start Lichii and load the game.
2. On the first start, Lichii converts the new cache into its own format (`lichii-cache.v2.bin`) and
   builds the pipelines. That can take a while; let it finish. Later starts are fast.
3. Lichii's log should contain a line like
   `Shader cache v2 started from the version 54 cache`. That confirms it picked up the cache.

During the build, check the line `hints moved onto this Lichii build: X of Y pipelines`. X should be
close to Y. If it's far lower, the `--lichii-tag` probably doesn't match your Lichii build.

## What it changes on your system

Only when something is missing:

- **Read-only mode** is turned off for the install and back on right afterwards, also if something
  fails.
- The **pacman keyring** is set up (`pacman-key --init` and `--populate archlinux holo`).
- **Packages:** `glibc`, `linux-api-headers` and/or `gcc` are reinstalled to restore their header files;
  any of `gcc`, `binutils`, `git`, `python`, `zstd`, `vulkan-tools` that are missing get installed.
  Nothing else is touched.
- If `/etc/pacman.conf` tells pacman to skip `/usr/include`, that line is commented out for the
  install only. The original file is put back right afterwards, also if the install fails, before
  read-only mode is switched back on. (If restoring ever fails, the script says so and the original is
  in `/etc/pacman.conf.scb-oot.bak`.)

Always:

- Downloads and temporary files go to `~/scb-oot-build` (or `--workdir`) and `~/.cache/scb-oot`, and
  are deleted at the end, also when something fails (unless you pass `--keep-files`). Only what the
  script created is deleted: other files in a `--workdir` you chose are left alone, and that folder is
  removed only if it's empty afterwards.
- scb-oot installs the cache in the cache folder, after backing up what was there into a
  `scb-oot-backup-<date>` folder inside it.

**SteamOS updates** replace the system partition, which removes the installed packages and headers
again. The cache stays. If you want to build again after an update, run the script again; it reinstalls
what's missing.

## What the patch changes in scb-oot

The patch is built into the script (in the `SCB_OOT_PATCH_EOF` section) and applied to a clean scb-oot
checkout each run. Compared to scb-oot it:

- **compiles against current Lichii sources**: Lichii build 130 and later moved the shader lowering and
  hashing into `native_lowering.cpp`, which scb-oot didn't compile, so linking failed with
  `undefined reference to VideoCommon::NativeShaderHash`. It also adds a small stand-in for Lichii's
  logging header.
- **moves the hints onto the new shader hashes**: scb-oot's hints file records pipelines by shader
  hash, as Lichii build 125 computed them. Newer builds produce different code for the same shader, so
  the patch processes every shader with both builds (it downloads the build-125 sources into
  `~/.cache/scb-oot`, which the script deletes again at the end), then rewrites each pipeline to the new hashes and code sizes.
- **makes Lichii pick up the cache**: current Lichii keeps its cache in `lichii-cache.v2.bin` and
  converts scb-oot's `vulkan.fork-v54.bin` only while that file doesn't exist. The installer now
  backs it up and removes it, so Lichii converts the new cache on its next start.
- **uses Lichii's cache folder by default** on Linux (`~/.cache/lichii/shader/<title id>`) and
  refuses a `--cache-dir` that isn't the game's own folder.

## Troubleshooting

**`fatal error: features.h: No such file or directory`**
The C headers are missing (SteamOS removes them). Run the script without `--skip-deps`; it reinstalls
them.

**`undefined reference to VideoCommon::NativeShaderHash` (or similar)**
You ran plain scb-oot against a current Lichii. Use this script, which applies the patch.

**pacman errors (`error: ...`)**
- `not enough free disk space`: the system partition is full. Check with `df -h /`.
- Keyring or signature errors: run `sudo pacman-key --init` and
  `sudo pacman-key --populate archlinux holo`, then try again.
- If read-only mode stays off after a crash: `sudo steamos-readonly enable`.

**`the emulator cache folder ... does not exist`**
Start the game in Lichii once, close it, and run the script again. For a portable Lichii install, pass
`--cache-dir`.

**`could not download Lichii tag ...`**
The `--lichii-tag` doesn't exist. Check the names on the
[releases page](https://github.com/zortos293/Lichii/releases).

**`cannot detect the graphics driver`**
`vulkaninfo` failed. Run it in Desktop Mode rather than over SSH, or save `vulkaninfo > vkinfo.txt` and
pass `--vulkaninfo-file vkinfo.txt`.

**The game still compiles shaders on first start**
That's expected: Lichii builds the pipelines from the cache on the first start. About 500 pipelines
can't be regenerated from the game files and are built when the game first needs them.

**Going back to your old cache**
Close Lichii, then copy the files from the newest `scb-oot-backup-<date>` folder in
`~/.cache/lichii/shader/0400486024dec000` back into that folder, and delete `lichii-cache.v2.bin` if
the backup has its own.

## Removing everything

The script already deletes its downloads and temporary files when it finishes. If you used
`--keep-files` or `--keep-work`, or a run was killed, delete them yourself:

```bash
rm -rf ~/scb-oot-build ~/.cache/scb-oot
```

To remove the script itself, delete `~/scb-oot-deck.sh` or the `~/scb-oot-steamdeck` folder. The
installed packages can stay; a SteamOS update removes them anyway.

## Credits and license

- [scb-oot](https://github.com/rafaelsmiranda/scb-oot) by rafaelsmiranda: the shader cache builder
  this script runs and patches.
- [Lichii](https://github.com/zortos293/Lichii) by zortos293: the emulator, whose sources the build
  uses.

This project isn't affiliated with either, or with Nintendo or Valve.

The script contains a modified version of scb-oot code, so it's licensed under the
**GNU General Public License v3.0**, like scb-oot. See [LICENSE](LICENSE).
