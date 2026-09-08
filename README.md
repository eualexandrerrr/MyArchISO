<div align="center">

# myarch

**Instalador do Arch Linux**

Instala uma base limpa em UEFI + systemd-boot + ext4, e já deixa
os [dotfiles](https://github.com/eualexandrerrr/dotfiles) clonados pro primeiro boot.

[![Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat-square&logo=arch-linux&logoColor=white)](https://archlinux.org)
[![systemd-boot](https://img.shields.io/badge/systemd--boot-FF6600?style=flat-square&logo=linux&logoColor=white)](https://wiki.archlinux.org/title/Systemd-boot)
[![ext4](https://img.shields.io/badge/ext4-0A9BDC?style=flat-square&logo=linux&logoColor=white)](https://wiki.archlinux.org/title/Ext4)

</div>

---

## O que ele faz

| Etapa | Detalhe |
|:--|:--|
| Checagem | Exige root, boot em UEFI e rede ativa |
| Ambiente live | `br-abnt2`, NTP, `reflector` nos mirrors BR/CL/US |
| **Partições preservadas** | Rótulos de `KEEP_LABELS` **nunca** são tocados, estejam em que posição estiverem no disco. Veja [Duas partições](#duas-partições) |
| Particionamento | **Duas partições, só.** GPT: ESP 1 GiB FAT32 + root com teto de 100 GiB (`ROOT_MAX_GB`) + o resto do disco na partição de dados |
| Partição de dados | Rótulo `Files`, ext4, montada em **`/home`**: criada se não existir, **reaproveitada intacta** se existir. É ela que faz reinstalar o sistema não custar nada |
| Desempenho do ext4 | `fast_commit` (caminho curto do `fsync`), `-m 1` na root e `-m 0` nos dados, tabelas escritas no `mkfs` (`lazy_itable_init=0`) |
| Sistema de arquivos | ext4 com `noatime` (btrfs saiu em 09/2026, ver Decisões) |
| Base | `pacstrap` com `linux-zen` + headers, firmware, `amd-ucode` |
| Localidade | `pt_BR.UTF-8`, `America/Sao_Paulo`, teclado ABNT2 no console e no X |
| Usuário | Cria o usuário no `wheel` com shell `zsh`, sudo liberado |
| Bootloader | `systemd-boot` com entrada normal e fallback, `systemd-boot-update.service` habilitado, entrada de NVRAM conferida |
| Swap | Nenhuma partição: `zram-generator` com metade da RAM, teto de 8 GiB, `zstd` |
| Desempenho | `amd_pstate=active`, `transparent_hugepage=always`, `vm.max_map_count` da SteamOS, `DefaultLimitNOFILE` pra esync, `makepkg` com `-j$(nproc)`, `!debug` e `-march=native` |
| Mirrors | `reflector.timer` semanal: só Brasil, https, os 10 mais rápidos |
| Cache | `paccache.timer` poda o cache do `pacman` |
| NVIDIA | Já grava `nvidia_drm.modeset=1`, `nvidia_drm.fbdev=1`, `NVreg_PreserveVideoMemoryAllocations=1` e `NVreg_UsePageAttributeTable=1` |
| Dotfiles | Clona em `~/.dotfiles` pronto pra rodar |

## A máquina

O instalador é genérico, mas foi escrito e testado neste PC. Vale como referência do que
ele espera encontrar.

| Peça | Modelo |
|:--|:--|
| CPU | AMD Ryzen 7 5700X, 8c/16t, AM4, **sem vídeo integrado** |
| Placa-mãe | ASUS TUF Gaming B550M-PLUS (mATX, B550) — x16 Gen4 pela CPU, x16 Gen3 (em x4) pelo chipset, 2 M.2, LAN 2.5G |
| RAM | 32 GB DDR4 dual channel (4 slots, até 128 GB) |
| GPU do host | PCYes Radeon RX 550 4GB — `amdgpu`, é ela que desenha o KDE |
| GPU da VM | Gainward RTX 3090 24GB — presa no `vfio-pci`, passada pra VM Windows |
| SSD | Corsair MP700 ELITE 932 GB NVMe Gen4 |
| Fonte | 850 W 80 Plus Gold |
| Gabinete | PCYes Forcefield Mini Black Vulcan (mini tower, GPU até 310 mm) |
| Monitores | ASUS XG27ACS 2560x1440@180Hz (paisagem) + LG UltraGear 2560x1440 (em pé) |

**Duas GPUs de propósito.** O client do RedM não passa pelo anticheat em Wine, então o jogo
roda numa VM Windows com GPU real. Uma GPU passada por `vfio` some do host — por isso a
RX 550: é ela que mantém o Linux com tela enquanto a 3090 fica dedicada à VM. A 3090 tem
cooler de 2,7 slots e tampa o slot de baixo fisicamente, então a RX 550 sai por um riser
PCIe 3.0 x16 de 20 cm com plugue de 90°.

O `configure_nvidia()` do [dotfiles](https://github.com/eualexandrerrr/dotfiles) e o
`kernel-nvidia` do `packages.txt` valem enquanto a 3090 ainda desenha o host; quando ela
for pro `vfio-pci`, saem os dois e entra o bind por ID (`10de:2204,10de:1aef`).

## Requisitos

| Item | Exigência | Por quê |
|:--|:--|:--|
| Firmware | **UEFI**, com CSM/Legacy desligado | O script recusa bootar em BIOS legada. Ele checa `/sys/firmware/efi/efivars` antes de tocar em qualquer disco |
| Secure Boot | **desligado** | A ISO do Arch não é assinada, e o `nvidia-open-dkms` também não |
| Disco de destino | mínimo 20 GB, recomendado 64 GB+ | 1 GiB vai pra ESP, o resto é ext4. Só o sistema base já ocupa ~3 GB, e o `@pkg` guarda cache de pacote |
| Rede no live ISO | cabo | O `pacstrap` baixa cerca de 900 MB. A ISO própria não traz Wi-Fi |
| Pendrive | [Ventoy](https://ventoy.net) + ISO do Arch | Qualquer pendrive de 4 GB serve |
| Processador | x86-64 | Não há suporte a ARM aqui |

O script instala microcode da Intel **e** da AMD. O errado é ignorado no boot, então o mesmo
pendrive serve pras duas plataformas.

## Duas partições

O disco tem **duas partições e mais nada** (a ESP não conta: 1 GiB, sem letra, invisível):

| | Rótulo | Tamanho | Sistema de arquivos | Montagem | Papel |
|:--|:--|:--|:--|:--|:--|
| sistema | `ROOT` | **100 GiB** (`ROOT_MAX_GB`) | ext4 | `/` | descartável: some a cada reinstalação |
| dados | `Files` | todo o resto | ext4 | **`/home`** | sagrada: **nunca formatada** se já existir |

**Rótulo é sagrado, posição não importa.** O instalador apaga tudo no disco **menos** as partições
cujo rótulo (de sistema de arquivos ou de partição GPT) esteja em `KEEP_LABELS`:

```bash
KEEP_LABELS="Files Alexandre HOME"     # "Alexandre" e "HOME" são nomes antigos, mantidos por segurança
```

Isso é o que torna o sistema descartável de verdade: a root é a única coisa que se perde ao
reinstalar, e ela não guarda nada seu — `~/.config`, `~/.claude`, `~/.dotfiles`, projetos,
biblioteca da Steam e imagem de VM ficam do lado de fora. **É o mesmo contrato do
[MyWinISO](https://github.com/eualexandrerrr/MyWinISO)**, que protege os mesmos rótulos.

### Por que ext4 e não NTFS na partição de dados

Ela é o `/home`. NTFS não serve de `/home`: o `ntfs3` do kernel não cria symlink POSIX, não guarda
dono nem bit de execução. Os `dotfiles` fazem `ln -sfn` de tudo e morreriam na primeira linha, e
todo repositório git apareceria com os arquivos modificados. Não é "pior", é quebrado.

Uma partição de dados NTFS **legada** continua sendo reconhecida e preservada, mas vai para
`/mnt/dados` como área compartilhada — não vira `/home`, e o instalador avisa por quê.

Com `/home` preservada o usuário é recriado com o **mesmo UID e GID de antes**, lidos da própria
pasta: dono no ext4 é um número, não um nome, e UID diferente deixaria o home inteiro parecendo de
outra pessoa.

Para ignorar a proteção e apagar o disco inteiro — disco novo, ou recomeço mesmo:

```bash
WIPE_ALL=1 bash install.sh
```

O modo automático **recusa** `WIPE_ALL`, e também recusa um disco que já tenha partições mas nenhuma
protegida: ninguém está olhando a tela no modo automático, e dez segundos não são aviso suficiente
para destruir dados.

## Antes de instalar

**O que não estiver protegido por rótulo é apagado.** Não existe redimensionamento: o instalador só
cria partição em espaço já livre. Se você quer uma área de dados menor para abrir espaço, encolha-a
**antes**, pelo sistema que já está instalado (o Gerenciamento de Disco do Windows faz isso no NTFS
sem risco), e deixe o espaço livre esperando.

Antes de bootar o pendrive:

1. **Tire o que só existe naquele disco e fora das partições protegidas.** Repositório sem push,
   pasta que não está em backup, chave de SSH, arquivo de configuração de aplicativo. Vale rodar
   `git status` em cada projeto — trabalho não commitado não vai pro GitHub sozinho. O que estiver
   na `HOME` ou na `Files` fica; o resto do disco, não.
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
git clone https://github.com/eualexandrerrr/MyArchISO
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
| Disco | o maior disco interno (não removível, não USB), fora o que carrega o live e o pendrive de configuração. Um só disco interno = ele. **Se o disco já tiver partições e nenhuma protegida, ele para** em vez de apagar |
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

## Se o desktop não subir

A opção **4** do menu do live reinstala só os dotfiles, sem tocar em partição nenhuma: monta a
ROOT, põe a partição de dados em `/home`, faz `arch-chroot`, apaga `~/.dotfiles`, clona do
GitHub, roda o `install.sh` do repo de dotfiles como o dono do `/home` e reinicia.

Ela existe porque a configuração do desktop mora em `/home`, que sobrevive à formatação.
Reinstalar o Arch inteiro não conserta um compositor que não sobe — o `~/.config` volta igual.
Antes disso a única saída era montar tudo à mão pelo shell.

Precisa de rede: os dotfiles vêm do GitHub, não da ISO. O reinício é automático depois de 10 s,
com `[esc]` para cancelar.

## Se um update quebrar

Sem snapshot: o caminho é o pendrive. Bootar o live, montar a root e arrumar de lá
(`arch-chroot /mnt`, `pacman -U /var/cache/pacman/pkg/<pacote-anterior>`).

```bash
mount /dev/nvme0n1p2 /mnt && mount /dev/nvme0n1p1 /mnt/boot && arch-chroot /mnt
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
```

## Decisões

- **systemd-boot em vez de GRUB** — em UEFI puro o GRUB é peso morto. Boot mais rápido e
  configuração é um arquivo de texto de 6 linhas.
- **ext4 em vez de btrfs** (09/2026) — decisão do dono, por desempenho: sem CoW, sem
  compressão, sem checksum de dados, menos trabalho por escrita em jogo e compilação. O preço
  é não ter snapshot nem rollback; a versão com btrfs + `snapper` + `snap-pac` fica no
  histórico do git (`git log --before=2026-09-06`).
- **Sem criptografia** — desktop fixo, disco não sai da mesa. LUKS e Secure Boot ficam de
  fora de propósito: o `nvidia-open-dkms` não vem assinado, então Secure Boot arrastaria
  `sbctl` e UKI atrás.
- **zram em vez de partição ou arquivo de swap** — swap em disco só serve pra hibernar, e
  hibernar com a NVIDIA proprietária é fonte de dor. `vm.swappiness=180` é o valor certo pra
  swap comprimida em RAM; o 60 padrão assume disco lento.
- **ESP montada com `fmask=0077,dmask=0077`** — sem isso o `systemd` reclama que o arquivo de
  random seed fica legível por qualquer usuário, e o `genfstab` carimba a montagem frouxa no
  `fstab`.
- **`linux-zen` e só `amd-ucode`** (09/2026) — máquina de jogo com Ryzen: o zen traz scheduler
  e timers voltados a desktop; `intel-ucode` era peso morto. Pra outra máquina, trocar as duas
  linhas em `BASE_PACKAGES` e nas entradas do `systemd-boot`.
- **Ajustes de desempenho no chroot, não nos dotfiles** — `sysctl`, limites do systemd,
  `makepkg.conf.d` e `reflector.conf` são do sistema, então nascem com ele. O que é de sessão
  (perfil de energia, `ananicy-cpp`, modo da GPU) fica nos dotfiles.
- **Preservar por rótulo, e não por posição** (09/2026) — o instalador do Windows desta casa
  protegia "a última partição do disco". Basta criar uma partição depois dela para a regra
  apontar para a errada. Rótulo não muda de lugar quando o disco é reparticionado, número
  muda; por isso a proteção é por `KEEP_LABELS` e o número da partição é descoberto na hora.
- **Sistema no primeiro espaço livre, `/home` no maior** — escolher o maior buraco para a root
  parece natural e é errado: num disco onde o espaço grande está no fim, a root nascia lá e
  não sobrava lugar para a `/home` separada. Medido em teste com disco de mentira antes de
  encostar em disco de verdade.
- **`/home` em partição própria em vez de junções** — no Windows a área persistente é feita
  de junções de `%APPDATA%` para outro disco, com tarefa agendada consertando o que estava em
  uso. No Linux nada disso é preciso: `/home` numa partição que o instalador não formata
  resolve o mesmo problema sem nenhuma peça móvel.
- **Duas partições, e a de dados é ext4** (09/2026) — decisão do dono. O Windows passa a viver
  só em VM com passthrough, e VM não lê partição: recebe pasta compartilhada e vê letra de
  unidade. Sem ninguém precisando ler o disco pelo Windows, não há mais motivo para o NTFS
  atrapalhar o `/home`.
- **`-m 0` na partição de dados** — a reserva de 5% do ext4 existe para o root ainda conseguir
  logar num disco cheio; isso só faz sentido na raiz do sistema. Em 690 GiB de dados seriam
  34 GiB parados sem servir a nada. Na root fica 1%, que já cumpre o papel em 100 GiB.
- **`fast_commit` nas duas** — encurta o caminho do `fsync`, que é o que mais aparece em imagem
  de VM, banco e compilação.
- **`lazy_itable_init=0` no `mkfs`** — escreve as tabelas na hora, em vez de deixar uma thread
  terminando em segundo plano nas primeiras horas de uso. Custa segundos na instalação e evita
  lentidão inexplicada logo depois dela.
- **`ntfs3` e não `ntfs-3g`** — o `ntfs3` é driver de kernel desde a 5.15; o `ntfs-3g` roda em
  espaço de usuário pelo FUSE e é bem mais lento. O pacote `ntfs-3g` continua instalado pelas
  ferramentas (`mkntfs`, `ntfsfix`), não pela montagem.
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

- O script **apaga tudo que não estiver protegido por rótulo** no disco escolhido. Ele pede
  confirmação digitada e lista o que vai preservar, mas confira o alvo com `lsblk` antes.
  Sistema ao lado de sistema no mesmo disco não existe aqui: a root é sempre recriada, então
  instalar o Arch remove o Windows que estivesse na frente do disco (e vice-versa) — o que
  sobrevive são os dados, não o outro sistema.
- Exige boot em UEFI. BIOS legada não é suportada.
- Secure Boot precisa estar desativado — `nvidia-open-dkms` não é assinado.

## O menu também se atualiza sozinho

Pelo mesmo motivo do instalador: a ISO congela o `myarch-menu` do commit em que foi gerada, e
uma opção nova só chegaria ao pendrive regerando a imagem. Ao abrir, ele baixa a própria versão
do GitHub, se troca e reexecuta uma vez. `MYARCH_MENU_ATUALIZADO` corta o laço.

Só troca se o arquivo baixado for um bash válido (shebang mais `bash -n`) e diferente do atual.
Um download pela metade sobrescreveria o menu por lixo e deixaria o live sem interface nenhuma.
Sem rede, segue com a versão da ISO sem reclamar.

Isso vale só para o menu. O `install.sh` continua com o próprio caminho de download e as
próprias checagens, descritas abaixo.

## O instalador vem do GitHub, não da ISO

**As opções 1 e 2 do menu baixam o `install.sh` do GitHub na hora.** A cópia dentro da ISO é o
plano B, para quando não há rede — e o menu diz de quando ela é.

É o mesmo desenho do [MyWinISO](https://github.com/eualexandrerrr/MyWinISO), onde o
`primeiro-logon.ps1` baixa o `setup.ps1` em vez de carregá-lo dentro do XML. O motivo: **a ISO
congela o instalador do commit em que foi gerada**, e uma ISO de duas semanas atrás instala o
sistema de duas semanas atrás. Isso quase custou caro aqui — a ISO de 05/09/2026 carrega a versão
que apagava o disco inteiro, sem preservar a partição de dados, e continuaria fazendo isso para
sempre. Buscar na hora faz a ISO envelhecer sem apodrecer.

O que é baixado passa por uma checagem antes de rodar (`protege_particao`): tem de ser um script
bash e tem de conter `KEEP_LABELS` e `particoes_protegidas`. **Um instalador que não sabe preservar
partição por rótulo não roda** — nem baixado, nem embutido. Sem rede e com uma ISO antiga, o menu
recusa e explica, em vez de apagar o disco:

```
PAREI. O instalador embutido nesta ISO (abc1234 de 05/09/2026) NAO sabe preservar particao
por rotulo: ele apagaria o disco inteiro, incluindo a particao de dados.
```

A mesma checagem barra uma página de portal de wi-fi cativo e um download que veio pela metade —
os dois casos em que "baixar da internet e executar" costuma dar errado.

## ISO própria

A pasta `archiso/` é um perfil do [archiso](https://gitlab.archlinux.org/archlinux/archiso)
(cópia do `releng`, o mesmo que gera a ISO oficial) com o que muda pra esta máquina:

- teclado `br-abnt2`, `pt_BR.UTF-8` e fuso `America/Sao_Paulo` já no live, sem `loadkeys`;
- `install.sh` e este README embutidos em `/root/myarch/`, então não precisa montar o Ventoy
  nem ter internet pra achar o instalador;
- menu no tty1 depois do autologin (`myarch-menu`): `1` instala automático (ver [Modo
  automático](#modo-automático)), `2` instala perguntando, `3` usa a cópia embutida sem baixar,
  shell, reiniciar, desligar. Com `script=` na linha de boot o menu não aparece, igual ao releng;
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
no `.gitignore`) e grava um `VERSAO` com o commit e a data — é ele que o menu mostra ao avisar que
está usando a cópia embutida. Essa cópia é só o plano B: com rede, o menu baixa a versão mais nova
(veja [O instalador vem do GitHub](#o-instalador-vem-do-github-não-da-iso)). Os symlinks
do `airootfs` estão no git como symlink de verdade: não edite essa pasta pelo Windows sem
`core.symlinks=true`, senão eles viram arquivo de texto e o live quebra em silêncio.

### Refazer a ISO: `atualizar-iso.ps1`

Do Windows, uma linha faz tudo — dispara o build, espera, baixa, **confere o `sha256`**, copia pro
pendrive, aponta o `menu_alias` do `ventoy.json` pra ISO nova, remove a antiga e atualiza o
`install.sh` solto do pendrive:

```powershell
.\atualizar-iso.ps1 -Pendrive E:
```

| Forma | O que faz |
|:--|:--|
| `.\atualizar-iso.ps1` | dispara o build, espera, baixa e confere. Não toca no pendrive |
| `.\atualizar-iso.ps1 -Pendrive E:` | o acima, e instala no pendrive |
| `.\atualizar-iso.ps1 -SemBuild -Pendrive E:` | não dispara nada: pega a última release já publicada |
| `-Token ghp_...` | token explícito; sem ele usa `$env:GH_TOKEN` ou o `gh auth token` |

Detalhes que o script cuida, e que são fáceis de esquecer fazendo à mão:

- **Se já houver um build rodando, ele acompanha aquele** em vez de empilhar outro — o workflow tem
  `concurrency` sem `cancel-in-progress`, então disparar duas vezes só cria fila.
- **Confere o `sha256` antes de gravar** e aborta se não bater.
- **Só apaga a ISO antiga depois que a nova está no lugar.** Enquanto a antiga estiver no pendrive
  ela é uma opção a mais no menu do Ventoy — e uma ISO velha carrega um `myarch-menu` velho, que
  roda o instalador embutido dela em vez de baixar o novo.
- **Preserva o resto do `ventoy.json`**, incluindo as entradas das outras ISOs e o tema; troca só o
  `menu_alias` da nossa, mantendo o texto que já estava lá. Mesma regra do `pendrive.ps1` do
  MyWinISO, porque o `ventoy.json` é do pendrive, não deste repositório.
- **Grava o `install.sh` do pendrive com LF**, que é o que o bash lê.
- O token só fala com a API; o download é sem ele (o repositório é público, e mandar o cabeçalho de
  autorização no redirecionamento para o armazenamento de objetos faz ele recusar).

### Quando vale refazer

Desde que o menu passou a baixar o `install.sh` do GitHub na hora, refazer a ISO virou raro — ela é
veículo de boot, e o que decide o que acontece com o disco mora no repositório. Vale quando:

- o `myarch-menu`, o perfil `archiso/` ou a lista de pacotes do live mudaram;
- o live está velho a ponto de o kernel não enxergar hardware novo;
- você quer instalar **sem rede** — aí a cópia embutida é a única que existe.

Grava do mesmo jeito: copiar o `.iso` pro pendrive do Ventoy.

Pra testar antes de gravar, `archiso/test-qemu.ps1` sobe a ISO num QEMU do Windows (TCG, sem
Hyper-V) com um disco virtio de 30 GB e um disco pequeno rotulado `Ventoy` fazendo o papel do
pendrive com `myarch/myarch.conf`; monitor em `127.0.0.1:4445` pra mandar teclas e capturar a
tela. Foi assim que o modo automático foi validado de ponta a ponta antes de formatar.

## Repositórios relacionados

- [eualexandrerrr/dotfiles](https://github.com/eualexandrerrr/dotfiles) — o rice que roda em cima desta base

<div align="center">
<sub>Branch <code>backup/legacy-2023</code> guarda o instalador antigo, de GRUB e i3.</sub>
</div>
