<div align="center">

# myarch

**Instalador do Arch Linux**

Instala uma base limpa em UEFI + systemd-boot + btrfs com subvolumes, e já deixa
os [dotfiles](https://github.com/eualexandrerrr/dotfiles) clonados pro primeiro boot.

[![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat-square&logo=arch-linux&logoColor=white)](https://archlinux.org)
[![systemd-boot](https://img.shields.io/badge/systemd--boot-FF6600?style=flat-square&logo=linux&logoColor=white)](https://wiki.archlinux.org/title/Systemd-boot)
[![btrfs](https://img.shields.io/badge/btrfs-0A9BDC?style=flat-square&logo=linux&logoColor=white)](https://wiki.archlinux.org/title/Btrfs)

</div>

---

## O que ele faz

| Etapa | Detalhe |
|:--|:--|
| Checagem | Exige root, boot em UEFI e rede ativa |
| Ambiente live | `br-abnt2`, NTP, `reflector` nos mirrors BR/CL/US |
| Particionamento | GPT: ESP 1 GiB FAT32 + root no restante |
| Sistema de arquivos | btrfs com `@` `@home` `@log` `@pkg` `@snapshots`, `zstd:3`, `noatime` |
| Base | `pacstrap` com kernel, headers, firmware, microcode Intel e AMD |
| Localidade | `pt_BR.UTF-8`, `America/Sao_Paulo`, teclado ABNT2 no console e no X |
| Usuário | Cria o usuário no `wheel` com shell `zsh`, sudo liberado |
| Bootloader | `systemd-boot` com entrada normal e fallback |
| NVIDIA | Já grava `nvidia_drm.modeset=1` e `NVreg_PreserveVideoMemoryAllocations=1` |
| Dotfiles | Clona em `~/.dotfiles` pronto pra rodar |

## Uso

### 1. Pendrive

O pendrive é montado com [Ventoy](https://ventoy.net), que boota ISO como arquivo —
dá pra ter Arch e Windows no mesmo pendrive e trocar a ISO sem regravar nada.

```
PENDRIVE/
├── archlinux-2026.08.01-x86_64.iso
├── Win11_pt-BR.iso
└── myarch/
    ├── install.sh
    └── README.md
```

### 2. Boot

Desative o **Secure Boot** na BIOS, boote o pendrive e escolha a ISO do Arch no menu do Ventoy.

### 3. Rede

Cabo já funciona sozinho. No wifi:

```bash
iwctl
[iwd]# device list
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect NOME_DA_REDE
[iwd]# exit
```

### 4. Instalar

```bash
loadkeys br-abnt2
pacman -Sy git --noconfirm
git clone https://github.com/eualexandrerrr/myarch
cd myarch
./install.sh
```

Ou direto do pendrive do Ventoy, sem precisar de internet pra baixar o script:

```bash
mkdir -p /mnt/usb && mount /dev/disk/by-label/Ventoy /mnt/usb
cd /mnt/usb/myarch && ./install.sh
```

O script pergunta o disco de destino e **exige que você digite o caminho completo** pra
confirmar. Depois pergunta hostname, usuário e senhas. Fora isso, roda sozinho.

Para pular a pergunta do disco:

```bash
DISK=/dev/nvme0n1 ./install.sh
```

### 5. Depois do reboot

```bash
cd ~/.dotfiles
./install.sh
```

Aí sim entram Hyprland, Quickshell, `nvidia-open-dkms` e o rice inteiro.

## Padrões

Editáveis no topo do `install.sh`:

```bash
HOSTNAME_DEFAULT="ryzen"
USERNAME_DEFAULT="alexandre"
TIMEZONE="America/Sao_Paulo"
LOCALE="pt_BR.UTF-8"
KEYMAP="br-abnt2"
ESP_SIZE="1GiB"
SUBVOLUMES=(@ @home @log @pkg @snapshots)
```

## Decisões

- **systemd-boot em vez de GRUB** — em UEFI puro o GRUB é peso morto. Boot mais rápido e
  configuração é um arquivo de texto de 6 linhas.
- **btrfs com subvolumes** — habilita snapshot antes de update. `@pkg` fora do snapshot pra
  não versionar cache de pacote, `@log` separado pra log não entrar em rollback.
- **Sem criptografia por padrão** — desktop fixo. Para LUKS, o passo é entre `wipe_disk` e
  `make_filesystems`.
- **Microcode Intel e AMD juntos** — o pacote errado é ignorado no boot, e o mesmo pendrive
  serve pras duas máquinas.

## Avisos

- O script **apaga o disco escolhido por inteiro**. Ele pede confirmação digitada, mas
  confira o alvo com `lsblk` antes.
- Exige boot em UEFI. BIOS legada não é suportada.
- Secure Boot precisa estar desativado — `nvidia-open-dkms` não é assinado.

## Repositórios relacionados

- [eualexandrerrr/dotfiles](https://github.com/eualexandrerrr/dotfiles) — o rice que roda em cima desta base

<div align="center">
<sub>Branch <code>backup/legacy-2023</code> guarda o instalador antigo, de GRUB e i3.</sub>
</div>
