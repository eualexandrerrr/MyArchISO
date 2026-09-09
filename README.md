[Português](README.pt-BR.md)

<div align="center">

# myarch

**Arch Linux installer**

Installs a clean base on UEFI + systemd-boot + ext4, and leaves the
[dotfiles](https://github.com/eualexandrerrr/dotfiles) cloned and ready for the first boot.

[![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat-square&logo=arch-linux&logoColor=white)](https://archlinux.org)
[![systemd-boot](https://img.shields.io/badge/systemd--boot-FF6600?style=flat-square&logo=linux&logoColor=white)](https://wiki.archlinux.org/title/Systemd-boot)
[![ext4](https://img.shields.io/badge/ext4-0A9BDC?style=flat-square&logo=linux&logoColor=white)](https://wiki.archlinux.org/title/Ext4)

</div>

---

## What it does

| Step | Detail |
|:--|:--|
| Checks | Requires root, UEFI boot and a working network |
| Live environment | `br-abnt2`, NTP, `reflector` over the BR/CL/US mirrors |
| **Preserved partitions** | Labels listed in `KEEP_LABELS` are **never** touched, wherever they sit on the disk. See [Two partitions](#two-partitions) |
| Partitioning | **Two partitions, that is all.** GPT: 1 GiB FAT32 ESP + root capped at 100 GiB (`ROOT_MAX_GB`) + the rest of the disk as the data partition |
| Data partition | Label `Files`, ext4, mounted at **`/home`**: created if missing, **reused untouched** if present. It is what makes reinstalling the system cost nothing |
| ext4 performance | `fast_commit` (short `fsync` path), `-m 1` on root and `-m 0` on data, tables written at `mkfs` time (`lazy_itable_init=0`) |
| Filesystem | ext4 with `noatime` (btrfs was dropped in 09/2026, see Decisions) |
| Base | `pacstrap` with `linux-zen` + headers, firmware, `amd-ucode` |
| Locale | `pt_BR.UTF-8`, `America/Sao_Paulo`, ABNT2 keyboard on the console and in X |
| User | Creates the user in `wheel` with the `zsh` shell and passwordless sudo |
| Bootloader | `systemd-boot` with a normal entry and a fallback, `systemd-boot-update.service` enabled, NVRAM entry verified |
| Swap | No partition: `zram-generator` with half the RAM, capped at 8 GiB, `zstd` |
| Performance | `amd_pstate=active`, `transparent_hugepage=always`, SteamOS's `vm.max_map_count`, `DefaultLimitNOFILE` for esync, `makepkg` with `-j$(nproc)`, `!debug` and `-march=native` |
| Mirrors | Weekly `reflector.timer`: Brazil only, https, the 10 fastest |
| Cache | `paccache.timer` prunes the `pacman` cache |
| NVIDIA | Already writes `nvidia_drm.modeset=1`, `nvidia_drm.fbdev=1`, `NVreg_PreserveVideoMemoryAllocations=1` and `NVreg_UsePageAttributeTable=1` |
| Dotfiles | Clones into `~/.dotfiles`, ready to run |

## The machine

The installer is generic, but it was written and tested on this PC. It is worth listing as a
reference of what it expects to find.

| Part | Model |
|:--|:--|
| CPU | AMD Ryzen 7 5700X, 8c/16t, AM4, **no integrated graphics** |
| Motherboard | ASUS TUF Gaming B550M-PLUS (mATX, B550) — x16 Gen4 off the CPU, x16 Gen3 (electrically x4) off the chipset, 2 M.2, 2.5G LAN |
| RAM | 32 GB DDR4 dual channel (4 slots, up to 128 GB) |
| Host GPU | PCYes Radeon RX 550 4GB — `amdgpu`, this is the one that draws KDE |
| VM GPU | Gainward RTX 3090 24GB — bound to `vfio-pci`, passed through to the Windows VM |
| SSD | Corsair MP700 ELITE 932 GB NVMe Gen4 |
| PSU | 850 W 80 Plus Gold |
| Case | PCYes Forcefield Mini Black Vulcan (mini tower, GPU up to 310 mm) |
| Monitors | ASUS XG27ACS 2560x1440@180Hz (landscape) + LG UltraGear 2560x1440 (portrait) |

**Two GPUs on purpose.** The RedM client does not get past the anticheat under Wine, so the game
runs in a Windows VM with a real GPU. A GPU passed through with `vfio` disappears from the host —
hence the RX 550: it is what keeps Linux on screen while the 3090 stays dedicated to the VM. The
3090 has a 2.7-slot cooler and physically blocks the slot below it, so the RX 550 hangs off a 20 cm
PCIe 3.0 x16 riser with a 90° plug.

`configure_nvidia()` in the [dotfiles](https://github.com/eualexandrerrr/dotfiles) and
`kernel-nvidia` in `packages.txt` are valid while the 3090 still draws the host; when it moves to
`vfio-pci`, both go away and binding by ID takes over (`10de:2204,10de:1aef`).

## Requirements

| Item | Requirement | Why |
|:--|:--|:--|
| Firmware | **UEFI**, with CSM/Legacy off | The script refuses to boot on legacy BIOS. It checks `/sys/firmware/efi/efivars` before touching any disk |
| Secure Boot | **off** | The Arch ISO is not signed, and neither is `nvidia-open-dkms` |
| Target disk | 20 GB minimum, 64 GB+ recommended | 1 GiB goes to the ESP, the rest is ext4. The base system alone takes ~3 GB, and `@pkg` keeps a package cache |
| Network in the live ISO | wired | `pacstrap` downloads about 900 MB. The custom ISO ships no Wi-Fi |
| USB stick | [Ventoy](https://ventoy.net) + the Arch ISO | Any 4 GB stick will do |
| Processor | x86-64 | There is no ARM support here |

The script installs both Intel **and** AMD microcode. The wrong one is ignored at boot, so the same
USB stick works for both platforms.

## Two partitions

The disk has **two partitions and nothing else** (the ESP does not count: 1 GiB, no drive letter,
invisible):

| | Label | Size | Filesystem | Mount | Role |
|:--|:--|:--|:--|:--|:--|
| system | `ROOT` | **100 GiB** (`ROOT_MAX_GB`) | ext4 | `/` | disposable: gone on every reinstall |
| data | `Files` | everything else | ext4 | **`/home`** | sacred: **never formatted** if it already exists |

**The label is sacred, the position does not matter.** The installer erases everything on the disk
**except** the partitions whose label (filesystem label or GPT partition label) is in `KEEP_LABELS`:

```bash
KEEP_LABELS="Files Alexandre HOME"     # "Alexandre" and "HOME" are old names, kept for safety
```

This is what makes the system genuinely disposable: root is the only thing lost on a reinstall, and
it holds nothing of yours — `~/.config`, `~/.claude`, `~/.dotfiles`, projects, the Steam library and
VM images all live outside of it. **It is the same contract as
[MyWinISO](https://github.com/eualexandrerrr/MyWinISO)**, which protects the same labels.

### Why ext4 and not NTFS on the data partition

It is `/home`. NTFS cannot serve as `/home`: the kernel's `ntfs3` does not create POSIX symlinks and
stores neither ownership nor the execute bit. The `dotfiles` `ln -sfn` everything and would die on
the first line, and every git repository would show every file as modified. It is not "worse", it is
broken.

A **legacy** NTFS data partition is still recognised and preserved, but it goes to `/mnt/dados` as a
shared area — it does not become `/home`, and the installer says why.

With `/home` preserved, the user is recreated with the **same UID and GID as before**, read from the
folder itself: ownership on ext4 is a number, not a name, and a different UID would make the whole
home look like it belongs to somebody else.

To bypass the protection and wipe the whole disk — a new disk, or a genuine fresh start:

```bash
WIPE_ALL=1 bash install.sh
```

Automatic mode **refuses** `WIPE_ALL`, and it also refuses a disk that already has partitions but
none of them protected: nobody is watching the screen in automatic mode, and ten seconds is not
warning enough to destroy data.

## Before installing

**Anything not protected by label is erased.** There is no resizing: the installer only creates
partitions in space that is already free. If you want a smaller data area to make room, shrink it
**first**, from the system already installed (Windows Disk Management does that on NTFS without
risk), and leave the free space waiting.

Before booting the USB stick:

1. **Take out whatever exists only on that disk and outside the protected partitions.** An unpushed
   repository, a folder that is not backed up, an SSH key, an application config file. Running
   `git status` in each project is worth it — uncommitted work does not reach GitHub by itself. What
   is on `HOME` or on `Files` stays; the rest of the disk does not.
2. **If there was Windows with BitLocker, save the recovery key first.** Turning Secure Boot off
   changes what the TPM measures, and Windows may demand the 48 digits on the next boot. This matters
   even if the plan is to erase Windows: if something goes wrong halfway through, you want to be able
   to go back. Get it from `manage-bde -protectors -get C:` or from
   `account.microsoft.com/devices/recoverykey`.
3. **Check the backup at the destination, not at the source.** A synced folder is not a backup until
   the file is on the other side. Open the service in a browser and look at the files there.
4. **Write down which disk is which.** In `lsblk`, check the model and size. `/dev/nvme0n1` and
   `/dev/nvme1n1` swap numbers between boots more often than you would think.

## BIOS: what to change

| Option | Value | Consequence of getting it wrong |
|:--|:--|:--|
| Secure Boot | **Disabled** | The ISO does not even show up in the boot menu |
| CSM / Legacy Boot | **Disabled** | The USB stick boots in legacy mode and the script stops at `preflight` |
| Boot Mode | **UEFI only** | Same as above |
| Fast Boot | Turn off if the USB stick does not appear | The firmware skips USB initialisation |
| SATA Mode | **AHCI** (not RAID / Intel RST) | Linux does not see the disk |

If the machine had Windows and you are going to keep another system around, also turn off Windows
**Fast Startup**: it hibernates NTFS, and mounting that from Linux corrupts it.

## Step-by-step installation

### 1. Prepare the USB stick

The stick is built with [Ventoy](https://ventoy.net), which boots an ISO as a file — you can have
Arch and Windows on the same stick and swap an ISO without rewriting anything.

```
USB STICK/
├── archlinux-2026.08.01-x86_64.iso
├── Win11_pt-BR.iso
└── myarch/
    ├── install.sh
    └── README.md
```

Download the ISO from [archlinux.org/download](https://archlinux.org/download/) and copy it to the
root of the stick. Ventoy finds it on its own. Or use this repo's [custom ISO](#custom-iso), which
already ships the installer inside and the right keyboard; in that case steps 3 and 4 come down to
picking `1` in the menu.

### 2. BIOS

Two things, that is all:

- **UEFI on.** The script refuses to boot on legacy BIOS, and it refuses early, before touching the
  disk.
- **Secure Boot off.** `nvidia-open-dkms` does not ship signed.

### 3. Boot and connect

Pick the Arch ISO in the Ventoy menu. A wired connection just works. On Wi-Fi:

```bash
iwctl
[iwd]# device list
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect NETWORK_NAME
[iwd]# exit
```

Check before going on — without a network the script stops right at the start:

```bash
ping -c1 archlinux.org
```

### 4. Run the installer

Straight from the USB stick, without downloading anything:

```bash
loadkeys br-abnt2
mkdir -p /mnt/usb && mount /dev/disk/by-label/Ventoy /mnt/usb
bash /mnt/usb/myarch/install.sh
```

Or by cloning, if you prefer the newest version:

```bash
loadkeys br-abnt2
pacman -Sy --noconfirm git
git clone https://github.com/eualexandrerrr/MyArchISO
bash myarch/install.sh
```

### 5. What it will ask

It lists the disks and asks for the target. **Check carefully:** the chosen disk is wiped whole, and
to confirm you have to type the full path, not `y` or `s`.

```
Disco de destino (ex: /dev/nvme0n1): /dev/nvme0n1
Digite exatamente o caminho do disco para confirmar (/dev/nvme0n1): /dev/nvme0n1
Hostname [RRR]:
Usuario [alexandre]:
Senha de alexandre:
Senha do root:
```

To skip the first question:

```bash
DISK=/dev/nvme0n1 bash install.sh
```

From there on it runs by itself. Most of the time is `pacstrap` downloading about 900 MB.

### 6. After the reboot

Remove the USB stick and log in as the user you created. The installer already left the dotfiles
cloned and a `PROXIMOS-PASSOS.txt` in the home directory:

```bash
cd ~/.dotfiles
./install.sh
```

That second stage is what installs KDE Plasma, the `nvidia-open-dkms` driver, `claude-code` and the
whole rice. Reboot again at the end.

## Automatic mode

```bash
AUTO=1 bash install.sh
```

It asks nothing. It is meant for reinstalling the same machine without typing:

| what | where it comes from |
|:--|:--|
| Disk | the largest internal disk (not removable, not USB), excluding the one carrying the live system and the configuration stick. A single internal disk = that one. **If the disk already has partitions and none of them is protected, it stops** instead of erasing |
| Hostname, user | `HOSTNAME_DEFAULT` and `USERNAME_DEFAULT` from the top of the script (`RRR`, `alexandre`), or `myarch.conf` |
| Password | `PASSWORD_HASH` (user and root get the same one). Without a hash, it asks for the password once |
| Warning | shows the disk and waits 10 seconds; any key cancels |
| Afterwards | schedules `myarch-firstboot.service`: on the first boot it runs `~/.dotfiles/install.sh` on tty1 and reboots into SDDM |

`myarch.conf` lives **outside the repository**, on the partition labelled `Ventoy` on the USB stick
(folder `myarch/`), because it carries the password hash:

```ini
HOSTNAME=RRR
USERNAME=alexandre
PASSWORD_HASH='$6$...'      # openssl passwd -6
```

The file is read with `grep`, not with `source`. `DISK=/dev/...` is accepted there too, to force the
target on a machine with more than one disk.

Two decisions that come with automatic mode and hold for manual mode as well: `wheel` gets
`NOPASSWD` in sudo (single-person desktop, the owner's request), and root and the user get the same
password.

## If something goes wrong

| What shows up | What it is | What to do |
|:--|:--|:--|
| `o sistema nao bootou em UEFI` | Still on legacy BIOS | Turn UEFI on in the board's setup |
| `sem internet` | No network in the live ISO | Connect with `iwctl`, or use a cable |
| `nao e um dispositivo de bloco` | Wrong disk path | Check with `lsblk` |
| `confirmacao nao bateu` | You typed something different | Nothing on the disk was touched. Run it again |
| `AVISO: nao registrei a entrada de boot na NVRAM` | The firmware refused to write | The system still boots, through the ESP's removable path. You can create the entry later with `efibootmgr` |

The script only erases a disk after all the checks and the typed confirmation. If it dies before
that, your disk is intact.

If it hangs mid-installation, it is safe to simply run it again: it repartitions from scratch, it
does not try to reuse previous state.

## If the desktop does not come up

Option **4** of the live menu reinstalls only the dotfiles, without touching any partition: it mounts
ROOT, puts the data partition at `/home`, does `arch-chroot`, deletes `~/.dotfiles`, clones from
GitHub, runs the dotfiles repo's `install.sh` as the owner of `/home` and reboots.

It exists because the desktop configuration lives in `/home`, which survives formatting. Reinstalling
the whole of Arch does not fix a compositor that will not start — `~/.config` comes back identical.
Before this, the only way out was mounting everything by hand from the shell.

It needs a network: the dotfiles come from GitHub, not from the ISO. The reboot is automatic after
10 s, with `[esc]` to cancel.


## Fixing without formatting

Option **6** opens a submenu dedicated to recovery. Nothing in there formats a disk: everything
mounts ROOT at `/mnt/sys`, puts the data partition at `/mnt/sys/home` and the ESP at
`/mnt/sys/boot`, does what was asked and unmounts on the way out. Mount order matters — without the
ESP mounted, `bootctl` and `mkinitcpio` write to the wrong place and the disk still will not boot.

| Option | For when | What it does |
|:--|:--|:--|
| 1 | anything that needs hands-on work | `arch-chroot` into a shell inside the system on the disk |
| 2 | boot stuck at `fsck`, dirty shutdown | `e2fsck -fp` on `ROOT` and `Files`, with the partitions unmounted |
| 3 | the systemd-boot menu is gone | `bootctl install`, `bootctl update` and lists the entries |
| 4 | a new kernel cannot find its modules | `mkinitcpio -P` |
| 5 | an update interrupted halfway | reinstalls `linux-zen`, `linux-firmware` and `systemd` |
| 6 | `invalid or corrupted package (PGP signature)` | rebuilds the pacman keyring and sync database |
| 7 | forgotten password | `passwd` on the uid 1000 user or on root |
| 8 | no idea why it did not come up | errors and the tail of the **previous boot**, read straight from `/var/log/journal` |
| 9 | checking before touching anything | `lsblk`, the labels myarch uses and the free space |

`e2fsck` only runs on an unmounted partition — mounted, it either refuses or corrupts. That is why
option 2 unmounts everything first and skips whatever is still in use, saying which it skipped. Exit
code 1 from `e2fsck` means "found errors and fixed them", not a failure; 4 is the case automatic mode
cannot solve, and then the menu shows the command to run by hand.

Option **5 of the main menu** is the middle ground between doing nothing and re-pulling everything:
it runs only the `setup.sh` of the dotfiles repo already on the disk. It does not clone, does not
install packages, does not touch the network. It is the path for when what broke was a stow symlink
or the compositor's config.

## If an update breaks something

No snapshots: the way out is the USB stick. Boot the live system, mount root and fix it from there
(`arch-chroot /mnt`, `pacman -U /var/cache/pacman/pkg/<previous-package>`).

```bash
mount /dev/nvme0n1p2 /mnt && mount /dev/nvme0n1p1 /mnt/boot && arch-chroot /mnt
```

## Defaults

Editable at the top of `install.sh`:

```bash
HOSTNAME_DEFAULT="RRR"
USERNAME_DEFAULT="alexandre"
TIMEZONE="America/Sao_Paulo"
LOCALE="pt_BR.UTF-8"
KEYMAP="br-abnt2"
ESP_SIZE="1GiB"
```

## Decisions

- **systemd-boot instead of GRUB** — on pure UEFI, GRUB is dead weight. Faster boot, and the
  configuration is a 6-line text file.
- **ext4 instead of btrfs** (09/2026) — the owner's decision, for performance: no CoW, no
  compression, no data checksums, less work per write while gaming and compiling. The price is having
  no snapshots and no rollback; the btrfs + `snapper` + `snap-pac` version stays in the git history
  (`git log --before=2026-09-06`).
- **No encryption** — a desktop that does not move, a disk that never leaves the desk. LUKS and
  Secure Boot are deliberately left out: `nvidia-open-dkms` does not ship signed, so Secure Boot would
  drag `sbctl` and a UKI along with it.
- **zram instead of a swap partition or file** — swap on disk is only good for hibernating, and
  hibernating with the proprietary NVIDIA driver is a source of pain. `vm.swappiness=180` is the right
  value for compressed swap in RAM; the default 60 assumes a slow disk.
- **ESP mounted with `fmask=0077,dmask=0077`** — without it `systemd` complains that the random seed
  file is readable by any user, and `genfstab` stamps the loose mount into `fstab`.
- **`linux-zen` and `amd-ucode` only** (09/2026) — a gaming machine with a Ryzen: zen brings a
  scheduler and timers aimed at the desktop; `intel-ucode` was dead weight. For another machine,
  change the two lines in `BASE_PACKAGES` and in the `systemd-boot` entries.
- **Performance tuning in the chroot, not in the dotfiles** — `sysctl`, systemd limits,
  `makepkg.conf.d` and `reflector.conf` belong to the system, so they are born with it. What belongs
  to the session (power profile, `ananicy-cpp`, GPU mode) stays in the dotfiles.
- **Preserving by label, not by position** (09/2026) — this household's Windows installer protected
  "the last partition on the disk". Creating one partition after it is enough to make the rule point
  at the wrong one. A label does not move when the disk is repartitioned, a number does; that is why
  the protection is by `KEEP_LABELS` and the partition number is discovered at run time.
- **System in the first free gap, `/home` in the largest one** — picking the largest hole for root
  feels natural and is wrong: on a disk where the big space is at the end, root would be born there
  and there would be no room left for a separate `/home`. Measured in a test with a fake disk before
  touching a real one.
- **`/home` on its own partition instead of junctions** — on Windows the persistent area is made of
  junctions from `%APPDATA%` to another disk, with a scheduled task fixing up whatever was in use. On
  Linux none of that is needed: `/home` on a partition the installer does not format solves the same
  problem with no moving parts.
- **Two partitions, and the data one is ext4** (09/2026) — the owner's decision. Windows now lives
  only in a VM with passthrough, and a VM does not read a partition: it gets a shared folder and sees
  a drive letter. With nobody needing to read the disk from Windows, there is no longer any reason to
  let NTFS get in the way of `/home`.
- **`-m 0` on the data partition** — ext4's 5% reserve exists so root can still log in on a full
  disk; that only makes sense on the system root. On 690 GiB of data that would be 34 GiB sitting
  there serving nothing. On root it is 1%, which already does the job in 100 GiB.
- **`fast_commit` on both** — it shortens the `fsync` path, which is what shows up most with VM
  images, databases and compilation.
- **`lazy_itable_init=0` at `mkfs`** — writes the tables right away instead of leaving a thread
  finishing up in the background during the first hours of use. It costs seconds during installation
  and avoids unexplained slowness right after it.
- **`ntfs3` and not `ntfs-3g`** — `ntfs3` has been a kernel driver since 5.15; `ntfs-3g` runs in
  userspace through FUSE and is much slower. The `ntfs-3g` package stays installed for the tools
  (`mkntfs`, `ntfsfix`), not for mounting.
- **`mkinitcpio -P` before writing the boot entries** — the `linux` package's preset does not always
  ship with `fallback` enabled. Without checking, the "Arch Linux (fallback)" entry would show up in
  the menu pointing at an image that was never generated: it only bites on the day you need it.
  `fallback` is enabled in the preset, not generated by hand, so that the `pacman` hook regenerates it
  on every kernel update.
- **The `pacman.conf` option adjusted by a function, not by a `sed` anchored at `^#`** — pacman 6.1
  started shipping `ParallelDownloads` already enabled. A `sed` that only matches the commented line
  stopped adjusting anything, and failed silently.
- **The boot entry verified after `bootctl install`** — when the firmware refuses to write to NVRAM,
  `bootctl` does not complain, and the machine ends up depending on the ESP's removable path, which
  another operating system can overwrite.

## Warnings

- The script **erases everything not protected by label** on the chosen disk. It asks for a typed
  confirmation and lists what it will preserve, but check the target with `lsblk` first. Dual-booting
  two systems on the same disk does not exist here: root is always recreated, so installing Arch
  removes the Windows that was at the front of the disk (and vice versa) — what survives is the data,
  not the other system.
- Requires UEFI boot. Legacy BIOS is not supported.
- Secure Boot has to be disabled — `nvidia-open-dkms` is not signed.

## The menu also updates itself

For the same reason as the installer: the ISO freezes the `myarch-menu` of the commit it was built
from, so a new option would only reach the USB stick by rebuilding the image. On startup it downloads
its own version from GitHub, replaces itself and re-executes once. `MYARCH_MENU_ATUALIZADO` breaks the
loop.

It only swaps itself out if the downloaded file is valid bash (shebang plus `bash -n`) and different
from the current one. A half-finished download would overwrite the menu with garbage and leave the
live system with no interface at all. With no network, it carries on with the ISO's version without
complaining.

This applies to the menu only. `install.sh` keeps its own download path and its own checks, described
below.

## The installer comes from GitHub, not from the ISO

**Menu options 1 and 2 download `install.sh` from GitHub on the spot.** The copy inside the ISO is
plan B, for when there is no network — and the menu tells you how old it is.

It is the same design as [MyWinISO](https://github.com/eualexandrerrr/MyWinISO), where
`primeiro-logon.ps1` downloads `setup.ps1` instead of carrying it inside the XML. The reason: **the
ISO freezes the installer of the commit it was built from**, and a two-week-old ISO installs a
two-week-old system. That nearly cost dearly here — the ISO from 05/09/2026 carries the version that
wiped the whole disk without preserving the data partition, and it would keep doing that forever.
Fetching on the spot lets the ISO age without rotting.

What gets downloaded goes through a check before running (`protege_particao`): it has to be a bash
script and it has to contain `KEEP_LABELS` and `particoes_protegidas`. **An installer that does not
know how to preserve a partition by label does not run** — neither downloaded nor embedded. With no
network and an old ISO, the menu refuses and explains, instead of erasing the disk:

```
PAREI. O instalador embutido nesta ISO (abc1234 de 05/09/2026) NAO sabe preservar particao
por rotulo: ele apagaria o disco inteiro, incluindo a particao de dados.
```

The same check blocks a captive Wi-Fi portal page and a download that arrived half-finished — the two
cases where "download from the internet and execute" usually goes wrong.

## Custom ISO

The `archiso/` folder is an [archiso](https://gitlab.archlinux.org/archlinux/archiso) profile (a copy
of `releng`, the same one that produces the official ISO) with what changes for this machine:

- `br-abnt2` keyboard, `pt_BR.UTF-8` and the `America/Sao_Paulo` timezone already in the live system,
  no `loadkeys` needed;
- `install.sh` and this README embedded in `/root/myarch/`, so there is no need to mount Ventoy or to
  have internet to find the installer;
- a menu on tty1 after autologin (`myarch-menu`): `1` installs automatically (see [Automatic
  mode](#automatic-mode)), `2` installs asking questions, `3` uses the embedded copy without
  downloading, `4` re-pulls the dotfiles, `5` only reapplies the config, `6` opens the recovery
  submenu (see [Fixing without formatting](#fixing-without-formatting)), shell, reboot, power off.
  With `script=` on the boot line the menu does not appear, same as releng;
- a trimmed package list (`archiso/packages.x86_64`, 40 packages): kernel, firmware, boot, network
  (wired and Wi-Fi), what `install.sh` calls and basic rescue tooling (`ntfs-3g`, `exfatprogs`,
  `rsync`, `7zip`, `tmux`, `htop`, `nvme-cli`, `smartmontools`, `openssh`). Left out: Wi-Fi, PXE,
  clonezilla, VPN, modem, screen reader, VirtualBox/VMware/Hyper-V guest tools, cloud-init, smartcard.

Building it requires Arch with root and the `archiso` package; the way without a Linux machine is the
**build-iso** workflow (Actions → build-iso → Run workflow), which runs in an `archlinux` container,
takes about 15 minutes and publishes `myarch-<date>-x86_64.iso` plus the `.sha256` in an `iso-<date>`
release. Locally:

```bash
sudo pacman -S archiso
sudo ./archiso/build.sh        # ISO in archiso/out/
```

`build.sh` copies `install.sh` from the repo root into the profile at build time (the copy is in
`.gitignore`) and writes a `VERSAO` with the commit and the date — that is what the menu shows when
warning that it is using the embedded copy. That copy is only plan B: with a network, the menu
downloads the newest version (see [The installer comes from
GitHub](#the-installer-comes-from-github-not-from-the-iso)). The `airootfs` symlinks are stored in git
as real symlinks: do not edit that folder from Windows without `core.symlinks=true`, or they turn into
text files and the live system breaks silently.

### Rebuilding the ISO: `atualizar-iso.ps1`

From Windows, one line does everything — it triggers the build, waits, downloads, **checks the
`sha256`**, copies it to the USB stick, points the `menu_alias` in `ventoy.json` at the new ISO,
removes the old one and updates the loose `install.sh` on the stick:

```powershell
.\atualizar-iso.ps1 -Pendrive E:
```

| Form | What it does |
|:--|:--|
| `.\atualizar-iso.ps1` | triggers the build, waits, downloads and checks. Does not touch the USB stick |
| `.\atualizar-iso.ps1 -Pendrive E:` | the above, and installs onto the USB stick |
| `.\atualizar-iso.ps1 -SemBuild -Pendrive E:` | triggers nothing: takes the latest already published release |
| `-Token ghp_...` | explicit token; without it, it uses `$env:GH_TOKEN` or `gh auth token` |

Details the script takes care of, and that are easy to forget when doing it by hand:

- **If a build is already running, it follows that one** instead of stacking another — the workflow
  has `concurrency` without `cancel-in-progress`, so triggering twice only creates a queue.
- **It checks the `sha256` before writing** and aborts if it does not match.
- **It only deletes the old ISO after the new one is in place.** While the old one is on the stick it
  is one more option in the Ventoy menu — and an old ISO carries an old `myarch-menu`, which runs its
  own embedded installer instead of downloading the new one.
- **It preserves the rest of `ventoy.json`**, including the entries for the other ISOs and the theme;
  it only changes the `menu_alias` of ours, keeping the text that was already there. The same rule as
  MyWinISO's `pendrive.ps1`, because `ventoy.json` belongs to the USB stick, not to this repository.
- **It writes the USB stick's `install.sh` with LF**, which is what bash reads.
- The token only talks to the API; the download goes without it (the repository is public, and sending
  the authorization header along the redirect to object storage makes it refuse).

### When rebuilding is worth it

Ever since the menu started downloading `install.sh` from GitHub on the spot, rebuilding the ISO has
become rare — it is a boot vehicle, and what decides what happens to the disk lives in the repository.
It is worth it when:

- `myarch-menu`, the `archiso/` profile or the live package list changed;
- the live system is old enough that its kernel cannot see new hardware;
- you want to install **without a network** — then the embedded copy is the only one there is.

You write it the same way: copy the `.iso` onto the Ventoy stick.

To test before writing, `archiso/test-qemu.ps1` boots the ISO in a Windows QEMU (TCG, no Hyper-V) with
a 30 GB virtio disk and a small disk labelled `Ventoy` playing the part of the USB stick with
`myarch/myarch.conf`; the monitor is on `127.0.0.1:4445` for sending keys and capturing the screen.
That is how automatic mode was validated end to end before formatting anything.

## Related repositories

- [eualexandrerrr/dotfiles](https://github.com/eualexandrerrr/dotfiles) — the rice that runs on top of this base

<div align="center">
<sub>The <code>backup/legacy-2023</code> branch keeps the old installer, with GRUB and i3.</sub>
</div>
