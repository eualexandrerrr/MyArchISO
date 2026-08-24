#!/usr/bin/env bash

set -euo pipefail

HOSTNAME_DEFAULT="ryzen"
USERNAME_DEFAULT="alexandre"
TIMEZONE="America/Sao_Paulo"
LOCALE="pt_BR.UTF-8"
KEYMAP="br-abnt2"
X11_KEYMAP="br"
ESP_SIZE="1GiB"
FILESYSTEM="btrfs"
SUBVOLUMES=(@ @home @log @pkg @snapshots)
KERNEL_PARAMS=(nvidia_drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1 rw quiet)
DOTFILES_REPO="https://github.com/eualexandrerrr/dotfiles"

BASE_PACKAGES=(
    base base-devel linux linux-headers linux-firmware
    btrfs-progs dosfstools e2fsprogs
    networkmanager
    sudo git nano vim
    intel-ucode amd-ucode
    zsh
    efibootmgr
    reflector
    man-db man-pages
    openssh
)

RED=$'\e[1;31m'; GRN=$'\e[1;32m'; YEL=$'\e[1;33m'; BLU=$'\e[1;34m'; BLD=$'\e[1m'; END=$'\e[0m'

log()  { printf '\n%s==>%s %s%s%s\n' "$BLU" "$END" "$BLD" "$*" "$END"; }
ok()   { printf '%s  ok%s %s\n' "$GRN" "$END" "$*"; }
warn() { printf '%s  !!%s %s\n' "$YEL" "$END" "$*"; }
die()  { printf '\n%serro:%s %s\n' "$RED" "$END" "$*" >&2; exit 1; }

banner() {
    printf '%s' "$BLU"
    cat <<'EOF'
                    _
   _ __ ___  _   _ / \   _ __ ___| |__
  | '_ ` _ \| | | / _ \ | '__/ __| '_ \
  | | | | | | |_| / ___ \| | | (__| | | |
  |_| |_| |_|\__, /_/   \_\_|  \___|_| |_|
             |___/
EOF
    printf '%s\n' "$END"
}

preflight() {
    log "verificando o ambiente"
    [[ $EUID -eq 0 ]] || die "rode como root, voce esta no live ISO"
    [[ -d /sys/firmware/efi/efivars ]] || die "o sistema nao bootou em UEFI, habilite UEFI na BIOS"
    ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "sem internet, use iwctl para conectar o wifi"
    ok "UEFI, root e rede confirmados"
}

prepare_live() {
    log "preparando o ambiente live"
    loadkeys "$KEYMAP"
    timedatectl set-ntp true
    pacman -Sy --noconfirm archlinux-keyring >/dev/null
    if command -v reflector >/dev/null 2>&1; then
        reflector --country Brazil,Chile,United\ States --age 12 --protocol https \
            --sort rate --save /etc/pacman.d/mirrorlist >/dev/null 2>&1 \
            && ok "mirrorlist otimizado" || warn "reflector falhou, seguindo com a lista padrao"
    fi
    sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    ok "ambiente live pronto"
}

pick_disk() {
    log "discos disponiveis"
    lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -vE 'loop|/dev/sr|/dev/zram'
    printf '\n'

    if [[ -n ${DISK:-} ]]; then
        [[ -b $DISK ]] || die "DISK=$DISK nao e um dispositivo de bloco"
    else
        read -rp "Disco de destino (ex: /dev/nvme0n1): " DISK
        [[ -b $DISK ]] || die "$DISK nao e um dispositivo de bloco"
    fi

    printf '\n%s' "$RED"
    cat <<EOF
================================================================
  ATENCAO: TODO o conteudo de $DISK vai ser APAGADO.
  Tamanho: $(lsblk -dno SIZE "$DISK")
  Modelo:  $(lsblk -dno MODEL "$DISK")
================================================================
EOF
    printf '%s\n' "$END"
    lsblk "$DISK"
    printf '\n'

    local confirm
    read -rp "Digite exatamente o caminho do disco para confirmar ($DISK): " confirm
    [[ $confirm == "$DISK" ]] || die "confirmacao nao bateu, nada foi alterado"

    if [[ $DISK == *nvme* || $DISK == *mmcblk* ]]; then
        ESP="${DISK}p1"; ROOT="${DISK}p2"
    else
        ESP="${DISK}1"; ROOT="${DISK}2"
    fi
    ok "alvo: $DISK  (ESP=$ESP  ROOT=$ROOT)"
}

ask_identity() {
    log "identidade da maquina"
    read -rp "Hostname [$HOSTNAME_DEFAULT]: " HOSTNAME
    HOSTNAME="${HOSTNAME:-$HOSTNAME_DEFAULT}"
    read -rp "Usuario [$USERNAME_DEFAULT]: " USERNAME
    USERNAME="${USERNAME:-$USERNAME_DEFAULT}"

    local p1 p2
    while true; do
        read -rsp "Senha de $USERNAME: " p1; printf '\n'
        read -rsp "Confirme a senha: " p2; printf '\n'
        [[ -n $p1 ]] || { warn "senha vazia nao serve"; continue; }
        [[ $p1 == "$p2" ]] && break
        warn "as senhas nao batem"
    done
    USER_PASSWORD="$p1"

    while true; do
        read -rsp "Senha do root: " p1; printf '\n'
        read -rsp "Confirme a senha do root: " p2; printf '\n'
        [[ -n $p1 ]] || { warn "senha vazia nao serve"; continue; }
        [[ $p1 == "$p2" ]] && break
        warn "as senhas nao batem"
    done
    ROOT_PASSWORD="$p1"
    ok "usuario $USERNAME em $HOSTNAME"
}

wipe_disk() {
    log "particionando $DISK"
    swapoff --all 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    wipefs -af "$DISK" >/dev/null
    sgdisk --zap-all "$DISK" >/dev/null
    partprobe "$DISK" 2>/dev/null || true

    sgdisk -n 1:0:+"$ESP_SIZE" -t 1:ef00 -c 1:"EFI" "$DISK" >/dev/null
    sgdisk -n 2:0:0           -t 2:8300 -c 2:"ROOT" "$DISK" >/dev/null
    partprobe "$DISK" 2>/dev/null || true
    sleep 2
    ok "GPT criado: ESP $ESP_SIZE + root no restante"
}

make_filesystems() {
    log "formatando"
    mkfs.fat -F32 -n EFI "$ESP" >/dev/null
    mkfs.btrfs -f -L ROOT "$ROOT" >/dev/null
    ok "ESP em FAT32, root em btrfs"

    log "criando subvolumes"
    mount "$ROOT" /mnt
    local sv
    for sv in "${SUBVOLUMES[@]}"; do
        btrfs subvolume create "/mnt/$sv" >/dev/null
        ok "subvolume $sv"
    done
    umount /mnt
}

mount_filesystems() {
    log "montando"
    local opts="noatime,compress=zstd:3,ssd,space_cache=v2"
    mount -o "$opts,subvol=@" "$ROOT" /mnt
    mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
    mount -o "$opts,subvol=@home"      "$ROOT" /mnt/home
    mount -o "$opts,subvol=@log"       "$ROOT" /mnt/var/log
    mount -o "$opts,subvol=@pkg"       "$ROOT" /mnt/var/cache/pacman/pkg
    mount -o "$opts,subvol=@snapshots" "$ROOT" /mnt/.snapshots
    mount "$ESP" /mnt/boot
    ok "arvore montada em /mnt"
    findmnt -R /mnt -o TARGET,SOURCE,FSTYPE | head -10
}

install_base() {
    log "instalando o sistema base"
    pacstrap -K /mnt "${BASE_PACKAGES[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
    ok "base instalada e fstab gerado"
}

configure_system() {
    log "configurando o sistema instalado"

    local script=/mnt/root/chroot-setup.sh
    cat > "$script" <<CHROOT
#!/usr/bin/env bash
set -euo pipefail

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

sed -i "s/^#$LOCALE/$LOCALE/" /etc/locale.gen
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
printf 'LANG=%s\n' "$LOCALE" > /etc/locale.conf
printf 'KEYMAP=%s\n' "$KEYMAP" > /etc/vconsole.conf

printf '%s\n' "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<KB
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$X11_KEYMAP"
EndSection
KB

printf 'root:%s' "$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel,audio,video,storage,input -s /bin/zsh "$USERNAME"
printf '%s:%s' "$USERNAME" "$USER_PASSWORD" | chpasswd
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
grep -qE '^\[multilib\]' /etc/pacman.conf || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
pacman -Sy --noconfirm >/dev/null

systemctl enable NetworkManager.service
systemctl enable systemd-timesyncd.service
systemctl enable fstrim.timer

bootctl install

cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 3
console-mode max
editor no
LOADER

ROOT_UUID=\$(blkid -s UUID -o value "$ROOT")

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=\$ROOT_UUID rootflags=subvol=@ ${KERNEL_PARAMS[*]}
ENTRY

cat > /boot/loader/entries/arch-fallback.conf <<ENTRY
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /initramfs-linux-fallback.img
options root=UUID=\$ROOT_UUID rootflags=subvol=@ ${KERNEL_PARAMS[*]}
ENTRY

mkinitcpio -P
CHROOT

    chmod +x "$script"
    arch-chroot /mnt /root/chroot-setup.sh
    rm -f "$script"
    ok "sistema configurado, systemd-boot instalado"
}

stage_dotfiles() {
    log "deixando os dotfiles prontos para o primeiro boot"
    local home="/mnt/home/$USERNAME"
    arch-chroot /mnt sudo -u "$USERNAME" git clone --depth 1 "$DOTFILES_REPO" "/home/$USERNAME/.dotfiles" \
        || { warn "clone dos dotfiles falhou, faca manualmente depois"; return 0; }

    cat > "$home/PROXIMOS-PASSOS.txt" <<STEPS
Depois de reiniciar e logar como $USERNAME:

    cd ~/.dotfiles
    ./install.sh

Isso instala o Hyprland, o Quickshell, o driver nvidia-open-dkms e aplica
o rice inteiro. Reinicie de novo no fim.
STEPS
    arch-chroot /mnt chown "$USERNAME:$USERNAME" "/home/$USERNAME/PROXIMOS-PASSOS.txt"
    ok "dotfiles clonados em /home/$USERNAME/.dotfiles"
}

finish() {
    log "concluido"
    umount -R /mnt 2>/dev/null || warn "algo continua montado em /mnt"
    printf '\n%s' "$GRN"
    cat <<EOF
================================================================
  Arch instalado em $DISK
  Hostname: $HOSTNAME   Usuario: $USERNAME
  Bootloader: systemd-boot
  Layout: btrfs com subvolumes ${SUBVOLUMES[*]}

  Reinicie, tire o pendrive e logue como $USERNAME.
  Depois rode:  cd ~/.dotfiles && ./install.sh
================================================================
EOF
    printf '%s\n' "$END"
}

main() {
    banner
    preflight
    prepare_live
    pick_disk
    ask_identity
    wipe_disk
    make_filesystems
    mount_filesystems
    install_base
    configure_system
    stage_dotfiles
    finish
}

main "$@"
