-- ÉTAPE 8 — Durcissement (issu de la revue de sécurité)
-- À lancer dans l'éditeur SQL Supabase. Idempotent : relançable sans risque.
--
-- Corrige 7 vrais problèmes :
--  1. Un compte DÉSACTIVÉ gardait tous ses accès (la colonne profiles.active
--     n'était vérifiée quasiment nulle part).
--  2. Un patron n'ayant que l'option « carte live » pouvait relire tout
--     l'historique conservé — c'est-à-dire l'option « trajet du jour » gratuite.
--  3. carnet_periode acceptait n'importe quelle période : un appel forgé
--     1900→2100 renvoyait TOUT le carnet, ce qui annulait l'intérêt de l'étape 7.
--  4. Un chauffeur transféré de flotte restait bloqué avec sa plaque en main,
--     sans pouvoir la rendre ni en reprendre une.
--  5. Le rôle « anon » gardait le droit d'appeler des fonctions internes.
--  6. Un patron pouvait réécrire l'identité technique d'un chauffeur.
--  7. Une position impossible ou datée dans le futur pouvait polluer la carte.

-- ---------------------------------------------------------------------------
-- 1) Les fonctions d'identité ignorent désormais les comptes désactivés
--    et les membres d'une flotte suspendue.
--    Elles renvoient NULL => toutes les policies qui s'appuient dessus tombent.
-- ---------------------------------------------------------------------------
create or replace function public.my_fleet()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.fleet_id
  from public.profiles p
  where p.id = auth.uid()
    and p.active
    and (
      p.role::text = 'superadmin'
      or p.fleet_id is null
      or exists (
        select 1
        from public.fleets f
        where f.id = p.fleet_id and not f.suspended
      )
    )
$$;

create or replace function public.my_role_sd()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.role::text
  from public.profiles p
  where p.id = auth.uid()
    and p.active
    and (
      p.role::text = 'superadmin'
      or p.fleet_id is null
      or exists (
        select 1
        from public.fleets f
        where f.id = p.fleet_id and not f.suspended
      )
    )
$$;

-- 5) anon reçoit EXECUTE par défaut chez Supabase : « from public » ne suffit pas.
revoke all on function public.my_fleet()    from public, anon;
revoke all on function public.my_role_sd()  from public, anon;
grant execute on function public.my_fleet()   to authenticated;
grant execute on function public.my_role_sd() to authenticated;

-- ---------------------------------------------------------------------------
-- 2) GPS : coordonnées bornées et date plausible. Un chauffeur peut rejouer
--    jusqu'à deux jours de sa file hors-ligne, même après avoir rendu la
--    plaque, mais seulement dans les heures de sa propre session.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.positions'::regclass
      and conname = 'positions_coordinates_valid'
  ) then
    alter table public.positions
      add constraint positions_coordinates_valid check (
        lat between -90 and 90
        and lng between -180 and 180
        and (accuracy is null or accuracy between 0 and 10000)
      ) not valid;
  end if;
end
$$;

drop policy if exists positions_driver_insert on public.positions;
create policy positions_driver_insert on public.positions
  for insert
  to authenticated
  with check (
    public.my_role_sd() = 'chauffeur'
    and driver_id = auth.uid()
    and fleet_id = public.my_fleet()
    and lat between -90 and 90
    and lng between -180 and 180
    and (accuracy is null or accuracy between 0 and 10000)
    and recorded_at >= now() - interval '2 days'
    and recorded_at <= now() + interval '5 minutes'
    and exists (
      select 1 from public.plate_sessions s
      where s.driver_id = auth.uid()
        and s.plate_id = positions.plate_id
        and s.fleet_id = public.my_fleet()
        and positions.recorded_at >= s.started_at - interval '5 minutes'
        and positions.recorded_at <= coalesce(
          s.ended_at + interval '5 minutes',
          now() + interval '5 minutes'
        )
    )
  );

-- ---------------------------------------------------------------------------
-- 3) GPS : « carte live » ne donne plus accès à tout l'historique.
--    live  -> les 15 dernières minutes seulement
--    replay-> tout ce qui est conservé
-- ---------------------------------------------------------------------------
drop policy if exists positions_patron_read on public.positions;
create policy positions_patron_read on public.positions
  for select
  to authenticated
  using (
    public.my_role() = 'patron'
    and positions.fleet_id = public.my_fleet()
    and exists (
      select 1 from public.fleets f
      where f.id = positions.fleet_id          -- qualifié : évite toute décorrélation future
        and not f.suspended
        and ( f.opt_replay
              or (f.opt_gps_live and positions.recorded_at > now() - interval '15 minutes') )
    )
  );

-- ---------------------------------------------------------------------------
-- 4) Le chauffeur peut TOUJOURS rendre sa plaque, même transféré ou désactivé.
--    (Le trigger plate_session_lock_cols gèle déjà fleet_id : la condition
--     retirée ici ne protégeait rien, elle ne faisait que bloquer le chauffeur.)
-- ---------------------------------------------------------------------------
drop policy if exists psess_driver_update on public.plate_sessions;
create policy psess_driver_update on public.plate_sessions
  for update
  to authenticated
  using      (driver_id = auth.uid())
  with check (driver_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 5) carnet_periode : période bornée à 3 mois par appel.
--    L'app ne demande jamais plus, mais l'app n'est pas la barrière.
-- ---------------------------------------------------------------------------
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
        where kv.key ~ '^\d{4}-\d{2}-\d{2}$'
          and kv.key >= to_char(p_from, 'YYYY-MM-DD')
          and kv.key <= to_char(p_to,   'YYYY-MM-DD')
      ), '{}'::jsonb)
  )
  from public.carnets c
  where c.user_id = p_driver
    and p_from <= p_to
    and (p_to - p_from) <= 92            -- 3 mois maximum par appel
    and exists (select 1 from public.profiles me where me.id = auth.uid() and me.active)
    and (
      public.my_role_sd() = 'superadmin'
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
      or (p_driver = auth.uid() and public.my_role_sd() = 'chauffeur')
    )
$$;
revoke all on function public.carnet_periode(uuid, date, date) from public, anon;
grant execute on function public.carnet_periode(uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Un patron peut activer/désactiver un chauffeur, mais ne peut pas réécrire
--    son identité, son rôle ou sa flotte par un PATCH PostgREST forgé.
--    Le super-admin et les opérations serveur restent autorisés.
-- ---------------------------------------------------------------------------
create or replace function public.profile_lock_scope()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
     and public.my_role_sd() is distinct from 'superadmin'
     and (
       new.id       is distinct from old.id
       or new.username is distinct from old.username
       or new.role     is distinct from old.role
       or new.fleet_id is distinct from old.fleet_id
     ) then
    raise exception 'profiles : identité, rôle et flotte non modifiables';
  end if;
  return new;
end
$$;

drop trigger if exists profile_scope_lock on public.profiles;
create trigger profile_scope_lock
before update on public.profiles
for each row execute function public.profile_lock_scope();

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 1bis) my_role() : même correctif « compte actif + flotte non suspendue ».
--       PLACÉ EN DERNIER EXPRÈS : son corps d'origine n'est pas versionné ici.
--       Si cette instruction échoue (type de retour différent), TOUT CE QUI
--       PRÉCÈDE EST DÉJÀ APPLIQUÉ — il n'y a rien à refaire, signale-le moi.
-- ---------------------------------------------------------------------------
create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.role::text
  from public.profiles p
  where p.id = auth.uid()
    and p.active
    and (
      p.role::text = 'superadmin'
      or p.fleet_id is null
      or exists (
        select 1
        from public.fleets f
        where f.id = p.fleet_id and not f.suspended
      )
    )
$$;

revoke all on function public.my_role() from public, anon;
grant execute on function public.my_role() to authenticated;

notify pgrst, 'reload schema';
