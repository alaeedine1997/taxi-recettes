# Activer la création de comptes (fonction serveur `create-user`)

La création de comptes (patron / chauffeur) a besoin d'une petite **fonction serveur sécurisée**
(elle utilise une clé secrète qui ne doit jamais être dans le navigateur). Il faut la déployer **une seule fois**.

## Option A — La plus simple (copier-coller dans le dashboard Supabase)

1. Dashboard Supabase → menu de gauche **Edge Functions** → **Deploy a new function** (ou **Create function**).
2. Nom : `create-user`
3. Colle le contenu de `site/supabase/functions/create-user/index.ts`.
4. **Deploy**.
5. La clé `SUPABASE_SERVICE_ROLE_KEY` et `SUPABASE_URL` sont fournies automatiquement à la fonction — rien à configurer.

## Option B — Avec l'outil en ligne de commande (si tu l'as)

```bash
# une seule fois : se connecter et lier le projet
supabase login
supabase link --project-ref trftmfsuucgauglchnfw

# déployer la fonction
supabase functions deploy create-user
```

## Vérifier que ça marche

Une fois déployée, dis-le-moi : je branche le bouton **« Nouveau compte »** dans le tableau de bord
(il appelle `POST /functions/v1/create-user`), et on teste la création d'un patron + d'un chauffeur.

## Règles de sécurité intégrées (déjà dans le code)

- **Super-admin** : peut créer patrons et chauffeurs, dans n'importe quelle flotte.
- **Patron** : peut créer uniquement des **chauffeurs**, et seulement dans **SA** flotte.
- Identifiant = lettres/chiffres/`. _ -`, 2 à 32 caractères → email interne `identifiant@taxi.local`.
- Si l'identifiant est déjà pris → erreur claire (pas de doublon).
- Mot de passe minimum 6 caractères.
