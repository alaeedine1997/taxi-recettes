# Mise en production — Taxi Recettes

Ce guide est la procédure courte et reproductible pour rendre la plateforme
utilisable. Il ne demande jamais la clé `service_role`.

## 1. Installer ou mettre à jour la base

Dans **Supabase > SQL Editor**, ouvrir une nouvelle requête, copier tout le
contenu de `supabase/INSTALLATION-COMPLETE.sql`, puis exécuter.

Le script est idempotent : il peut être relancé après une interruption ou lors
d’une mise à jour. Il crée les tables, fonctions, index, déclencheurs, RLS et
permissions Data API dans l’ordre requis.

Résultat attendu :

- tables : `fleets`, `profiles`, `carnets`, `plates`, `plate_sessions`,
  `positions`, `fleet_config` ;
- RLS activée sur les sept tables ;
- table d'audit `private.carnet_audit` avec RLS et aucun accès Data API ;
- fonctions `admin_ride_mutation` et `positions_live` réservées aux utilisateurs
  connectés, avec validation du rôle à l'intérieur ;
- accès `anon` révoqué ;
- accès des utilisateurs connectés filtré par les policies.

## 2. Créer le premier super-administrateur

1. Dans **Authentication > Users**, créer l’utilisateur
   `admin@taxi.local` avec un mot de passe fort et confirmer son email.
2. Copier son UUID.
3. Exécuter cette requête en remplaçant `UUID_AUTH` :

```sql
insert into public.profiles (id, username, display_name, role, fleet_id, active)
values ('UUID_AUTH', 'admin', 'Administrateur', 'superadmin', null, true)
on conflict (id) do update
set username = excluded.username,
    display_name = excluded.display_name,
    role = 'superadmin',
    fleet_id = null,
    active = true;
```

Le mot de passe ne doit apparaître ni dans SQL ni dans le dépôt.

Dans les réglages de sécurité de Supabase Auth, activer également la protection
contre les mots de passe compromis avant de créer les comptes de production.

## 3. Déployer la gestion des comptes

Suivre `supabase/DEPLOY.md` et déployer le code
`supabase/functions/rapid-function/index.ts` sous le slug exact
`rapid-function`.

## 4. Configurer la signature Android

Générer la clé une seule fois sur un ordinateur sûr :

```bash
keytool -genkeypair -v \
  -keystore taxi-recettes-release.keystore \
  -alias taxi-recettes \
  -keyalg RSA -keysize 4096 -validity 10000
```

Conserver le fichier et ses mots de passe dans un coffre-fort. Perdre cette clé
empêche de mettre à jour les APK déjà installées.

Dans **GitHub > Settings > Secrets and variables > Actions**, créer :

- `ANDROID_KEYSTORE_BASE64` : contenu produit par
  `base64 -w 0 taxi-recettes-release.keystore` ;
- `ANDROID_KEYSTORE_PASSWORD` ;
- `ANDROID_KEY_ALIAS` ;
- `ANDROID_KEY_PASSWORD`.

La clé privée ne doit jamais être commitée. Le workflow refuse désormais de
publier si un secret manque ou si le keystore est invalide.

## 5. Publier

Après validation de la Pull Request :

- `.github/workflows/quality.yml` teste le JavaScript, 210 000 cas de calcul et
  de totalisation dont 50 000 exécutés par le code Kotlin de production, les
  scénarios hors-ligne multi-appareil, les migrations SQL deux fois et les
  trois variantes Android debug ;
- le merge sur `main` déclenche `.github/workflows/build-apk.yml` ;
- la release GitHub `apk-latest` fournit
  `taxi-chauffeur.apk`, `taxi-patron.apk` et `taxi-admin.apk`.

## 6. Recette obligatoire avant utilisation réelle

Faire le test avec une flotte et deux téléphones :

1. l’admin crée une flotte, un patron, un chauffeur et une plaque ;
2. le chauffeur se connecte, prend la plaque et accepte la localisation ;
3. le patron voit le taxi sur la carte, l’heure du point et le rayon de
   précision ;
4. démarrer une course, verrouiller l’écran cinq minutes, puis vérifier que la
   carte et le taximètre continuent ;
5. couper le réseau, ajouter une course, fermer/réouvrir l’app, rétablir le
   réseau et vérifier que la course est synchronisée ;
6. comparer le net chauffeur/patron sur la même période ;
7. terminer la course, rendre la plaque et vérifier que plus aucun nouveau
   point GPS n’est accepté ;
8. suspendre la flotte et vérifier que recettes et carte patron sont bloquées.
9. dans l'espace super-admin, afficher toutes les flottes sur la carte et
   vérifier qu'un chauffeur sans point apparaît comme « GPS en attente » ;
10. modifier puis supprimer une course de test depuis l'espace super-admin,
    et vérifier que le total est recalculé après chaque action.

Ne commencer avec de l'argent réel qu'après réussite des dix contrôles.

## 7. Usage réglementaire du compteur

Le compteur de l’application est un outil d’appoint et de contrôle interne. Pour
une course officielle à Bruxelles, utiliser le taximètre homologué du véhicule
et remettre le ticket imprimé obligatoire. Le préréglage intégré correspond aux
courses de taxi de station sans réservation : prise en charge 2,60 €, 2,30 €/km,
0,60 €/minute, minimum 8 € et supplément nuit 2 € entre 22 h et 6 h.

Vérifier les tarifs sur le site officiel de la Région avant chaque déploiement :
https://be.brussels/fr/transport-mobilite/transport-en-commun/taxi-et-mobilite-partagee/prendre-un-taxi

## 8. Exploitation

- Contrôler chaque jour les échecs des workflows GitHub et les logs Edge
  Functions.
- Vérifier chaque semaine que la tâche `purge-positions-2j` est active. Si
  `pg_cron` n’est pas disponible, lancer la purge manuelle indiquée dans
  `supabase/etape4-retention.sql`.
- Sauvegarder séparément le keystore Android et les codes de récupération
  Supabase/GitHub.
- Ne jamais désactiver la RLS pour résoudre un problème d’accès.
