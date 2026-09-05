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
| Particionamento | GPT: ESP 1 GiB FAT32 + root no restante (tipo da root pelo GUID da Discoverable Partition Spec) |
| Sistema de arquivos | btrfs com `@` `@home` `@log` `@pkg` `@snapshots`, `zstd:3`, `noatime` |
| Base | `pacstrap` com kernel, headers, firmware, microcode Intel e AMD |
| Localidade | `pt_BR.UTF-8`, `America/Sao_Paulo`, teclado ABNT2 no console e no X |
| Usuário | Cria o usuário no `wheel` com shell `zsh`, sudo liberado |
| Bootloader | `systemd-boot` com entrada normal e fallback, `systemd-boot-update.service` habilitado, entrada de NVRAM conferida |
| Swap | Nenhuma partição: `zram-generator` com metade da RAM, teto de 8 GiB, `zstd` |
| Snapshots | `snapper` no `@snapshots` + `snap-pac`: snapshot antes e depois de cada transação do `pacman` |
| Cache | `paccache.timer` poda o `@pkg`, que fica fora do snapshot e cresceria pra sempre |
| NVIDIA | Já grava `nvidia_drm.modeset=1` e `NVreg_PreserveVideoMemoryAllocations=1` |
| Dotfiles | Clona em `~/.dotfiles` pronto pra rodar |

## Requisitos

| Item | Exigência | Por quê |
|:--|:--|:--|
| Firmware | **UEFI**, com CSM/Legacy desligado | O script recusa bootar em BIOS legada. Ele checa `/sys/firmware/efi/efivars` antes de tocar em qualquer disco |
| Secure Boot | **desligado** | A ISO do Arch não é assinada, e o `nvidia-open-dkms` também não |
| Disco de destino | mínimo 20 GB, recomendado 64 GB+ | 1 GiB vai pra ESP, o resto é btrfs. Só o sistema base já ocupa ~3 GB, e o `@pkg` guarda cache de pacote |
| Rede no live ISO | cabo | O `pacstrap` baixa cerca de 900 MB. A ISO própria não traz Wi-Fi |
| Pendrive | [Ventoy](https://ventoy.net) + ISO do Arch | Qualquer pendrive de 4 GB serve |
| Processador | x86-64 | Não há suporte a ARM aqui |

O script instala microcode da Intel **e** da AMD. O errado é ignorado no boot, então o mesmo
pendrive serve pras duas plataformas.

## Antes de apagar o disco

**O disco escolhido é apagado por inteiro.** Não existe modo "instalar ao lado": o script faz
`wipefs` e `sgdisk --zap-all` no dispositivo, e reparticiona do zero. Não há redimensionamento,
não há preservação de partição, não há dual boot no mesmo disco.

Antes de bootar o pendrive:

1. **Tire o que só existe naquele disco.** Repositório sem push, pasta que não está em backup,
   chave de SSH, arquivo de configuração de aplicativo. Vale rodar `git status` em cada
   projeto — trabalho não commitado não vai pro GitHub sozinho.
2. **Se havia Windows com BitLocker, salve a chave de recuperação primeiro.** Desligar o
   Secure Boot muda o que o TPM mede, e o Windows pode exigir os 48 dígitos no boot seguinte.
   Isso importa mesmo se o plano é apagar o Windows: se algo der errado no meio, você quer
   conseguir voltar. Pegue em `manage-bde -protectors -get C:` ou em
   `account.microsoft.com/devices/recoverykey`.
3. **Confira o backup no destino, não na origem.** Pasta sincronizada não é backup até o
   arquivo estar do outro lado. Abra o serviço no navegador e veja os arquivos lá.
4. **Anote qual disco é qual.** Em `lsblk`, confira modelo e tamanho. `/dev/nvme0n1` e
   `/dev/nvme1n1` trocam de número entre boots com mais frequência do que se imagina.

## BIOS: o que mexer

| Opção | Valor | Consequência de errar |
|:--|:--|:--|
| Secure Boot | **Disabled** | A ISO nem aparece no menu de boot |
| CSM / Legacy Boot | **Disabled** | O pendrive boota em modo legado e o script para no `preflight` |
| Boot Mode | **UEFI only** | Mesmo caso acima |
| Fast Boot | Desligar se o pendrive não aparecer | A firmware pula a inicialização do USB |
| SATA Mode | **AHCI** (não RAID / Intel RST) | O Linux não enxerga o disco |

Se a máquina tinha Windows e você vai manter algum outro sistema, desligue também o
**Início Rápido** do Windows: ele hiberna o NTFS, e montar isso do Linux corrompe.

## Instalação passo a passo

### 1. Preparar o pendrive

O pendrive é montado com [Ventoy](https://ventoy.net), que boota ISO como arquivo — dá pra
ter Arch e Windows no mesmo pendrive e trocar a ISO sem regravar nada.

```
PENDRIVE/
├── archlinux-2026.08.01-x86_64.iso
├── Win11_pt-BR.iso
└── myarch/
    ├── install.sh
    └── README.md
```

Baixe a ISO em [archlinux.org/download](https://archlinux.org/download/) e copie pra raiz do
pendrive. O Ventoy acha sozinho. Ou use a [ISO própria](#iso-própria) deste repo, que já vem
com o instalador dentro e o teclado certo; nesse caso os passos 3 e 4 se resumem a escolher
`1` no menu.

### 2. BIOS

Duas coisas, só:

- **UEFI ligado.** O script recusa bootar em BIOS legada, e recusa cedo, antes de tocar no disco.
- **Secure Boot desligado.** O `nvidia-open-dkms` não vem assinado.

### 3. Bootar e conectar

Escolha a ISO do Arch no menu do Ventoy. Cabo de rede já funciona sozinho. No wifi:

```bash
iwctl
[iwd]# device list
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect NOME_DA_REDE
[iwd]# exit
```

Confira antes de seguir — sem rede o script para logo no começo:

```bash
ping -c1 archlinux.org
```

### 4. Rodar o instalador

Direto do pendrive, sem baixar nada:

```bash
loadkeys br-abnt2
mkdir -p /mnt/usb && mount /dev/disk/by-label/Ventoy /mnt/usb
bash /mnt/usb/myarch/install.sh
```

Ou clonando, se preferir a versão mais nova:

```bash
loadkeys br-abnt2
pacman -Sy --noconfirm git
git clone https://github.com/eualexandrerrr/myarch
bash myarch/install.sh
```

### 5. O que ele vai perguntar

Ele lista os discos e pede o alvo. **Confira com calma:** o disco escolhido é apagado por
inteiro, e pra confirmar você tem que digitar o caminho completo, não `s` nem `y`.

```
Disco de destino (ex: /dev/nvme0n1): /dev/nvme0n1
Digite exatamente o caminho do disco para confirmar (/dev/nvme0n1): /dev/nvme0n1
Hostname [RRR]:
Usuario [alexandre]:
Senha de alexandre:
Senha do root:
```

Pra pular a primeira pergunta:

```bash
DISK=/dev/nvme0n1 bash install.sh
```

Daí em diante roda sozinho. O grosso do tempo é o `pacstrap` baixando cerca de 900 MB.

### 6. Depois do reboot

Tire o pendrive e logue como o usuário que você criou. O instalador já deixou os dotfiles
clonados e um `PROXIMOS-PASSOS.txt` no home:

```bash
cd ~/.dotfiles
./install.sh
```

É essa segunda etapa que instala o KDE Plasma, o driver `nvidia-open-dkms`, o
`claude-code` e o rice inteiro. Reinicie de novo no fim.

## Modo automático

```bash
AUTO=1 bash install.sh
```

Não pergunta nada. Serve pra reinstalar a mesma máquina sem digitar:

| o quê | de onde vem |
|:--|:--|
| Disco | o maior disco interno (não removível, não USB), fora o que carrega o live e o pendrive de configuração. Um só disco interno = ele |
| Hostname, usuário | `HOSTNAME_DEFAULT` e `USERNAME_DEFAULT` do topo do script (`RRR`, `alexandre`), ou `myarch.conf` |
| Senha | `PASSWORD_HASH` (usuário e root com a mesma). Sem hash, pergunta a senha uma vez |
| Aviso | mostra o disco e espera 10 segundos; qualquer tecla cancela |
| Depois | agenda `myarch-firstboot.service`: no primeiro boot roda `~/.dotfiles/install.sh` no tty1 e reinicia no SDDM |

O `myarch.conf` fica **fora do repositório**, na partição rotulada `Ventoy` do pendrive
(pasta `myarch/`), porque carrega o hash da senha:

```ini
HOSTNAME=RRR
USERNAME=alexandre
PASSWORD_HASH='$6$...'      # openssl passwd -6
```

O arquivo é lido com `grep`, não com `source`. `DISK=/dev/...` também é aceito ali, pra
forçar o alvo numa máquina com mais de um disco.

Duas decisões que vêm com o automático e valem pro modo manual também: `wheel` tem
`NOPASSWD` no sudo (desktop de uma pessoa só, pedido do dono), e root e usuário recebem a
mesma senha.

## Se algo der errado

| O que aparece | O que é | O que fazer |
|:--|:--|:--|
| `o sistema nao bootou em UEFI` | Ainda em BIOS legada | Ligar UEFI no setup da placa |
| `sem internet` | Sem rede no live ISO | Conectar com `iwctl`, ou usar cabo |
| `nao e um dispositivo de bloco` | Caminho do disco errado | Conferir com `lsblk` |
| `confirmacao nao bateu` | Você digitou diferente | Nada foi tocado no disco. Rodar de novo |
| `AVISO: nao registrei a entrada de boot na NVRAM` | A firmware recusou gravar | O sistema ainda boota, pelo caminho removível do ESP. Dá pra criar depois com `efibootmgr` |

O script só apaga disco depois de todas as checagens e da confirmação digitada. Se ele morrer
antes disso, seu disco está intacto.

Se travar no meio da instalação, é seguro simplesmente rodar de novo: ele reparticiona do
zero, não tenta aproveitar estado anterior.

## Rollback

O `snap-pac` tira um snapshot antes e outro depois de cada transação do `pacman`. Quando um
update quebra o sistema:

```bash
snapper list                 # acha o número do snapshot bom
sudo snapper rollback <N>    # marca o snapshot como novo padrão
reboot
```

O `systemd-boot` **não** lista snapshots no menu de boot — isso é coisa de `grub-btrfs`, que
só existe pro GRUB. Se o sistema nem chega a bootar, o caminho é o pendrive: bootar o live
ISO, montar o subvolume `@snapshots` e fazer o rollback de lá.

```bash
mount -o subvol=@snapshots /dev/nvme0n1p2 /mnt
```

## Padrões

Editáveis no topo do `install.sh`:

```bash
HOSTNAME_DEFAULT="RRR"
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
- **Sem criptografia** — desktop fixo, disco não sai da mesa. LUKS e Secure Boot ficam de
  fora de propósito: o `nvidia-open-dkms` não vem assinado, então Secure Boot arrastaria
  `sbctl` e UKI atrás.
- **`snapper` com `TIMELINE_CREATE=no`** — quem dispara snapshot é o `snap-pac`, antes e depois
  de cada transação do `pacman`. Snapshot de hora em hora num desktop só enche disco. O
  `create-config` precisa de uma dança (desmontar `/.snapshots`, deixar ele criar o dele,
  apagar, remontar o nosso) porque ele se recusa a trabalhar num subvolume que já existe.
- **zram em vez de partição ou arquivo de swap** — swap em disco só serve pra hibernar, e
  hibernar com a NVIDIA proprietária é fonte de dor. `vm.swappiness=180` é o valor certo pra
  swap comprimida em RAM; o 60 padrão assume disco lento.
- **ESP montada com `fmask=0077,dmask=0077`** — sem isso o `systemd` reclama que o arquivo de
  random seed fica legível por qualquer usuário, e o `genfstab` carimba a montagem frouxa no
  `fstab`.
- **Sem `ssd` nem `space_cache=v2` nas opções de montagem** — os dois são autodetectados ou já
  são padrão desde o btrfs-progs 5.15. Escrever à mão só envelhece o script.
- **Microcode Intel e AMD juntos** — o pacote errado é ignorado no boot, e o mesmo pendrive
  serve pras duas máquinas.
- **`mkinitcpio -P` antes de escrever as entradas do boot** — o preset do pacote `linux` nem
  sempre traz o `fallback` ligado. Sem conferir, a entrada "Arch Linux (fallback)" apareceria
  no menu apontando pra uma imagem que nunca foi gerada: só morde no dia em que você precisa
  dela. O `fallback` é ligado no preset, não gerado à mão, pra que o hook do `pacman` a
  regenere a cada update de kernel.
- **Opção do `pacman.conf` ajustada por função, não por `sed` ancorado em `^#`** — o pacman
  6.1 passou a entregar `ParallelDownloads` já ativo. Um `sed` que só casa a linha comentada
  deixou de ajustar qualquer coisa, e falhava calado.
- **Entrada de boot conferida depois do `bootctl install`** — quando a firmware recusa gravar
  na NVRAM, o `bootctl` não reclama, e a máquina passa a depender do caminho removível do
  ESP, que outro sistema operacional pode sobrescrever.

## Avisos

- O script **apaga o disco escolhido por inteiro**. Ele pede confirmação digitada, mas
  confira o alvo com `lsblk` antes. Não existe modo de instalar ao lado de outro sistema
  no mesmo disco: para dual boot, use um disco separado para cada sistema, e escolha
  qual bootar pelo menu da placa.
- Exige boot em UEFI. BIOS legada não é suportada.
- Secure Boot precisa estar desativado — `nvidia-open-dkms` não é assinado.

## ISO própria

A pasta `archiso/` é um perfil do [archiso](https://gitlab.archlinux.org/archlinux/archiso)
(cópia do `releng`, o mesmo que gera a ISO oficial) com o que muda pra esta máquina:

- teclado `br-abnt2`, `pt_BR.UTF-8` e fuso `America/Sao_Paulo` já no live, sem `loadkeys`;
- `install.sh` e este README embutidos em `/root/myarch/`, então não precisa montar o Ventoy
  nem ter internet pra achar o instalador;
- menu no tty1 depois do autologin (`myarch-menu`): `1` instala automático (ver [Modo
  automático](#modo-automático)), `2` instala perguntando, `3` baixa o instalador mais novo do
  GitHub, shell, desligar. Com `script=` na linha de boot o menu não aparece, igual ao releng;
- lista de pacotes enxuta (`archiso/packages.x86_64`, 40 pacotes): kernel, firmware, boot, rede
  (cabo e Wi-Fi), o que o `install.sh` chama e socorro básico (`ntfs-3g`, `exfatprogs`, `rsync`,
  `7zip`, `tmux`, `htop`, `nvme-cli`, `smartmontools`, `openssh`). Fora: Wi-Fi, PXE, clonezilla,
  VPN, modem, leitor de tela, guest tools de VirtualBox/VMware/Hyper-V, cloud-init, smartcard.

Gerar exige Arch com root e o pacote `archiso`; o jeito sem máquina Linux é o workflow
**build-iso** (Actions → build-iso → Run workflow), que roda num container `archlinux`,
leva uns 15 minutos e publica `myarch-<data>-x86_64.iso` mais o `.sha256` numa release
`iso-<data>`. Localmente:

```bash
sudo pacman -S archiso
sudo ./archiso/build.sh        # ISO em archiso/out/
```

O `build.sh` copia o `install.sh` da raiz pra dentro do perfil na hora do build (a cópia está
no `.gitignore`), então a ISO sempre carrega a versão do commit em que foi gerada. Os symlinks
do `airootfs` estão no git como symlink de verdade: não edite essa pasta pelo Windows sem
`core.symlinks=true`, senão eles viram arquivo de texto e o live quebra em silêncio.

Grava do mesmo jeito: copiar o `.iso` pro pendrive do Ventoy.

## Repositórios relacionados

- [eualexandrerrr/dotfiles](https://github.com/eualexandrerrr/dotfiles) — o rice que roda em cima desta base

<div align="center">
<sub>Branch <code>backup/legacy-2023</code> guarda o instalador antigo, de GRUB e i3.</sub>
</div>
