#!/usr/bin/env bash

set -euo pipefail

HOSTNAME_DEFAULT="RRR"
USERNAME_DEFAULT="alexandre"

# AUTO=1: nao pergunta nada. Disco = maior disco interno que nao e o pendrive;
# hostname e usuario = padroes acima; senha = PASSWORD_HASH (do ambiente ou de um
# myarch/myarch.conf na particao rotulada CONF_LABEL, o pendrive do Ventoy). Sem
# hash, pergunta so a senha. Antes de apagar o disco mostra o resumo e espera 10 s.
# No fim agenda o install.sh dos dotfiles pro primeiro boot (myarch-firstboot).
AUTO="${AUTO:-0}"
CONF_LABEL="${CONF_LABEL:-Ventoy}"
CONF_FILE="myarch/myarch.conf"
PASSWORD_HASH="${PASSWORD_HASH:-}"
CONF_DISK=""
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
    snapper snap-pac pacman-contrib
    networkmanager
    sudo git nano vim
    intel-ucode amd-ucode
    zsh
    efibootmgr
    zram-generator
    reflector
    man-db man-pages
    openssh
)

RED=$'\e[1;31m'; GRN=$'\e[1;32m'; YEL=$'\e[1;33m'; BLU=$'\e[1;34m'; BLD=$'\e[1m'; END=$'\e[0m'

log()  { printf '\n%s==>%s %s%s%s\n' "$BLU" "$END" "$BLD" "$*" "$END"; }
ok()   { printf '%s  ok%s %s\n' "$GRN" "$END" "$*"; }
warn() { printf '%s  !!%s %s\n' "$YEL" "$END" "$*"; }
die()  { printf '\n%serro:%s %s\n' "$RED" "$END" "$*" >&2; exit 1; }

# O pacman 6.1 passou a entregar ParallelDownloads ATIVO (valor 5) no
# pacman.conf. Um `sed 's/^#ParallelDownloads.*/.../'` so casa quando a opcao
# esta comentada, entao desde entao ele nao ajusta nada e falha calado. Isto aqui
# cobre os tres casos: comentada, ativa com outro valor, e ausente.
set_pacman_option() {
    local key="$1" value="$2" file="${3:-/etc/pacman.conf}"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
    elif grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*$" "$file"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*$|${key} = ${value}|" "$file"
    else
        sed -i "/^\[options\]/a ${key} = ${value}" "$file"
    fi
}

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
    ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "sem internet, confira o cabo de rede"
    ok "UEFI, root e rede confirmados"
}

prepare_live() {
    log "preparando o ambiente live"
    loadkeys "$KEYMAP"
    timedatectl set-ntp true

    # O live ISO monta o chaveiro em background, no pacman-init.service. Mexer no
    # pacman antes disso terminar da "unknown trust" e derruba o script inteiro.
    # Em oneshot ja rodando, o `start` espera terminar em vez de rodar de novo.
    if systemctl cat pacman-init.service >/dev/null 2>&1; then
        if systemctl start pacman-init.service >/dev/null 2>&1; then
            ok "chaveiro do live ISO pronto"
        else
            warn "pacman-init.service reclamou, seguindo"
        fi
    fi

    # --needed porque o ISO ja traz o chaveiro do dia em que foi gerado; isso so
    # importa em ISO velha. Falhar aqui nao e motivo pra abortar a instalacao: o
    # pacstrap -K monta um chaveiro proprio no destino de qualquer jeito.
    if ! pacman -Sy --noconfirm --needed archlinux-keyring >/dev/null 2>&1; then
        warn "nao atualizei o archlinux-keyring, seguindo com o do ISO"
    fi
    if command -v reflector >/dev/null 2>&1; then
        reflector --country Brazil,Chile,United\ States --age 12 --protocol https \
            --sort rate --save /etc/pacman.d/mirrorlist >/dev/null 2>&1 \
            && ok "mirrorlist otimizado" || warn "reflector falhou, seguindo com a lista padrao"
    fi
    set_pacman_option ParallelDownloads 10
    ok "ambiente live pronto"
}

load_conf() {
    # Le HOSTNAME, USERNAME, PASSWORD_HASH e DISK de myarch/myarch.conf na particao
    # rotulada $CONF_LABEL. grep em vez de source: o arquivo vem de um pendrive.
    local dev mnt val key
    dev="$(blkid -L "$CONF_LABEL" 2>/dev/null || true)"
    [[ -n $dev ]] || return 0
    local pk; pk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)"
    CONF_DISK="${pk:+/dev/$pk}"; CONF_DISK="${CONF_DISK:-$dev}"
    mnt="$(mktemp -d)"
    mount -o ro "$dev" "$mnt" 2>/dev/null || { rmdir "$mnt"; return 0; }
    if [[ -f "$mnt/$CONF_FILE" ]]; then
        log "lendo $CONF_FILE do pendrive $CONF_LABEL"
        for key in HOSTNAME USERNAME PASSWORD_HASH DISK; do
            val="$(grep -E "^${key}=" "$mnt/$CONF_FILE" | tail -1 | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//" | tr -d '\r')"
            [[ -n $val ]] || continue
            case "$key" in
                HOSTNAME) HOSTNAME_DEFAULT="$val" ;;
                USERNAME) USERNAME_DEFAULT="$val" ;;
                PASSWORD_HASH) PASSWORD_HASH="$val" ;;
                DISK) DISK="${DISK:-$val}" ;;
            esac
            ok "$key definido pelo pendrive"
        done
    fi
    umount "$mnt"; rmdir "$mnt"
}

live_disk() {
    # Disco que carrega o proprio live (ISO gravada direto ou pendrive do Ventoy).
    local src pk
    src="$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
    [[ -n $src && $src != /dev/loop* ]] || return 0
    pk="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"
    printf '%s\n' "${pk:+/dev/$pk}"
}

auto_disk() {
    # Candidatos: tipo disk, nao removivel, nao USB, fora o disco do live e o do pendrive de conf.
    local live name rm tran size best=0 bestname=""
    live="$(live_disk)"
    while read -r name rm tran size; do
        [[ $name == /dev/loop* || $name == /dev/sr* || $name == /dev/zram* ]] && continue
        [[ $rm == 1 || $tran == usb ]] && continue
        [[ $name == "$live" || $name == "$CONF_DISK" ]] && continue
        if (( size > best )); then best=$size; bestname=$name; fi
    done < <(lsblk -dbno NAME,RM,TRAN,SIZE -p 2>/dev/null | awk '{ if (NF == 3) print $1, $2, "-", $3; else print $1, $2, $3, $4 }')
    [[ -n $bestname ]] || die "nenhum disco interno encontrado para instalar"
    printf '%s\n' "$bestname"
}

pick_disk() {
    log "discos disponiveis"
    lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -vE 'loop|/dev/sr|/dev/zram'
    printf '\n'

    if [[ -n ${DISK:-} ]]; then
        [[ -b $DISK ]] || die "DISK=$DISK nao e um dispositivo de bloco"
    elif [[ $AUTO == 1 ]]; then
        DISK="$(auto_disk)"
        ok "disco escolhido sozinho: $DISK (maior disco interno)"
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
    if [[ $AUTO == 1 ]]; then
        printf '%s  modo automatico: hostname %s, usuario %s, senha %s%s\n' "$YEL" "$HOSTNAME_DEFAULT" "$USERNAME_DEFAULT" \
            "$([[ -n $PASSWORD_HASH ]] && echo 'do pendrive' || echo 'vai ser perguntada')" "$END"
        printf '%s  apagando %s em 10 segundos. Qualquer tecla cancela.%s\n' "$RED" "$DISK" "$END"
        if read -rs -t 10 -n 1 confirm; then die "cancelado, nada foi alterado"; fi
        printf '\n'
    else
        read -rp "Digite exatamente o caminho do disco para confirmar ($DISK): " confirm
        [[ $confirm == "$DISK" ]] || die "confirmacao nao bateu, nada foi alterado"
    fi

    if [[ $DISK == *nvme* || $DISK == *mmcblk* ]]; then
        ESP="${DISK}p1"; ROOT="${DISK}p2"
    else
        ESP="${DISK}1"; ROOT="${DISK}2"
    fi
    ok "alvo: $DISK  (ESP=$ESP  ROOT=$ROOT)"
}

ask_identity() {
    log "identidade da maquina"
    if [[ $AUTO == 1 ]]; then
        HOSTNAME="$HOSTNAME_DEFAULT"; USERNAME="$USERNAME_DEFAULT"
    else
        read -rp "Hostname [$HOSTNAME_DEFAULT]: " HOSTNAME
        HOSTNAME="${HOSTNAME:-$HOSTNAME_DEFAULT}"
        read -rp "Usuario [$USERNAME_DEFAULT]: " USERNAME
        USERNAME="${USERNAME:-$USERNAME_DEFAULT}"
    fi

    if [[ -n $PASSWORD_HASH ]]; then
        [[ $PASSWORD_HASH == \$* ]] || die "PASSWORD_HASH nao parece um hash (gere com: openssl passwd -6)"
        USER_PASSWORD=""; ROOT_PASSWORD=""
        ok "usuario $USERNAME em $HOSTNAME, senha pelo hash (root com a mesma)"
        return 0
    fi

    local p1 p2
    while true; do
        read -rsp "Senha de $USERNAME: " p1; printf '\n'
        read -rsp "Confirme a senha: " p2; printf '\n'
        [[ -n $p1 ]] || { warn "senha vazia nao serve"; continue; }
        [[ $p1 == "$p2" ]] && break
        warn "as senhas nao batem"
    done
    USER_PASSWORD="$p1"

    if [[ $AUTO == 1 ]]; then
        p1="$USER_PASSWORD"
    else
        while true; do
            read -rsp "Senha do root: " p1; printf '\n'
            read -rsp "Confirme a senha do root: " p2; printf '\n'
            [[ -n $p1 ]] || { warn "senha vazia nao serve"; continue; }
            [[ $p1 == "$p2" ]] && break
            warn "as senhas nao batem"
        done
    fi
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

    # ef00 = EFI System. A root usa o GUID da Discoverable Partition Specification
    # (root-x86-64) em vez do generico 8300: com ele o systemd acha a raiz sozinho
    # se o root= sumir da linha de comando do kernel.
    sgdisk -n 1:0:+"$ESP_SIZE" -t 1:ef00 -c 1:"EFI" "$DISK" >/dev/null
    sgdisk -n 2:0:0 -t 2:4f68bce3-e8cd-4db1-96e7-fbcaf984b709 -c 2:"ROOT" "$DISK" >/dev/null
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
    local opts="noatime,compress=zstd:3"
    mount -o "$opts,subvol=@" "$ROOT" /mnt
    mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot}
    mount -o "$opts,subvol=@home"      "$ROOT" /mnt/home
    mount -o "$opts,subvol=@log"       "$ROOT" /mnt/var/log
    mount -o "$opts,subvol=@pkg"       "$ROOT" /mnt/var/cache/pacman/pkg
    mount -o "$opts,subvol=@snapshots" "$ROOT" /mnt/.snapshots
    mount -o fmask=0077,dmask=0077 "$ESP" /mnt/boot
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

useradd -m -G wheel,audio,video,storage,input -s /bin/zsh "$USERNAME"
if [ -n "\${PW_HASH:-}" ]; then
    # hash SHA-512 vindo do pendrive (openssl passwd -6); -e = ja criptografado
    printf 'root:%s\n' "\$PW_HASH" | chpasswd -e
    printf '%s:%s\n' "$USERNAME" "\$PW_HASH" | chpasswd -e
else
    printf 'root:%s\n' "\$PW_ROOT" | chpasswd
    printf '%s:%s\n' "$USERNAME" "\$PW_USER" | chpasswd
fi
# wheel sem senha no sudo: pedido do dono da maquina (desktop de uma pessoa so).
printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

# Mesma armadilha do live ISO: o pacman 6.1 entrega ParallelDownloads ATIVO,
# entao um sed ancorado em ^# nao casa e o ajuste some sem avisar. O chroot roda
# como script separado, por isso a funcao vai duplicada aqui.
set_pacman_option() {
    local key="\$1" value="\$2" file=/etc/pacman.conf
    if grep -qE "^[[:space:]]*#?[[:space:]]*\${key}[[:space:]]*=" "\$file"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*\${key}[[:space:]]*=.*|\${key} = \${value}|" "\$file"
    elif grep -qE "^[[:space:]]*#?[[:space:]]*\${key}[[:space:]]*\$" "\$file"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*\${key}[[:space:]]*\$|\${key} = \${value}|" "\$file"
    else
        sed -i "/^\[options\]/a \${key} = \${value}" "\$file"
    fi
}

set_pacman_option ParallelDownloads 10
grep -qE '^[[:space:]]*Color[[:space:]]*$' /etc/pacman.conf || sed -i 's/^[[:space:]]*#[[:space:]]*Color[[:space:]]*$/Color/' /etc/pacman.conf
grep -qE '^[[:space:]]*Color[[:space:]]*$' /etc/pacman.conf || sed -i '/^\[options\]/a Color' /etc/pacman.conf
grep -qE '^\[multilib\]' /etc/pacman.conf || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
pacman -Sy --noconfirm >/dev/null

systemctl enable NetworkManager.service
systemctl enable systemd-timesyncd.service
systemctl enable fstrim.timer
systemctl enable paccache.timer

# Sem particao de swap: zram cobre o pico de memoria sem gastar disco.
cat > /etc/systemd/zram-generator.conf <<ZRAM
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
ZRAM

cat > /etc/sysctl.d/99-zram.conf <<SYSCTL
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
SYSCTL

# Snapper no subvolume @snapshots. O create-config quer criar /.snapshots ele
# mesmo e falha porque o subvolume ja existe montado, entao a ordem e:
# desmontar, apagar, deixar o snapper criar o dele, apagar esse, e remontar o
# nosso por cima. --no-dbus porque dentro do chroot nao ha barramento.
umount /.snapshots
rm -rf /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount /.snapshots
chmod 750 /.snapshots
chown :"$USERNAME" /.snapshots

# TIMELINE_CREATE=no porque quem dispara snapshot aqui e o snap-pac, antes e
# depois de cada transacao do pacman. Snapshot por hora em desktop so enche disco.
snapper --no-dbus -c root set-config     TIMELINE_CREATE=no     NUMBER_CLEANUP=yes     NUMBER_MIN_AGE=1800     NUMBER_LIMIT=15     NUMBER_LIMIT_IMPORTANT=8     ALLOW_USERS="$USERNAME"     SYNC_ACL=yes

systemctl enable snapper-cleanup.timer

# O preset do pacote linux nem sempre traz o 'fallback' ligado. Quando nao traz,
# o mkinitcpio -P gera so o initramfs normal, e a entrada de recuperacao do
# systemd-boot fica apontando pra uma imagem que nunca existiu: o menu mostra
# "Arch Linux (fallback)" e escolher nao boota. Ligar no PRESET, e nao gerar a
# imagem na mao, e o que mantem ela viva: o hook do pacman roda mkinitcpio -P a
# cada update de kernel.
PRESET=/etc/mkinitcpio.d/linux.preset
if [ -f "\$PRESET" ]; then
    sed -i "s|^#[[:space:]]*\(fallback_image=\)|\1|" "\$PRESET"
    sed -i "s|^#[[:space:]]*\(fallback_options=\)|\1|" "\$PRESET"
    grep -q "^fallback_image=" "\$PRESET" \
        || printf 'fallback_image="/boot/initramfs-linux-fallback.img"\n' >> "\$PRESET"
    grep -q "^fallback_options=" "\$PRESET" \
        || printf 'fallback_options="-S autodetect"\n' >> "\$PRESET"
    grep -qE "^PRESETS=.*fallback" "\$PRESET" \
        || sed -i "s|^PRESETS=.*|PRESETS=('default' 'fallback')|" "\$PRESET"
fi

# Gerar as imagens ANTES de escrever as entradas: assim da pra so escrever a
# entrada de fallback se a imagem dela realmente saiu.
mkinitcpio -P

bootctl install

# O bootctl grava a entrada "Linux Boot Manager" na NVRAM, mas nem sempre
# consegue: firmware que recusa escrita, efivarfs em somente-leitura, ou
# execucao dentro de chroot. Quando falha ele NAO reclama, e a maquina passa a
# depender do caminho removivel do ESP, que outro sistema operacional ou um
# update de firmware pode sobrescrever. Conferir, e criar na mao se faltar.
if efibootmgr 2>/dev/null | grep -qi 'Linux Boot Manager'; then
    echo 'entrada de boot ja registrada na NVRAM'
elif efibootmgr --create --disk "$DISK" --part 1 --unicode --loader '\EFI\systemd\systemd-bootx64.efi' --label 'Linux Boot Manager' >/dev/null 2>&1; then
    echo 'entrada de boot criada na NVRAM pelo efibootmgr'
else
    echo 'AVISO: nao registrei a entrada de boot na NVRAM' >&2
    echo 'AVISO: a maquina vai bootar pelo caminho removivel do ESP' >&2
fi

systemctl enable systemd-boot-update.service

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

if [ -f /boot/initramfs-linux-fallback.img ]; then
    cat > /boot/loader/entries/arch-fallback.conf <<ENTRY
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /initramfs-linux-fallback.img
options root=UUID=\$ROOT_UUID rootflags=subvol=@ ${KERNEL_PARAMS[*]}
ENTRY
else
    printf 'AVISO: sem initramfs de fallback, a entrada de recuperacao nao foi criada\n' >&2
fi
CHROOT

    chmod +x "$script"
    # Senhas entram por variavel de ambiente, nunca pelo texto do script (o hash tem '$').
    arch-chroot /mnt env PW_HASH="$PASSWORD_HASH" PW_ROOT="$ROOT_PASSWORD" PW_USER="$USER_PASSWORD" /root/chroot-setup.sh
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

Isso instala o KDE Plasma, o driver nvidia-open-dkms, os pacotes e os
symlinks. Reinicie de novo no fim.
STEPS
    arch-chroot /mnt chown "$USERNAME:$USERNAME" "/home/$USERNAME/PROXIMOS-PASSOS.txt"
    ok "dotfiles clonados em /home/$USERNAME/.dotfiles"
}

stage_firstboot() {
    # So no modo automatico: no primeiro boot, antes de qualquer login, roda o
    # install.sh dos dotfiles no tty1 (KDE, NVIDIA se houver, pacotes, AUR) e
    # reinicia. Se falhar, se desliga e deixa o log; a maquina continua usavel.
    [[ $AUTO == 1 ]] || return 0
    log "agendando o install.sh dos dotfiles pro primeiro boot"

    cat > /mnt/usr/local/bin/myarch-firstboot <<FB
#!/usr/bin/env bash
# Gerado pelo myarch. Roda uma vez, no primeiro boot, e se apaga.
LOG=/var/log/myarch-firstboot.log
USERNAME="$USERNAME"
exec > >(tee -a "\$LOG") 2>&1
printf '\n\033[1;34m==>\033[0m myarch: primeiro boot, instalando o desktop dos dotfiles. Nao desligue.\n'
for i in \$(seq 1 60); do ping -c1 -W2 archlinux.org >/dev/null 2>&1 && break; sleep 2; done
if ! ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
    printf 'sem rede depois de 2 minutos; rode depois: cd ~/.dotfiles && ./install.sh\n'
    systemctl disable myarch-firstboot.service; exit 1
fi
if runuser -u "\$USERNAME" -- env HOME="/home/\$USERNAME" bash -lc 'cd ~/.dotfiles && { git pull -q --ff-only || true; } && ./install.sh'; then
    printf '\n\033[1;32m==>\033[0m dotfiles instalados. Reiniciando em 5 s.\n'
    rm -f "/home/\$USERNAME/PROXIMOS-PASSOS.txt"
    systemctl disable myarch-firstboot.service
    rm -f /etc/systemd/system/myarch-firstboot.service /usr/local/bin/myarch-firstboot
    sleep 5; systemctl reboot
else
    printf '\n\033[1;31merro:\033[0m install.sh dos dotfiles falhou. Log em %s. Rode de novo: cd ~/.dotfiles && ./install.sh\n' "\$LOG"
    systemctl disable myarch-firstboot.service
    sleep 20
fi
FB
    chmod 755 /mnt/usr/local/bin/myarch-firstboot

    cat > /mnt/etc/systemd/system/myarch-firstboot.service <<'UNIT'
[Unit]
Description=myarch: install.sh dos dotfiles no primeiro boot
After=network-online.target systemd-user-sessions.service getty@tty1.service
Wants=network-online.target
Conflicts=getty@tty1.service
ConditionPathExists=/usr/local/bin/myarch-firstboot

[Service]
Type=oneshot
ExecStart=/usr/local/bin/myarch-firstboot
StandardInput=tty-force
StandardOutput=journal+console
StandardError=journal+console
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT
    arch-chroot /mnt systemctl enable myarch-firstboot.service >/dev/null 2>&1
    ok "myarch-firstboot.service habilitado"
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

  Reinicie e tire o pendrive.
$( if [[ $AUTO == 1 ]]; then
     printf '  No primeiro boot o install.sh dos dotfiles roda sozinho no tty1\n  (KDE, NVIDIA, pacotes, AUR) e reinicia no SDDM. Nao desligue.'
   else
     printf '  Logue como %s e rode:  cd ~/.dotfiles && ./install.sh' "$USERNAME"
   fi )
================================================================
EOF
    printf '%s\n' "$END"
    if [[ $AUTO == 1 ]]; then
        printf '%s  reiniciando em 10 segundos. Qualquer tecla cancela o reboot.%s\n' "$YEL" "$END"
        read -rs -t 10 -n 1 _ || systemctl reboot
    fi
}

main() {
    banner
    preflight
    prepare_live
    load_conf
    pick_disk
    ask_identity
    wipe_disk
    make_filesystems
    mount_filesystems
    install_base
    configure_system
    stage_dotfiles
    stage_firstboot
    finish
}

main "$@"
