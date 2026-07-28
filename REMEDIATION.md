# Correctifs post-audit

Branche de travail : `agent/full-ui-ux-overhaul`.

## Changements appliqués

- Nouvelle interface commune chauffeur, patron et admin :
  - design system teal/bleu à fort contraste ;
  - polices Lexend et Source Sans 3 ;
  - barre latérale sur ordinateur, navigation basse sur mobile ;
  - formulaires et cibles tactiles de 44 px minimum ;
  - calcul de règlement guidé et résultat maintenu visible ;
  - carte avec âge du point et rayon réel de précision.
- Argent :
  - taux bornés entre 0 et 100 % côté chauffeur et tableaux de bord ;
  - cash `appcash` borné au montant total ;
  - formule finale du taximètre Android alignée sur la formule web.
- Hors-ligne :
  - échec `localStorage` fermé avec restauration de la dernière copie durable ;
  - marqueur de synchronisation embarqué dans le carnet ;
  - tombstones pour empêcher la résurrection des courses/charges supprimées ;
  - résolution LWW par champ pour les kilomètres et horaires.
- Requêtes :
  - réponses obsolètes rejetées pour réglages, calculs et carte GPS ;
  - enregistrement des réglages désactivé si leur chargement échoue.
- Android/GPS :
  - snapshot immédiat au démarrage du taximètre ;
  - restauration d'une course même après un kill prolongé, sans facturer la coupure ;
  - erreur native de démarrage réellement traitée dans l'interface ;
  - position datée au moment de la mesure et points en cache rejetés ;
  - autorisation de partage restaurée après redémarrage du process.
- Signature :
  - clé privée compromise retirée ;
  - aucun mot de passe de signature dans le dépôt.

## Secrets GitHub requis avant la prochaine APK

Créer une **nouvelle** clé de signature puis définir :

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Ne jamais réutiliser la clé supprimée. Si l'application est distribuée via Google
Play App Signing, suivre la procédure officielle de rotation de clé. Sinon, une
nouvelle clé peut nécessiter de désinstaller l'ancienne APK avant installation.

## Vérifications exécutées

```text
100 000 cas d'argent : OK
50 000 configurations taximètre web/Android : OK
Syntaxe JavaScript des 4 pages (dont asset Android) : OK
git diff --check : OK
```

Commande reproductible :

```bash
node tests/regression.mjs
```

La compilation Android complète n'a pas été exécutée localement : Gradle et le SDK
Android ne sont pas installés dans l'environnement d'audit. Le workflow GitHub
reste la validation de compilation faisant autorité.
