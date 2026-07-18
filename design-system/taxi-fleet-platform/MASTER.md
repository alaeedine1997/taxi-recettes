# Design System — Taxi Fleet Platform (SOURCE DE VÉRITÉ)

> Direction choisie par le chauffeur (2026-07-18) : **« Premium chaleureux »** (option 2 sur 3).
> But : plateforme qui inspire confiance (présentée à des patrons de flotte). Chaleureux, élégant, soigné — PAS générique.
> Le taximètre garde son afficheur LED ambre séparé (identité « appareil »).

## Palette (tokens)
Clair :
- `--bg`     #FAF5EC  (crème chaud — volontairement PAS le #F4F1EA cliché)
- `--surface`#FFFFFF
- `--ink`    #241C12  (brun-noir chaud)
- `--muted`  #7C6F5B  (taupe chaud, texte secondaire)
- `--brand`  #B14A28  (terracotta — CTA / accent principal)
- `--on-brand` #FFFFFF
- `--gold`   #A6791F  (ocre profond — accent secondaire, à doser)
- `--line`   #EAE0CE  (filet chaud)
- `--ok`     #4F7A43  (olive)
- `--danger` #B4362B

Sombre (chaud, pas inversé) :
- `--bg` #17130E · `--surface` #201A12 · `--ink` #F0E9DC · `--muted` #A99A82
- `--brand` #D2622F · `--gold` #D9A83A · `--line` #33291B · `--ok` #7FB06B · `--danger` #E06455

## Typographie
- Titres / display : **Fraunces** (serif « old-style » chaleureux, caractériel — plus distinctif que Playfair). Poids 500–600.
- Corps / UI : **Inter** (400/500/600).
- Données / chiffres : Inter tabular-nums (le compteur taxi garde sa mono ambre à part).
- Google Fonts (l'app n'est PAS sous CSP stricte → chargement direct OK) :
  `Fraunces:opsz,wght@9..144,500;9..144,600` + `Inter:wght@400;500;600`.

## Style & exécution
- Élégant-flat avec profondeur douce : ombres subtiles, coins arrondis ~14px, beaucoup d'air.
- PAS de glassmorphism lourd malgré le nom « Liquid Glass » sorti par l'outil — rester lisible et premium.
- Un seul CTA primaire par écran (terracotta plein). Secondaires discrets.
- Icônes SVG (Lucide/Heroicons), jamais d'emoji comme icône structurelle.
- Deux thèmes soignés (clair + sombre chaud), tokens sémantiques, contrastes AA.
- Micro-interactions 150–300ms, focus visibles, prefers-reduced-motion respecté.
- Responsive mobile-first : 375 / 768 / 1024 / 1440. Cibles tactiles ≥44px.

## À éviter (anti-génération-IA)
- Le combo cliché « #F4F1EA + Playfair + terracotta » tel quel → on s'en écarte (Fraunces + crème #FAF5EC).
- Emojis en icônes, ombres au hasard, gris-sur-gris, tout centré, `rounded-lg` partout sans intention.
