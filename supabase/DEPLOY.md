# Déployer la fonction de gestion des comptes

Les boutons de création, suppression et réinitialisation de mot de passe utilisent
l’Edge Function Supabase `rapid-function`.

La clé `service_role` reste exclusivement dans l’environnement protégé de
Supabase. Elle ne doit jamais être copiée dans le dépôt, le navigateur, Android
ou un message.

## Méthode recommandée — Supabase CLI

Depuis la racine du dépôt :

```bash
supabase login
supabase link --project-ref trftmfsuucgauglchnfw
supabase functions deploy rapid-function \
  --project-ref trftmfsuucgauglchnfw
```

Le code à déployer est `supabase/functions/rapid-function/index.ts`. Le dossier
et le slug distant doivent rester exactement `rapid-function`, car les tableaux
de bord appellent :

```text
POST /functions/v1/rapid-function
```

Conserver la vérification JWT de la passerelle activée. Le fichier
`supabase/config.toml` fixe explicitement `verify_jwt = true` pour empêcher une
régression lors des prochains déploiements. Le navigateur envoie la clé publique
`sb_publishable_…` dans `apikey` et le JWT de session dans `Authorization`. La
fonction revérifie ensuite ce JWT avec `auth.getUser()`, puis le rôle, l’état
actif et la flotte dans `profiles`.

## Depuis le Dashboard

1. Ouvrir **Edge Functions** puis **Deploy a new function**.
2. Donner le nom exact `rapid-function`.
3. Coller `supabase/functions/rapid-function/index.ts`.
4. Laisser **Verify JWT** activé.
5. Déployer.

`SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` sont injectées automatiquement par
Supabase dans la fonction hébergée. Ne pas créer de copie de ces secrets.

## Vérification sûre

Sans connexion, cet appel doit répondre `401` :

```bash
curl -i \
  -X POST \
  -H 'Content-Type: application/json' \
  -H 'apikey: sb_publishable_mjNmfNZfe-h6Ywj_Gr3g3Q_MZBstjrh' \
  -d '{"action":"create"}' \
  'https://trftmfsuucgauglchnfw.supabase.co/functions/v1/rapid-function'
```

Ensuite, depuis le tableau de bord administrateur connecté :

1. créer un chauffeur d’essai ;
2. se connecter avec ce chauffeur ;
3. vérifier qu’il ne voit que son propre carnet ;
4. supprimer le compte d’essai.

Une réponse `404` signifie que le slug n’est pas déployé. Une réponse `401`
sans session est normale et confirme que la fonction n’accepte pas un appel
anonyme.
