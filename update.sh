#!/usr/bin/env bash
# Encrypt the pages and the hub, then commit them.
# Usage: ./update.sh [page ...] [--no-commit]
# Pages are listed in ~/.config/hydro-viz/pages.tsv, one per line:
#   name<TAB>card title<TAB>card description<TAB>source path
# Names are p1, p2, ... Each page lands in <name>/index.html.
# Without page arguments, every page is encrypted. The hub index.html is always rebuilt.
set -euo pipefail

cd "$(dirname "$(realpath "$0")")"
REPO=$(pwd)
CONF="$HOME/.config/hydro-viz"
PASS_FILE="$CONF/passphrase"
PAGES_FILE="$CONF/pages.tsv"
STATICRYPT="staticrypt@3.5.4"
# Marker placed in every plaintext we inject into. It must never reach the repo.
GUARD="hv-plain-guard"

commit=1
wanted=()
for arg in "$@"; do
    case "$arg" in
        --no-commit) commit=0 ;;
        *) wanted+=("$arg") ;;
    esac
done

[[ -f "$PASS_FILE" ]] || { echo "missing $PASS_FILE" >&2; exit 1; }
[[ $(stat -c '%a' "$PASS_FILE") == 600 ]] || { echo "$PASS_FILE must be mode 600" >&2; exit 1; }
[[ -f "$PAGES_FILE" ]] || { echo "missing $PAGES_FILE" >&2; exit 1; }

names=() titles=() descs=() srcs=()
while IFS=$'\t' read -r name title desc src; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    [[ "$name" =~ ^p[0-9]+$ ]] || { echo "bad page name: $name" >&2; exit 1; }
    names+=("$name") titles+=("$title") descs+=("$desc") srcs+=("$src")
done < "$PAGES_FILE"
(( ${#names[@]} )) || { echo "no page in $PAGES_FILE" >&2; exit 1; }
(( ${#wanted[@]} )) || wanted=("${names[@]}")

# Work in ~/.cache, because /tmp is a shared tmpfs.
mkdir -p "$HOME/.cache"
tmp=$(mktemp -d "$HOME/.cache/hydro-viz.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

run_staticrypt() {
    STATICRYPT_PASSWORD=$(<"$PASS_FILE") npx --yes "$STATICRYPT" "$@" \
        --config .staticrypt.json --remember false --short
}

# Hashed password, kept in memory and only written inside plaintext.
hash=$(run_staticrypt --share "" | sed -n 's/^#staticrypt_pwd=//p')
[[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo "could not compute share hash" >&2; exit 1; }

# Links marked data-hv hand the key to the next page through sessionStorage.
# template.html reads it once and deletes it, so the key never shows in a URL or in history.
HANDOFF="<script id=\"$GUARD\">document.addEventListener('click', function (e) { var a = e.target.closest('a[data-hv]'); if (a && e.button === 0 && !e.ctrlKey && !e.metaKey && !e.shiftKey) { try { sessionStorage.setItem('hv_key', '$hash'); } catch (_) {} } });</script>"

esc() {
    local s=${1//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    printf '%s' "${s//\"/&quot;}"
}

# encrypt <plaintext copy> <output path>
encrypt() {
    local plain=$1 dest=$2 out
    mkdir -p "$tmp/out"
    run_staticrypt "$plain" \
        --directory "$tmp/out" \
        --template template.html \
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
    out="$tmp/out/$(basename "$plain")"
    # French page, kept out of search engines.
    sed -i -e 's/<html class="staticrypt-html">/<html class="staticrypt-html" lang="fr">/' \
           -e '0,/<head>/s//<head>\n    <meta name="robots" content="noindex, nofollow">/' "$out"
    # Refuse anything that still looks like plaintext.
    grep -q 'name="robots" content="noindex' "$out" || { echo "noindex meta missing" >&2; exit 1; }
    grep -q 'class="staticrypt-html"' "$out" || { echo "output is not a staticrypt page" >&2; exit 1; }
    if grep -q -e "$GUARD" -e 'plotly-graph-div' -e "$hash" "$out"; then
        echo "plaintext found in output" >&2; exit 1
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$out" "$dest"
    echo "$dest encrypted ($(du -h "$dest" | cut -f1))"
}

# Pages: hand-off script in head, link back to the hub at the top of body.
for w in "${wanted[@]}"; do
    i=-1
    for k in "${!names[@]}"; do [[ "${names[$k]}" == "$w" ]] && i=$k; done
    (( i >= 0 )) || { echo "unknown page: $w" >&2; exit 1; }
    src=$(realpath "${srcs[$i]/#\~/$HOME}")
    [[ -f "$src" ]] || { echo "source not found for $w" >&2; exit 1; }
    [[ "$src" != "$REPO"/* ]] || { echo "source must live outside the repo" >&2; exit 1; }
    plain="$tmp/$w.html"
    back="<p style=\"font-family: Arial, Helvetica, sans-serif; font-size: 13px;\"><a data-hv href=\"../\">← Retour à la liste des pages</a></p>"
    # Escape & for the sed replacement.
    sed -e "0,/<head[^>]*>/s||&\n${HANDOFF//&/\\&}|" -e "0,/<body[^>]*>/s||&\n$back|" "$src" > "$plain"
    grep -q "$GUARD" "$plain" || { echo "no <head> in source for $w" >&2; exit 1; }
    encrypt "$plain" "$w/index.html"
done

# Hub: one card per listed page.
cards=""
for k in "${!names[@]}"; do
    cards+="<a class=\"card\" data-hv href=\"${names[$k]}/\"><h2>$(esc "${titles[$k]}")</h2><p>$(esc "${descs[$k]}")</p></a>"$'\n'
done
cat > "$tmp/hub.html" <<HTML
<!DOCTYPE html>
<html lang="fr">
<head>
$HANDOFF
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pages disponibles</title>
<style>
body { font-family: Arial, Helvetica, sans-serif; background: #eef1f5; color: #1f2933; margin: 0; padding: 40px 16px; }
main { max-width: 720px; margin: 0 auto; }
h1 { font-size: 22px; margin: 0 0 6px; }
.lead { margin: 0 0 28px; color: #52606d; }
.card { display: block; background: #fff; border-left: 4px solid #2f5d8a; padding: 16px 20px; margin-bottom: 14px; text-decoration: none; color: inherit; box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12); }
.card:hover { box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2); }
.card h2 { font-size: 17px; margin: 0 0 4px; color: #2f5d8a; }
.card p { margin: 0; color: #52606d; font-size: 14px; }
footer { margin-top: 32px; font-size: 13px; color: #7b8794; }
</style>
</head>
<body>
<main>
<h1>Pages disponibles</h1>
<p class="lead">Choisissez la page à consulter.</p>
$cards
<footer>Bastien Boivin, Université de Rennes</footer>
</main>
</body>
</html>
HTML
encrypt "$tmp/hub.html" index.html

if (( commit )); then
    paths=(index.html .staticrypt.json)
    for n in "${names[@]}"; do [[ -f "$n/index.html" ]] && paths+=("$n/index.html"); done
    git add -- "${paths[@]}"
    if git diff --cached --quiet -- "${paths[@]}"; then
        echo "nothing to commit"
    else
        git commit -q -m "chore: update pages $(date +%F)" -- "${paths[@]}"
        echo "committed. Publish with: git push"
    fi
fi
