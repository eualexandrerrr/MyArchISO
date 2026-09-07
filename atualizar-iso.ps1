<#
  Gera a ISO no GitHub Actions, baixa, confere o sha256 e (se você quiser) instala no pendrive do
  Ventoy no lugar da anterior. É a ferramenta para quando a ISO precisar ser refeita -- o que,
  desde que o menu passou a baixar o install.sh do GitHub na hora, é raro: a ISO virou veículo de
  boot, e o que decide o que acontece com o disco mora no repositório.

  Quando vale refazer:
    - o menu (myarch-menu), o perfil archiso/ ou a lista de pacotes do live mudaram
    - o live está velho a ponto de o kernel dele não enxergar hardware novo
    - você quer instalar sem rede (aí a cópia embutida é a única que existe)

    .\atualizar-iso.ps1                      dispara o build, espera, baixa e confere
    .\atualizar-iso.ps1 -Pendrive E:         e ainda instala no pendrive, tirando a ISO antiga
    .\atualizar-iso.ps1 -SemBuild -Pendrive E:   não dispara nada: pega a última release publicada
    .\atualizar-iso.ps1 -Token ghp_xxx       token explícito (senão usa GH_TOKEN ou o `gh auth token`)

  O token só é usado para falar com a API. Ele não é gravado em lugar nenhum.
#>
[CmdletBinding()]
param(
    [string] $Pendrive,
    [switch] $SemBuild,
    [string] $Token,
    [string] $Destino = (Join-Path $env:TEMP 'myarch-iso'),
    [int]    $EsperaMax = 45          # minutos
)

$ErrorActionPreference = 'Stop'
$REPO = 'eualexandrerrr/MyArchISO'
$API  = "https://api.github.com/repos/$REPO"

function Passo($m) { Write-Host "  - $m" -ForegroundColor Gray }
function Ok($m)    { Write-Host "  ok $m" -ForegroundColor Green }
function Aviso($m) { Write-Host "  !! $m" -ForegroundColor Yellow }
function Etapa($m) { Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }

# --- token ------------------------------------------------------------------------------------
if (-not $Token) { $Token = $env:GH_TOKEN }
if (-not $Token -and (Get-Command gh -ErrorAction Ignore)) {
    $Token = (& gh auth token 2>$null | Select-Object -First 1)
}
if (-not $Token) {
    throw "sem token. Rode 'gh auth login', ou passe -Token, ou ponha em `$env:GH_TOKEN."
}
$cab = @{ Authorization = "Bearer $Token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }

# --- 1. build ---------------------------------------------------------------------------------
$run = $null
if (-not $SemBuild) {
    Etapa 'Disparando o build no GitHub Actions'
    $commit = (Invoke-RestMethod -Uri "$API/commits/main" -Headers $cab)
    Passo "commit do main: $($commit.sha.Substring(0,7)) $(($commit.commit.message -split "`n")[0])"

    # Se já houver uma rodada andando, acompanha ela em vez de empilhar outra: o workflow tem
    # concurrency com cancel-in-progress false, então disparar de novo só cria fila.
    $andando = (Invoke-RestMethod -Uri "$API/actions/workflows/build-iso.yml/runs?per_page=5" -Headers $cab).workflow_runs |
               Where-Object { $_.status -ne 'completed' } | Select-Object -First 1
    if ($andando) {
        Aviso "já há uma rodada em andamento ($($andando.id)); vou acompanhar essa em vez de disparar outra"
        $run = $andando
    } else {
        Invoke-RestMethod -Method Post -Uri "$API/actions/workflows/build-iso.yml/dispatches" -Headers $cab `
            -Body (@{ ref = 'main'; inputs = @{ publicar = 'true' } } | ConvertTo-Json) -ContentType 'application/json' | Out-Null
        Ok 'disparado'
        Start-Sleep -Seconds 8
        $run = (Invoke-RestMethod -Uri "$API/actions/workflows/build-iso.yml/runs?per_page=1" -Headers $cab).workflow_runs[0]
    }

    Etapa "Esperando o build (id $($run.id))"
    Passo $run.html_url
    $t0 = Get-Date
    while ($run.status -ne 'completed') {
        if (((Get-Date) - $t0).TotalMinutes -gt $EsperaMax) { throw "passou de $EsperaMax min; veja $($run.html_url)" }
        Start-Sleep -Seconds 30
        $run = Invoke-RestMethod -Uri "$API/actions/runs/$($run.id)" -Headers $cab
        Write-Host ("     {0} | {1:mm\:ss} decorridos" -f $run.status, ((Get-Date) - $t0)) -ForegroundColor DarkGray
    }
    if ($run.conclusion -ne 'success') { throw "o build terminou como '$($run.conclusion)'. Veja $($run.html_url)" }
    Ok "build concluído em $([int]((Get-Date) - $t0).TotalMinutes) min"
}

# --- 2. release e download --------------------------------------------------------------------
Etapa 'Baixando a ISO da release mais recente'
$rel = Invoke-RestMethod -Uri "$API/releases/latest" -Headers $cab
Passo "release $($rel.tag_name), publicada em $([datetime]$rel.published_at)"
$aIso = $rel.assets | Where-Object { $_.name -like 'myarch-*.iso' }     | Select-Object -First 1
$aSha = $rel.assets | Where-Object { $_.name -like 'myarch-*.iso.sha256' } | Select-Object -First 1
if (-not $aIso) { throw "a release $($rel.tag_name) não tem um myarch-*.iso" }

New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$iso = Join-Path $Destino $aIso.name
Passo ("{0}: {1:n0} MB" -f $aIso.name, ($aIso.size / 1MB))
if ((Test-Path $iso) -and ((Get-Item $iso).Length -eq $aIso.size)) {
    Ok 'já estava baixado com o tamanho certo; não baixo de novo'
} else {
    # Invoke-WebRequest sem barra de progresso é muito mais rápido para arquivo grande
    $antigo = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    $t = [Diagnostics.Stopwatch]::StartNew()
    # SEM o cabeçalho de token: a URL do asset redireciona para o armazenamento de objetos, o
    # PowerShell reenvia os cabeçalhos no redirecionamento e ele recusa com "only one auth
    # mechanism allowed". O repositório é público, então o download não precisa de token mesmo.
    Invoke-WebRequest -Uri $aIso.browser_download_url -OutFile $iso
    $ProgressPreference = $antigo
    Ok ("baixado em {0:n0}s ({1:n1} MB/s)" -f $t.Elapsed.TotalSeconds, (($aIso.size / 1MB) / $t.Elapsed.TotalSeconds))
}

# --- 3. sha256 --------------------------------------------------------------------------------
Etapa 'Conferindo o sha256'
if ($aSha) {
    $sha = Join-Path $Destino $aSha.name
    Invoke-WebRequest -Uri $aSha.browser_download_url -OutFile $sha   # sem token, mesmo motivo do .iso
    # formato do sha256sum: "<hash>  <arquivo>"
    $esperado = ((Get-Content $sha -Raw) -split '\s+')[0]
    $obtido = (Get-FileHash -Path $iso -Algorithm SHA256).Hash.ToLower()
    if ($obtido -ne $esperado.ToLower()) {
        throw "sha256 NÃO bate.`n  esperado: $esperado`n  obtido:   $obtido`nA ISO está corrompida; não grave."
    }
    Ok "sha256 confere: $obtido"
} else {
    Aviso 'a release não tem .sha256; seguindo sem conferir (não ideal)'
}

if (-not $Pendrive) {
    Etapa 'Pronto'
    Write-Host "  ISO em: $iso" -ForegroundColor Green
    Write-Host "  Para instalar no pendrive: .\atualizar-iso.ps1 -SemBuild -Pendrive E:" -ForegroundColor Gray
    return
}

# --- 4. pendrive ------------------------------------------------------------------------------
Etapa "Instalando no pendrive $Pendrive"
$raiz = $Pendrive.TrimEnd('\', ':') + ':\'
if (-not (Test-Path $raiz)) { throw "$raiz não existe" }
$vol = Get-Volume -DriveLetter $raiz[0] -ErrorAction Ignore
if ($vol.FileSystemLabel -ne 'Ventoy') { throw "$raiz tem rótulo '$($vol.FileSystemLabel)', esperava 'Ventoy'. Disco errado?" }
Passo "$raiz (Ventoy, $([int]($vol.SizeRemaining/1GB)) GB livres)"
if ($vol.SizeRemaining -lt $aIso.size) { throw "faltam $([int](($aIso.size - $vol.SizeRemaining)/1MB)) MB no pendrive" }

$antigas = @(Get-ChildItem -LiteralPath $raiz -Filter 'myarch-*.iso' -File -ErrorAction Ignore |
             Where-Object Name -ne $aIso.name)
Copy-Item -LiteralPath $iso -Destination (Join-Path $raiz $aIso.name) -Force
Ok "copiada: $($aIso.name)"

# ventoy.json: preserva tudo e troca só o menu_alias da nossa ISO. Mesma regra do pendrive.ps1 do
# MyWinISO -- o ventoy.json é do pendrive, não deste repositório, e tem entradas de outras ISOs.
$vj = Join-Path $raiz 'ventoy\ventoy.json'
if (Test-Path $vj) {
    Copy-Item $vj "$vj.bak" -Force
    $j = Get-Content $vj -Raw -Encoding UTF8 | ConvertFrom-Json
    $alias = 'Arch Linux  (MyArchISO)'
    if ($j.PSObject.Properties['menu_alias']) {
        $nossa = $j.menu_alias | Where-Object { $_.image -like '/myarch-*.iso' } | Select-Object -First 1
        if ($nossa) { $alias = $nossa.alias }
        $j.menu_alias = @($j.menu_alias | Where-Object { $_.image -notlike '/myarch-*.iso' }) +
                        @([pscustomobject]@{ image = "/$($aIso.name)"; alias = $alias })
    } else {
        $j | Add-Member -NotePropertyName 'menu_alias' -NotePropertyValue @([pscustomobject]@{ image = "/$($aIso.name)"; alias = $alias })
    }
    $j | ConvertTo-Json -Depth 10 | Set-Content $vj -Encoding UTF8
    Ok "ventoy.json: menu_alias -> /$($aIso.name)  (cópia em ventoy.json.bak)"
} else {
    Aviso "não achei $vj; o menu do Ventoy vai mostrar o nome do arquivo"
}

# A ISO antiga sai por último, e só depois de a nova estar no lugar: enquanto ela estiver no
# pendrive, é uma opção a mais no menu -- e uma ISO velha traz um myarch-menu velho, que roda o
# instalador embutido dela em vez de baixar o novo.
foreach ($a in $antigas) {
    Remove-Item -LiteralPath $a.FullName -Force
    Ok "ISO antiga removida: $($a.Name)"
}

# o install.sh solto do pendrive (usado quando se roda à mão) também acompanha
$sh = Join-Path $raiz 'myarch\install.sh'
if (Test-Path (Join-Path $PSScriptRoot 'install.sh')) {
    New-Item -ItemType Directory -Path (Split-Path $sh -Parent) -Force | Out-Null
    # LF, sempre: o bash não lê CRLF
    $txt = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'install.sh')) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($sh, $txt, [Text.UTF8Encoding]::new($false))
    Ok "myarch\install.sh do pendrive atualizado ($((Get-Item $sh).Length) bytes)"
}

Etapa 'Pronto'
Write-Host "  $($aIso.name) no pendrive, sha256 conferido, ISO antiga removida." -ForegroundColor Green
