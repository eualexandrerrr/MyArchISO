# Testa a ISO do myarch em QEMU no Windows (TCG, sem Hyper-V): UEFI, disco virtio de 30 GB
# e um segundo disco pequeno rotulado "Ventoy" fazendo o papel do pendrive com myarch/myarch.conf.
#
#   .\archiso\test-qemu.ps1 -Iso C:\...\myarch-2026.09.05-x86_64.iso -Conf C:\...\ventoy.img
#   .\archiso\test-qemu.ps1 -NoCdrom          # segundo boot, direto do disco instalado
#
# Monitor QEMU em tcp 127.0.0.1:4445 (sendkey, screendump), serial em tcp 127.0.0.1:4446 (ver
# serial-bridge.py: com console=ttyS0 na linha do kernel da pra dirigir o live sem tela), VNC em :5902.
# A imagem "Ventoy": num Arch qualquer, `truncate -s 32M ventoy.img && mkfs.vfat -F32 -n Ventoy ventoy.img`,
# montar em loop e gravar myarch/myarch.conf dentro.
param(
  [string]$Iso = "",
  [string]$Disk = "$PSScriptRoot\out\arch-test.qcow2",
  [string]$Conf = "",
  [switch]$NoCdrom,
  [int]$Mem = 4,
  [int]$Cpus = 4,
  [int]$MonitorPort = 4445,
  [int]$SerialPort = 4446,
  [int]$VncDisplay = 2
)
$q = 'C:\Program Files\qemu\qemu-system-x86_64.exe'
$share = 'C:\Program Files\qemu\share'
$work = Split-Path $Disk
New-Item -ItemType Directory -Force $work | Out-Null
if (-not (Test-Path $Disk)) { & 'C:\Program Files\qemu\qemu-img.exe' create -f qcow2 $Disk 30G | Out-Null }
$vars = Join-Path $work 'ovmf-vars-test.fd'
if (-not (Test-Path $vars)) { Copy-Item "$share\edk2-i386-vars.fd" $vars }

$args = @(
  '-name','myarch-test','-machine','q35','-accel','tcg,thread=multi','-cpu','max','-smp',"$Cpus",'-m',"${Mem}G",
  '-drive',"if=pflash,format=raw,readonly=on,file=$share\edk2-x86_64-code.fd",
  '-drive',"if=pflash,format=raw,file=$vars",
  '-drive',"file=$Disk,if=virtio,format=qcow2",
  '-nic','user,model=virtio-net-pci,hostfwd=tcp::2223-:22',
  '-monitor',"tcp:127.0.0.1:$MonitorPort,server,nowait",
  '-vnc',"127.0.0.1:$VncDisplay",'-display','none','-vga','std',
  '-serial',"tcp:127.0.0.1:$SerialPort,server,nowait",
  '-rtc','base=localtime'
)
if ($Conf) { $args += @('-drive',"file=$Conf,if=virtio,format=raw") }
if (-not $NoCdrom) {
  if (-not $Iso) { throw "passe -Iso ou -NoCdrom" }
  $args += @('-drive',"file=$Iso,media=cdrom,if=ide"); $args += @('-boot','order=d')
}
$line = ($args | ForEach-Object { if ($_ -match '[ ,]' -and $_ -notmatch '^"') { '"' + $_ + '"' } else { $_ } }) -join ' '
$p = Start-Process -FilePath $q -ArgumentList $line -PassThru -WindowStyle Hidden `
  -RedirectStandardError "$work\qemu-test.err" -RedirectStandardOutput "$work\qemu-test.out"
"qemu pid $($p.Id)  monitor 127.0.0.1:$MonitorPort  serial 127.0.0.1:$SerialPort  vnc :$VncDisplay"
