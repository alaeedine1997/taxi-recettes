# Taxi Recettes — système UI/UX final

## Positionnement

Taxi Recettes est un outil opérationnel et financier. L’interface doit être rapide,
fiable et lisible en situation réelle, pas décorative. Les trois espaces partagent
les mêmes composants, mais chaque rôle possède sa propre hiérarchie.

## Identité

- Style : centre d’opérations automobile, net et premium.
- Police : IBM Plex Sans, avec chiffres tabulaires pour les montants et compteurs.
- Marque : bleu nuit `#0F172A`.
- Action chauffeur : jaune taxi `#F5B700`, texte bleu nuit.
- Action patron : bleu `#1D4ED8`, texte blanc.
- Action super admin : violet `#6D4AFF`, texte blanc.
- Succès : `#15803D`; avertissement : `#A16207`; danger : `#C0262D`.
- Toile : `#F4F6F9`; surface : `#FFFFFF`; texte : `#101828`.

## Principes

1. Une action principale par écran.
2. Cibles tactiles de 44 px minimum, 48 px sur les actions terrain.
3. Navigation mobile en bas, navigation bureau dans une barre latérale.
4. Le chauffeur encode une course avec le moins de gestes possible.
5. Le patron accède au traceur GPS dès le résumé.
6. Le super admin dispose d’une densité supérieure, sans masquer le contexte de flotte.
7. Les montants, états GPS et erreurs ne reposent jamais uniquement sur la couleur.
8. Les animations durent 150–300 ms et sont désactivées avec `prefers-reduced-motion`.
9. Le contenu reste exploitable à 375, 768, 1024 et 1440 px.
10. Aucun emoji n’est utilisé comme icône structurelle : uniquement des SVG cohérents.

## Composants

- Rayon : 10 px pour les contrôles, 16 px pour les cartes, 24 px pour les héros.
- Ombres : faibles sur les données, plus marquées seulement sur les surfaces prioritaires.
- Champs : libellé visible, hauteur 46–50 px, erreur proche du champ.
- Boutons : état survol, appui, focus et désactivé toujours visible.
- Carte GPS : liste des véhicules à gauche sur bureau, défilement horizontal sur mobile.
- Résultat financier : bloc visible et stable, chiffres tabulaires, détail vérifiable.

## Thèmes

Le thème sombre utilise des surfaces bleu nuit désaturées. Le jaune, le bleu et le
violet conservent leur rôle, avec contraste vérifié séparément du thème clair.
