# hydro-viz

Pages statiques sur GitHub Pages pour partager des visu aux partenaires sans héberger de serveur. Chiffré avec StatiCrypt pour rien laisser en clair sur le dépôt.

En ligne : https://bastien-boivin.github.io/hydro-viz/

## Config

Sur la machine, dans `~/.config/hydro-viz/` (chmod 600) :
- `passphrase` : mot de passe partagé
- `pages.tsv` : tabulations entre identifiant (p1, p2), titre, desc, chemin du html source

## Commandes

Mettre à jour une page :
```bash
./update.sh p1
git push
```

Tout régénérer :
```bash
./update.sh
git push
```

Tester sans committer : `./update.sh --no-commit`

## Mémo

- Le mot de passe se tape une seule fois sur l'accueil, ensuite le hash tourne dans `sessionStorage` entre les pages.
- Hook `.git/hooks/pre-commit` pour bloquer les commits avec du html en clair. À remettre à la main si clone frais.
- Chaque export ajoute ~20 Mo de html chiffré dans git. Si le dépôt grossit trop, supprimer le repo GitHub et repousser à zéro.
