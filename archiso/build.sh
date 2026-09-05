#!/usr/bin/env bash
# Gera a ISO do myarch. Precisa de Arch (ou container archlinux) com root e o pacote archiso.
#
#   sudo ./archiso/build.sh            # ISO em archiso/out/
#   sudo ./archiso/build.sh -o /tmp/x  # outro destino
#
# O install.sh e o README da raiz do repo sao copiados pra dentro do live em /root/myarch/,
# entao a ISO carrega sempre a versao do commit em que foi gerada.

set -euo pipefail

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$aqui")"
out="$aqui/out"
work="${TMPDIR:-/tmp}/myarch-archiso-work"

while getopts 'o:w:' opt; do
    case "$opt" in
        o) out="$OPTARG" ;;
        w) work="$OPTARG" ;;
        *) exit 1 ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "rode como root (mkarchiso precisa)"; exit 1; }
command -v mkarchiso >/dev/null || { echo "instale o pacote archiso: pacman -S archiso"; exit 1; }

# Copia o instalador pra dentro do perfil. A pasta fica no .gitignore.
install -Dm755 "$repo/install.sh" "$aqui/airootfs/root/myarch/install.sh"
install -Dm644 "$repo/README.md"  "$aqui/airootfs/root/myarch/README.md"

# Data do ultimo commit deixa a ISO reproduzivel e o nome com a data certa.
if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$repo" log -1 --format=%ct)}"
fi

rm -rf "$work"
mkdir -p "$out"
mkarchiso -v -w "$work" -o "$out" "$aqui"
rm -rf "$work"

cd "$out"
for iso in myarch-*.iso; do
    sha256sum "$iso" > "$iso.sha256"
done
ls -la "$out"
