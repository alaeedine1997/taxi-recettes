-- ÉTAPE 7 — Le patron ne télécharge plus le carnet complet
--
-- AVANT : le patron lisait toute la table carnets (tout l'historique du chauffeur,
--         y compris des journées hors flotte ou d'avant son embauche) puis filtrait
--         les dates dans son navigateur.
-- APRÈS : il appelle une fonction qui ne renvoie QUE la période demandée.
--         La policy de lecture directe des carnets est SUPPRIMÉE.
--
-- Le calcul de la recette reste fait côté app (déjà testé, identique au carnet du
-- chauffeur) : on ne duplique pas la formule d'argent en SQL, ce serait le
-- meilleur moyen d'obtenir deux résultats différents.
--
-- Idempotent : relançable sans risque.

-- 1) La fonction. SECURITY DEFINER => elle ignore la RLS, donc elle DOIT
--    vérifier elle-même qui appelle.
create or replace function public.carnet_periode(
  p_driver uuid,
  p_from   date,
  p_to     date
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    -- On ne fait confiance à rien : si la forme n'est pas celle attendue, on
    -- renvoie du vide plutôt que de faire échouer la requête (erreur 500).
    'sources',   case when jsonb_typeof(c.data->'sources')   = 'array'
                      then c.data->'sources'   else '[]'::jsonb end,
    'fuelPerKm', case when jsonb_typeof(c.data->'fuelPerKm') = 'number'
                      then c.data->'fuelPerKm' else '0'::jsonb end,
    'days',      coalesce((
        select jsonb_object_agg(kv.key, kv.value)
        from jsonb_each(
               case when jsonb_typeof(c.data->'days') = 'object'
                    then c.data->'days' else '{}'::jsonb end
             ) kv
        -- comparaison en TEXTE : 'AAAA-MM-JJ' se trie déjà dans l'ordre du calendrier.
        -- (Pas de cast en date : l'ordre d'évaluation du WHERE n'étant pas garanti,
        --  une clé mal formée ferait échouer toute la requête.)
        where kv.key ~ '^\d{4}-\d{2}-\d{2}$'
          and kv.key >= to_char(p_from, 'YYYY-MM-DD')
          and kv.key <= to_char(p_to,   'YYYY-MM-DD')
      ), '{}'::jsonb)
  )
  from public.carnets c
  where c.user_id = p_driver
    and p_from <= p_to
    -- l'appelant doit être un compte ACTIF (un patron désactivé perd l'accès)
    and exists (select 1 from public.profiles me where me.id = auth.uid() and me.active)
    and (
      -- le super-admin peut tout voir
      public.my_role_sd() = 'superadmin'
      -- le patron : uniquement les CHAUFFEURS de SA flotte
      or (
        public.my_role_sd() = 'patron'
        and exists (
          select 1 from public.profiles p
          where p.id = p_driver
            and p.role::text = 'chauffeur'
            and p.fleet_id is not null
            and p.fleet_id = public.my_fleet()
        )
      )
      -- le chauffeur : son propre carnet
      or p_driver = auth.uid()
    )
$$;

-- anon reçoit EXECUTE par défaut chez Supabase : "from public" ne suffit PAS à le retirer.
revoke all on function public.carnet_periode(uuid, date, date) from public, anon;
grant execute on function public.carnet_periode(uuid, date, date) to authenticated;

-- 2) On retire l'accès direct du patron à la table carnets :
--    désormais il passe OBLIGATOIREMENT par la fonction ci-dessus.
--    (Le chauffeur garde l'accès à SON carnet via sa policy d'origine.)
drop policy if exists carnets_patron_read on public.carnets;

-- 3) Rafraîchit le cache de schéma de l'API (évite un 404 juste après l'exécution).
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- VÉRIFICATIONS (à lancer après, dans le même éditeur) :
--
-- a) La fonction existe UNE SEULE FOIS et est bien SECURITY DEFINER :
--    select oid::regprocedure, prosecdef, proacl from pg_proc where proname='carnet_periode';
--
-- b) IMPORTANT — le chauffeur doit GARDER l'accès à son propre carnet,
--    sinon la synchro de tous les chauffeurs casse. Cette liste ne doit PAS être vide :
--    select policyname, cmd from pg_policies where tablename='carnets';
--    (« carnets_patron_read » doit avoir disparu, les autres rester en place.)
-- ---------------------------------------------------------------------------
