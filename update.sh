#!/usr/bin/env bash
# Encrypt the source page into index.html and commit it.
# Usage: ./update.sh [source.html] [--no-commit]
# Without a source argument, the path is read from ~/.config/hydro-viz/source.
set -euo pipefail

cd "$(dirname "$(realpath "$0")")"
REPO=$(pwd)
CONF="$HOME/.config/hydro-viz"
PASS_FILE="$CONF/passphrase"
STATICRYPT="staticrypt@3.5.4"

commit=1
src=""
for arg in "$@"; do
    case "$arg" in
        --no-commit) commit=0 ;;
        *) src="$arg" ;;
    esac
done
[[ -n "$src" ]] || src=$(<"$CONF/source")
src=$(realpath "$src")

[[ -f "$src" ]] || { echo "source not found: $src" >&2; exit 1; }
[[ "$src" != "$REPO"/* ]] || { echo "source must live outside the repo" >&2; exit 1; }
[[ -f "$PASS_FILE" ]] || { echo "missing $PASS_FILE" >&2; exit 1; }
[[ $(stat -c '%a' "$PASS_FILE") == 600 ]] || { echo "$PASS_FILE must be mode 600" >&2; exit 1; }

# Work in ~/.cache, because /tmp is a shared tmpfs.
mkdir -p "$HOME/.cache"
tmp=$(mktemp -d "$HOME/.cache/hydro-viz.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

STATICRYPT_PASSWORD=$(<"$PASS_FILE") npx --yes "$STATICRYPT" "$src" \
    --directory "$tmp" \
    --config .staticrypt.json \
    --remember false \
    --short \
    --template-title "Accès réservé" \
    --template-instructions "Page publiée par Bastien Boivin (Université de Rennes) pour les partenaires du projet. Saisissez le mot de passe qui vous a été communiqué." \
    --template-button "Ouvrir" \
    --template-placeholder "Mot de passe" \
    --template-error "Mot de passe incorrect" \
    --template-toggle-show "Afficher le mot de passe" \
    --template-toggle-hide "Masquer le mot de passe" \
    --template-color-primary "#2f5d8a" \
    --template-color-secondary "#eef1f5" \
    >/dev/null

out="$tmp/$(basename "$src")"
# French page, kept out of search engines.
sed -i -e 's/<html class="staticrypt-html">/<html class="staticrypt-html" lang="fr">/' \
       -e '0,/<head>/s//<head>\n    <meta name="robots" content="noindex, nofollow">/' "$out"

# Refuse anything that still looks like plaintext.
grep -q 'name="robots" content="noindex' "$out" || { echo "noindex meta missing" >&2; exit 1; }
grep -q 'staticrypt' "$out" || { echo "output is not a staticrypt page" >&2; exit 1; }
if grep -q 'plotly-graph-div' "$out"; then echo "plaintext found in output" >&2; exit 1; fi

mv "$out" index.html
echo "index.html encrypted ($(du -h index.html | cut -f1))"

if (( commit )); then
    git add -- index.html .staticrypt.json
    if git diff --cached --quiet -- index.html .staticrypt.json; then
        echo "nothing to commit"
    else
        git commit -q -m "chore: update page $(date +%F)" -- index.html .staticrypt.json
        echo "committed. Publish with: git push"
    fi
fi
