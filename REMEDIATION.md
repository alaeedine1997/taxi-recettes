# Correctifs post-audit

Le rapport complet et les preuves sont dans `AUDIT-COMPLET.md`. La procédure de
déploiement et de recette finale est dans `MISE-EN-PRODUCTION.md`.

## Changements appliqués

- Nouvelle interface adaptée à chaque rôle :
  - cockpit chauffeur bleu nuit + jaune taxi ;
  - centre opérationnel patron bleu, avec accès direct au traceur ;
  - console super admin violette, plus dense ;
  - police IBM Plex Sans et chiffres tabulaires ;
  - barre latérale sur ordinateur, navigation basse sur mobile ;
  - formulaires et cibles tactiles de 44 px minimum ;
  - calcul de règlement guidé et résultat maintenu visible ;
  - carte avec âge du point et rayon réel de précision.
  - cache PWA renouvelé pour forcer le chargement du nouveau design.
- Argent :
  - taux bornés entre 0 et 100 % côté chauffeur et tableaux de bord ;
  - cash `appcash` borné au montant total ;
  - formule finale du taximètre Android alignée sur la formule web.
- Hors-ligne :
  - échec `localStorage` fermé avec restauration de la dernière copie durable ;
  - marqueur de synchronisation embarqué dans le carnet ;
  - marqueur monotone persisté avec les données avant la métadonnée séparée ;
  - tombstones pour empêcher la résurrection des courses/charges supprimées ;
  - résolution LWW par champ pour les kilomètres et horaires.
- Requêtes :
  - réponses obsolètes rejetées pour réglages, calculs et carte GPS ;
  - carte live limitée par plaque au lieu d'une limite globale évictive ;
  - création flotte + patron conservée si la réponse réseau est ambiguë ;
  - enregistrement des réglages désactivé si leur chargement échoue.
- Android/GPS :
  - snapshot immédiat au démarrage du taximètre ;
  - état natif et snapshot annulés si le service Android refuse de démarrer ;
  - restauration d'une course même après un kill prolongé, sans facturer la coupure ;
  - erreur native de démarrage réellement traitée dans l'interface ;
  - position datée au moment de la mesure et points en cache rejetés ;
  - autorisation de partage restaurée après redémarrage du process ;
  - file GPS hors-ligne, refresh du jeton et rejeu après rendu de plaque ;
  - heures de prise/rendu imposées par le serveur et session clôturée immuable ;
  - WebView isolée sous origine HTTPS locale et navigation externe bloquée.
- Sécurité multi-flotte :
  - les trois anciennes policies permissives sont supprimées lors d'une mise à
    niveau ;
  - seul un profil chauffeur peut prendre une plaque et envoyer du GPS ;
  - une flotte suspendue invalide désormais les helpers RLS même avec un JWT
    encore valide ;
  - positions, sessions clôturées, carnet et prise de plaque sont refusés aux
    membres suspendus.
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
10 000 totaux affichés : OK
50 000 vecteurs de parité taximètre côté Node : OK
50 000 calculs Kotlin de production via JUnit : OK en CI
Deux téléphones + faux PostgREST : aucune perte : OK
Échec fractionné du stockage puis redémarrage : récupération OK
Migrations SQL exécutées deux fois + RLS adversariale : OK
Anciennes policies + usurpation patron/chauffeur : refusées
Flotte suspendue + horodatages de session forgés : refusés
Carte live bornée par plaque : OK
Syntaxe JavaScript des 5 pages (dont asset Android) : OK
Syntaxe TypeScript de l'Edge Function : OK
3 APK debug + 3 APK release : OK
Android Lint Vital : aucun problème
git diff --check : OK
```

Commande reproductible :

```bash
npm test
```
