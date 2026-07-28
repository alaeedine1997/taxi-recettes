# Reprise Codex — Taxi Recettes

## Objectif

Finaliser, vérifier et publier la version de production de Taxi Recettes sans
jamais pousser directement sur `main`.

## État du projet

- Dépôt : `https://github.com/alaeedine1997/taxi-recettes`
- Branche de travail : `agent/full-ui-ux-overhaul`
- Le dossier contient l’historique Git et toutes les modifications locales.
- Les dépendances et sorties de compilation ont été exclues du transfert.
- Supabase : utiliser uniquement la clé publique anon déjà présente dans le
  projet. Ne jamais demander ni utiliser une clé `service_role`.

## Travail déjà réalisé

- Audit complet : argent, RLS, synchronisation hors ligne, Android, GPS,
  taximètre, SQL et tableaux de bord.
- Refonte UI/UX complète et distincte pour chauffeur, patron et super-admin.
- Carte GPS de suivi des chauffeurs avec historique de position.
- Renforcement de la WebView Android, de la file GPS hors ligne et du
  taximètre natif.
- Migrations Supabase idempotentes et durcissement RLS.
- Tests de parité financière, synchronisation, SQL et HTML.
- Documentation de production et rapport d’audit.

## Consigne à exécuter

1. Lire `AUDIT-COMPLET.md`, `REMEDIATION.md`,
   `MISE-EN-PRODUCTION.md` et `git status -sb`.
2. Examiner tout le diff et préserver l’ensemble des modifications prévues.
3. Installer les dépendances avec `npm ci`.
4. Exécuter :

   ```powershell
   npm test
   git diff --check
   ```

5. Corriger tout échec réel sans réduire la couverture ni neutraliser un test.
6. Vérifier que le dépôt distant est bien
   `alaeedine1997/taxi-recettes` et que GitHub CLI est authentifié.
7. Rester sur `agent/full-ui-ux-overhaul`.
8. Ajouter les fichiers, créer un commit clair, pousser la branche et ouvrir
   une Pull Request en brouillon vers `main`.
9. Ne jamais pousser directement sur `main`.
10. Fournir le lien de la Pull Request et la liste exacte des tests réussis.

## Critères de fin

- Tous les tests automatisés passent.
- Aucune fuite anonyme ou inter-flotte connue.
- `rideNet` et `cRideNet` restent identiques.
- Les courses hors ligne ne sont pas perdues.
- Les trois interfaces utilisent la nouvelle identité visuelle.
- La branche est publiée et une Pull Request en brouillon est ouverte.
- Les tests physiques Android/GPS restants sont signalés clairement s’ils
  nécessitent un appareil réel.
