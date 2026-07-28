-- TAXI RECETTES — INSTALLATION COMPLÈTE SUPABASE
-- Généré à partir des migrations versionnées. Relançable sans erreur.
-- Exécuter ce fichier dans le SQL Editor d’un projet Supabase neuf.


-- ============================================================
-- SOURCE: supabase/etape1-base.sql
-- ============================================================

-- =====================================================================
-- ÉTAPE 1 — Socle complet Taxi Recettes
-- À exécuter UNE FOIS avant les étapes 2 à 10. Sûr à relancer.
-- Ne contient aucune clé secrète.
-- =====================================================================

create extension if not exists pgcrypto;

create table if not exists public.fleets (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  max_plates   integer not null default 0 check (max_plates >= 0),
  suspended    boolean not null default false,
  opt_gps_live boolean not null default true,
  opt_replay   boolean not null default true,
  opt_recettes boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text not null,
  display_name text not null default '',
  role         text not null default 'chauffeur'
               check (role in ('superadmin','patron','chauffeur')),
  fleet_id     uuid references public.fleets(id) on delete set null,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);
create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username));
create index if not exists profiles_fleet_role
  on public.profiles (fleet_id, role) where active;

create table if not exists public.carnets (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  data       jsonb not null default '{"version":2,"days":{}}'::jsonb,
  updated_at timestamptz not null default now(),
  device     text not null default ''
);
create index if not exists carnets_updated_at on public.carnets (updated_at desc);

alter table public.fleets   enable row level security;
alter table public.profiles enable row level security;
alter table public.carnets  enable row level security;

create or replace function public.my_role()
returns text
language sql stable security definer
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

create or replace function public.my_fleet()
returns uuid
language sql stable security definer
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

revoke all on function public.my_role()  from public, anon;
revoke all on function public.my_fleet() from public, anon;
grant execute on function public.my_role()  to authenticated;
grant execute on function public.my_fleet() to authenticated;

drop policy if exists fleets_superadmin_all on public.fleets;
create policy fleets_superadmin_all on public.fleets
  for all to authenticated
  using (public.my_role() = 'superadmin')
  with check (public.my_role() = 'superadmin');

drop policy if exists member_reads_own_fleet on public.fleets;
drop policy if exists fleets_member_read on public.fleets;
create policy fleets_member_read on public.fleets
  for select to authenticated
  using (
    public.my_role() = 'superadmin'
    or (id = public.my_fleet() and not suspended)
  );

drop policy if exists own_profile_read on public.profiles;
drop policy if exists profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles
  for select to authenticated
  using (id = auth.uid() and active);

drop policy if exists profiles_superadmin_all on public.profiles;
create policy profiles_superadmin_all on public.profiles
  for all to authenticated
  using (public.my_role() = 'superadmin')
  with check (public.my_role() = 'superadmin');

drop policy if exists profiles_patron_read on public.profiles;
create policy profiles_patron_read on public.profiles
  for select to authenticated
  using (
    public.my_role() = 'patron'
    and public.my_fleet() is not null
    and fleet_id = public.my_fleet()
  );

drop policy if exists profiles_patron_update_driver on public.profiles;
create policy profiles_patron_update_driver on public.profiles
  for update to authenticated
  using (
    public.my_role() = 'patron'
    and public.my_fleet() is not null
    and role = 'chauffeur'
    and fleet_id = public.my_fleet()
  )
  with check (
    public.my_role() = 'patron'
    and role = 'chauffeur'
    and fleet_id = public.my_fleet()
  );

drop policy if exists own_carnet_all on public.carnets;
drop policy if exists carnets_owner_all on public.carnets;
create policy carnets_owner_all on public.carnets
  for all to authenticated
  using (user_id = auth.uid() and public.my_role() = 'chauffeur')
  with check (user_id = auth.uid() and public.my_role() = 'chauffeur');

revoke all on table public.fleets, public.profiles, public.carnets from anon;
grant select, insert, update, delete on table public.fleets, public.profiles, public.carnets to authenticated;

notify pgrst, 'reload schema';

-- PREMIER SUPER-ADMIN
-- 1. Crée d'abord un utilisateur dans Authentication > Users.
-- 2. Copie son UUID, puis exécute en remplaçant les valeurs :
--
-- insert into public.profiles (id, username, display_name, role)
-- values ('UUID_AUTH', 'admin', 'Administrateur', 'superadmin')
-- on conflict (id) do update
-- set username=excluded.username, display_name=excluded.display_name,
--     role='superadmin', active=true;

-- ============================================================
-- SOURCE: supabase/etape2-plaques.sql
-- ============================================================

-- =====================================================================
--  ÉTAPE 2 — Plaques + Prise de plaque
--  À exécuter dans l'éditeur SQL Supabase (projet taxi-recettes).
--  Sûr à relancer (idempotent : if not exists / or replace / drop policy).
-- =====================================================================

-- Helper : fleet_id du chauffeur/patron courant (security definer → contourne la RLS de profiles)
create or replace function public.my_fleet()
returns uuid
language sql stable security definer set search_path = public, pg_temp
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

-- ---------------------------------------------------------------------
--  Table des plaques (une plaque appartient à une flotte)
-- ---------------------------------------------------------------------
create table if not exists public.plates (
  id         uuid primary key default gen_random_uuid(),
  fleet_id   uuid not null references public.fleets(id) on delete cascade,
  label      text not null,                       -- matricule / n° de plaque (ex : "TX-AA-123")
  active     boolean not null default true,       -- désactivable sans supprimer l'historique
  created_at timestamptz not null default now(),
  unique (fleet_id, label)
);
alter table public.plates enable row level security;

drop policy if exists plates_superadmin_all on public.plates;
create policy plates_superadmin_all on public.plates
  for all using (public.my_role() = 'superadmin') with check (public.my_role() = 'superadmin');

drop policy if exists plates_patron_all on public.plates;
create policy plates_patron_all on public.plates
  for all using (public.my_role() = 'patron' and fleet_id = public.my_fleet())
  with check (public.my_role() = 'patron' and fleet_id = public.my_fleet());

drop policy if exists plates_member_read on public.plates;
create policy plates_member_read on public.plates
  for select using (fleet_id = public.my_fleet());

-- ---------------------------------------------------------------------
--  Sessions de prise de plaque (check-in / check-out)
--  ended_at = NULL  →  session ACTIVE (le chauffeur conduit cette plaque maintenant)
-- ---------------------------------------------------------------------
create table if not exists public.plate_sessions (
  id         uuid primary key default gen_random_uuid(),
  plate_id   uuid not null references public.plates(id) on delete cascade,
  driver_id  uuid not null references public.profiles(id) on delete cascade,
  fleet_id   uuid not null references public.fleets(id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at   timestamptz
);
alter table public.plate_sessions enable row level security;

-- Invariants forts (au niveau base) :
--   • une seule session ACTIVE par plaque   → pas 2 chauffeurs sur la même plaque
create unique index if not exists plate_sessions_one_active_plate
  on public.plate_sessions (plate_id) where ended_at is null;
--   • une seule session ACTIVE par chauffeur → un chauffeur = une plaque à la fois
create unique index if not exists plate_sessions_one_active_driver
  on public.plate_sessions (driver_id) where ended_at is null;
-- Recherche rapide "qui conduit quoi maintenant" pour le patron
create index if not exists plate_sessions_active_by_fleet
  on public.plate_sessions (fleet_id) where ended_at is null;

drop policy if exists psess_superadmin_all on public.plate_sessions;
create policy psess_superadmin_all on public.plate_sessions
  for all using (public.my_role() = 'superadmin') with check (public.my_role() = 'superadmin');

-- patron : voit les sessions de SA flotte (qui conduit quelle plaque)
drop policy if exists psess_patron_read on public.plate_sessions;
create policy psess_patron_read on public.plate_sessions
  for select using (public.my_role() = 'patron' and fleet_id = public.my_fleet());

-- chauffeur : prend une plaque (insert) — sur LUI-MÊME, dans SA flotte, ET la plaque doit
-- exister, appartenir à sa flotte ET être active (sinon la règle n'était garantie que côté client).
drop policy if exists psess_driver_insert on public.plate_sessions;
create policy psess_driver_insert on public.plate_sessions
  for insert with check (
    public.my_role() = 'chauffeur'
    and driver_id = auth.uid()
    and fleet_id = public.my_fleet()
    and exists (
      select 1 from public.plates p
      where p.id = plate_id and p.fleet_id = public.my_fleet() and p.active
    )
  );

-- chauffeur : rend sa plaque (update de SES sessions). Le with check reprend l'isolation de flotte ;
-- l'immuabilité des colonnes structurantes est garantie par le trigger ci-dessous (seul ended_at bouge).
drop policy if exists psess_driver_update on public.plate_sessions;
create policy psess_driver_update on public.plate_sessions
  for update using (driver_id = auth.uid())
  with check (driver_id = auth.uid() and fleet_id = public.my_fleet());

-- patron : peut LIBÉRER une plaque de sa flotte (chauffeur qui a oublié de la rendre / passation d'équipe)
drop policy if exists psess_patron_update on public.plate_sessions;
create policy psess_patron_update on public.plate_sessions
  for update using (public.my_role() = 'patron' and fleet_id = public.my_fleet())
  with check (public.my_role() = 'patron' and fleet_id = public.my_fleet());

-- TEMPS SERVEUR + IMMUTABILITÉ : un client ne choisit ni started_at, ni la
-- date de clôture. Une session clôturée ne peut plus être antidatée/prolongée
-- pour élargir artificiellement la fenêtre d'insertion GPS.
create or replace function public.plate_session_lock_cols()
returns trigger language plpgsql as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.started_at := now();
    new.ended_at := null;
    return new;
  end if;

  if new.plate_id  is distinct from old.plate_id
  or new.driver_id is distinct from old.driver_id
  or new.fleet_id  is distinct from old.fleet_id
  or new.started_at is distinct from old.started_at then
    raise exception 'plate_sessions : seul ended_at est modifiable';
  end if;
  if old.ended_at is not null and new.ended_at is distinct from old.ended_at then
    raise exception 'plate_sessions : une session clôturée est immuable';
  end if;
  if old.ended_at is null and new.ended_at is not null then
    new.ended_at := greatest(now(), old.started_at);
  end if;
  return new;
end $$;
drop trigger if exists plate_session_lock on public.plate_sessions;
create trigger plate_session_lock before insert or update on public.plate_sessions
  for each row execute function public.plate_session_lock_cols();

-- chauffeur : relit ses propres sessions
drop policy if exists psess_driver_read on public.plate_sessions;
create policy psess_driver_read on public.plate_sessions
  for select
  to authenticated
  using (
    driver_id = auth.uid()
    and (ended_at is null or public.my_role() = 'chauffeur')
  );

-- =====================================================================
--  (Optionnel) Jeu de test pour valider tout de suite :
--  1) récupère l'id de ta flotte :   select id, name from public.fleets;
--  2) insère 2 plaques (remplace <FLEET_ID>) :
--     insert into public.plates (fleet_id, label) values
--       ('<FLEET_ID>', 'TX-AA-101'), ('<FLEET_ID>', 'TX-AA-102');
--  3) lie le compte de test à la flotte (pour tester la prise de plaque) :
--     update public.profiles set fleet_id = '<FLEET_ID>' where username = 'audit-test';
-- =====================================================================

-- ============================================================
-- SOURCE: supabase/etape3-gps.sql
-- ============================================================

-- =====================================================================
--  ÉTAPE 3 — Positions GPS (suivi pendant le service)
--  À exécuter dans l'éditeur SQL Supabase (projet taxi-recettes).
--  Prérequis : etape2-plaques.sql (my_fleet, plates, plate_sessions).
--  Idempotent (if not exists / drop policy if exists).
-- =====================================================================

create table if not exists public.positions (
  id          uuid primary key default gen_random_uuid(),
  driver_id   uuid not null references public.profiles(id) on delete cascade,
  fleet_id    uuid not null references public.fleets(id) on delete cascade,
  plate_id    uuid references public.plates(id) on delete set null,   -- plaque conduite au moment du point
  lat         double precision not null,
  lng         double precision not null,
  accuracy    real,                                                   -- précision en mètres
  recorded_at timestamptz not null default now()
);
alter table public.positions enable row level security;

-- Requêtes patron "positions de ma flotte, les plus récentes" + "trajet du jour d'une plaque"
create index if not exists positions_fleet_time on public.positions (fleet_id, recorded_at desc);
create index if not exists positions_plate_time on public.positions (plate_id, recorded_at desc);
create index if not exists positions_driver_time on public.positions (driver_id, recorded_at desc);
create index if not exists positions_recorded_at_desc on public.positions (recorded_at desc);

-- superadmin : tout
drop policy if exists positions_superadmin_all on public.positions;
create policy positions_superadmin_all on public.positions
  for all using (public.my_role() = 'superadmin') with check (public.my_role() = 'superadmin');

-- chauffeur : n'ENVOIE que SES propres points, dans SA flotte, ET uniquement PENDANT LE SERVICE :
-- la plaque du point doit correspondre à une session ACTIVE de CE chauffeur (garantie SERVEUR, pas seulement client).
-- Effet : un point sans plaque ou après le rendu de plaque est refusé → pas de suivi 24/7 possible.
drop policy if exists positions_driver_insert on public.positions;
create policy positions_driver_insert on public.positions
  for insert with check (
    public.my_role() = 'chauffeur'
    and driver_id = auth.uid()
    and fleet_id = public.my_fleet()
    and exists (
      select 1 from public.plate_sessions s
      where s.driver_id = auth.uid()
        and s.plate_id  = positions.plate_id
        and s.fleet_id  = public.my_fleet()
        and s.ended_at is null
    )
  );

-- chauffeur : relit ses propres points (vie privée : il voit SA trace)
drop policy if exists positions_driver_read on public.positions;
create policy positions_driver_read on public.positions
  for select
  to authenticated
  using (driver_id = auth.uid() and public.my_role() = 'chauffeur');

-- patron : voit les positions de SA flotte UNIQUEMENT si l'option GPS/replay est débloquée
--          ET la flotte non suspendue (contrôle d'abonnement + confidentialité au niveau base).
drop policy if exists positions_patron_read on public.positions;
create policy positions_patron_read on public.positions
  for select using (
    public.my_role() = 'patron'
    and fleet_id = public.my_fleet()
    and exists (
      select 1 from public.fleets f
      where f.id = fleet_id and not f.suspended and (f.opt_gps_live or f.opt_replay)
    )
  );

-- Carte live : retourne un nombre borné de points PAR plaque. Une limite
-- globale évincerait les véhicules dont le dernier point est moins récent.
create or replace function public.positions_live(
  p_fleet uuid default null,
  p_points integer default 40
)
returns table (
  plate_id uuid,
  fleet_id uuid,
  driver_id uuid,
  lat double precision,
  lng double precision,
  accuracy real,
  recorded_at timestamptz,
  plate_label text,
  driver_name text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with caller as materialized (
    select public.my_role() as role, public.my_fleet() as fleet_id
  ),
  ranked as (
    select
      pos.*,
      row_number() over (
        partition by pos.plate_id
        order by pos.recorded_at desc, pos.id desc
      ) as point_rank
    from public.positions pos
    cross join caller c
    where pos.plate_id is not null
      and pos.recorded_at >= now() - interval '10 minutes'
      and (
        (
          c.role = 'superadmin'
          and (p_fleet is null or pos.fleet_id = p_fleet)
        )
        or (
          c.role = 'patron'
          and pos.fleet_id = c.fleet_id
          and (p_fleet is null or p_fleet = c.fleet_id)
          and exists (
            select 1
            from public.fleets f
            where f.id = pos.fleet_id
              and not f.suspended
              and (f.opt_gps_live or f.opt_replay)
          )
        )
      )
  )
  select
    r.plate_id,
    r.fleet_id,
    r.driver_id,
    r.lat,
    r.lng,
    r.accuracy,
    r.recorded_at,
    pl.label,
    coalesce(nullif(pr.display_name, ''), pr.username)
  from ranked r
  join public.plates pl on pl.id = r.plate_id
  left join public.profiles pr on pr.id = r.driver_id
  where r.point_rank <= least(greatest(coalesce(p_points, 40), 1), 100)
  order by r.recorded_at desc, r.plate_id
$$;

revoke all on function public.positions_live(uuid, integer) from public, anon;
grant execute on function public.positions_live(uuid, integer) to authenticated;

-- =====================================================================
--  NOTE rétention (à faire plus tard, hors v0) : purger les vieux points
--  pour ne garder que ~le trajet du jour, ex. via un cron :
--    delete from public.positions where recorded_at < now() - interval '2 days';
--  (le "trajet du jour" n'a besoin que des points d'aujourd'hui.)
-- =====================================================================

-- ============================================================
-- SOURCE: supabase/etape4-reglages-flotte.sql
-- ============================================================

-- =====================================================================
--  ÉTAPE 4 — Réglages de flotte (sources + retenues + carburant)
--  Le PATRON fixe ces réglages ; le chauffeur de flotte les reçoit en lecture seule.
--  À exécuter dans l'éditeur SQL Supabase. Prérequis : etape2-plaques.sql (my_fleet).
--  Idempotent.
-- =====================================================================

create table if not exists public.fleet_config (
  fleet_id    uuid primary key references public.fleets(id) on delete cascade,
  sources     jsonb   not null default '[]'::jsonb,   -- [{id,name,rate,builtin,appCash}]
  fuel_per_km numeric not null default 0,             -- coût carburant €/km
  updated_at  timestamptz not null default now()
);
alter table public.fleet_config enable row level security;

-- superadmin : tout
drop policy if exists fcfg_superadmin_all on public.fleet_config;
create policy fcfg_superadmin_all on public.fleet_config
  for all using (public.my_role() = 'superadmin') with check (public.my_role() = 'superadmin');

-- patron : édite la config de SA flotte (et seulement la sienne)
drop policy if exists fcfg_patron_all on public.fleet_config;
create policy fcfg_patron_all on public.fleet_config
  for all using (public.my_role() = 'patron' and fleet_id = public.my_fleet())
  with check (public.my_role() = 'patron' and fleet_id = public.my_fleet());

-- membre (chauffeur) : LIT la config de sa flotte
drop policy if exists fcfg_member_read on public.fleet_config;
create policy fcfg_member_read on public.fleet_config
  for select using (fleet_id = public.my_fleet());

-- Config par défaut pour chaque flotte existante (5 sources standard, carburant 0)
insert into public.fleet_config (fleet_id, sources, fuel_per_km)
select f.id,
  '[{"id":"uber","name":"Uber","rate":0,"builtin":true,"appCash":true},
    {"id":"bolt","name":"Bolt","rate":0,"builtin":true,"appCash":true},
    {"id":"heetch","name":"Heetch","rate":18,"builtin":true,"appCash":false},
    {"id":"taxivert","name":"Taxis Verts","rate":0,"builtin":true,"appCash":false},
    {"id":"prive","name":"Course privée","rate":0,"builtin":true,"appCash":false}]'::jsonb,
  0
from public.fleets f
on conflict (fleet_id) do nothing;

-- ============================================================
-- SOURCE: supabase/etape4-retention.sql
-- ============================================================

-- =====================================================================
--  ÉTAPE 4 — Rétention des positions GPS (purge automatique)
--  À exécuter dans l'éditeur SQL Supabase (projet taxi-recettes).
--  But : ne garder que ~2 jours de points (le "trajet du jour" n'a besoin
--        que d'aujourd'hui) → évite l'accumulation infinie + respecte la vie privée.
--  Prérequis : etape3-gps.sql (table positions).
--  FACULTATIF : si pg_cron n'est pas disponible sur ton offre, tu peux ignorer
--  ce fichier ; tu peux aussi lancer la ligne DELETE à la main de temps en temps.
-- =====================================================================

-- Active pg_cron si l'offre le permet, puis planifie la purge. Si l'extension
-- n'est pas disponible, l'installation continue et affiche seulement un NOTICE.
do $outer$
begin
  begin
    execute 'create extension if not exists pg_cron';
  exception when others then
    raise notice 'pg_cron indisponible : purge automatique non activée (%)', sqlerrm;
  end;

  if to_regnamespace('cron') is null then
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'purge-positions-2j') then
    perform cron.unschedule('purge-positions-2j');
  end if;
  perform cron.schedule(
    'purge-positions-2j',
    '0 3 * * *',
    $job$delete from public.positions where recorded_at < now() - interval '2 days'$job$
  );
end
$outer$;

-- Vérifier :   select jobname, schedule, active from cron.job;
-- Débrancher : select cron.unschedule('purge-positions-2j');
-- Purge manuelle immédiate :
--   delete from public.positions where recorded_at < now() - interval '2 days';

-- ============================================================
-- SOURCE: supabase/etape5-calcul-patron.sql
-- ============================================================

-- ÉTAPE 5 — Le patron voit les fiches de recette de SES chauffeurs
-- (lecture seule, uniquement les chauffeurs de sa propre flotte).
-- À lancer dans l'éditeur SQL Supabase. Idempotent : relançable sans risque.
--
-- IMPORTANT : à lancer APRÈS avoir mis à jour l'app chauffeur (index.html),
-- qui filtre désormais sa lecture du carnet sur son propre user_id.

-- 0) Fonction dédiée, SECURITY DEFINER (= lit profiles en ignorant la RLS).
--    On crée un NOUVEAU nom exprès : une policy posée SUR profiles qui appellerait
--    une fonction NON security-definer provoquerait une récursion RLS infinie
--    (plus personne ne pourrait se connecter). On ne touche pas à my_role() existante.
create or replace function public.my_role_sd()
returns text
language sql
stable
security definer
set search_path = public
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

revoke all on function public.my_role_sd() from public;
grant execute on function public.my_role_sd() to authenticated;

-- 1) Le patron peut lire les PROFILS des CHAUFFEURS de sa flotte
--    (pour afficher la liste de ses chauffeurs).
--    Limité au rôle 'chauffeur' : il n'a pas à voir les identifiants de
--    connexion des autres patrons ni d'un super-admin.
drop policy if exists profiles_patron_read on public.profiles;
create policy profiles_patron_read on public.profiles
  for select
  to authenticated
  using (
    public.my_role_sd() = 'patron'
    and role::text = 'chauffeur'
    and fleet_id is not null
    and fleet_id = public.my_fleet()
  );

-- 2) [REMPLACÉ PAR L'ÉTAPE 7 — NE PAS RECRÉER]
--    Le patron lisait ici directement la table carnets, donc TOUT l'historique
--    du chauffeur. C'est désormais la fonction public.carnet_periode()
--    (etape7-recette-periode.sql) qui s'en charge, et elle ne renvoie que la
--    période demandée. On supprime la policy si un ancien passage l'avait créée.
drop policy if exists carnets_patron_read on public.carnets;

-- Vérification (doit lister les 2 policies + la fonction en security definer) :
-- select tablename, policyname, cmd from pg_policies
--   where policyname in ('profiles_patron_read','carnets_patron_read');
-- select proname, prosecdef from pg_proc where proname in ('my_role','my_role_sd','my_fleet');


-- ============================================================
-- SOURCE: supabase/etape6-plaques-occupees.sql
-- ============================================================

-- ÉTAPE 6 (optionnelle) — Le chauffeur VOIT les plaques déjà prises
--
-- Sans ce script, tout fonctionne quand même : la prise d'une plaque occupée est
-- déjà refusée par le serveur (index unique) et le chauffeur reçoit le message
-- « Cette plaque est déjà prise par un autre chauffeur » au moment du clic.
-- Avec ce script, les plaques occupées apparaissent grisées AVANT le clic.
--
-- Ce qui est exposé : uniquement les sessions EN COURS de SA flotte
-- (plaque + identifiant technique du chauffeur). Le chauffeur ne peut pas
-- résoudre le nom du collègue : la table profiles reste fermée pour lui.
-- Idempotent : relançable sans risque.

drop policy if exists psess_member_read_active on public.plate_sessions;
create policy psess_member_read_active on public.plate_sessions
  for select
  to authenticated
  using (
    ended_at is null
    and fleet_id is not null
    and fleet_id = public.my_fleet()
  );

-- Vérification :
-- select policyname, cmd from pg_policies
--   where tablename='plate_sessions' and policyname='psess_member_read_active';


-- ============================================================
-- SOURCE: supabase/etape7-recette-periode.sql
-- ============================================================

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
      or (p_driver = auth.uid() and public.my_role_sd() = 'chauffeur')
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

-- ============================================================
-- SOURCE: supabase/etape8-durcissement.sql
-- ============================================================

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

-- ============================================================
-- SOURCE: supabase/etape9-quotas.sql
-- ============================================================

-- ÉTAPE 9 — Faire RESPECTER les quotas (max_plates) et l'option Recettes
-- À lancer dans l'éditeur SQL Supabase. Idempotent : relançable sans risque.
--
-- Jusqu'ici, « Plaques max » et l'option « Recettes » cochées par le super-admin
-- étaient purement décoratives : rien ne les faisait respecter côté serveur.

-- ---------------------------------------------------------------------------
-- 1) max_plates : on ne peut plus ajouter une plaque ACTIVE au-delà du quota.
--    (max_plates <= 0 = pas de limite. On compte les plaques ACTIVES : désactiver
--     une vieille plaque libère un emplacement.)
-- ---------------------------------------------------------------------------
create or replace function public.plates_enforce_max()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  maxp int;
  cnt  int;
begin
  if public.my_role_sd() = 'superadmin' then
    return new;                       -- le super-admin (qui FIXE le quota) n'est pas bloqué par lui
  end if;
  if not coalesce(new.active, true) then
    return new;                       -- une plaque inactive ne consomme pas d'emplacement
  end if;
  select max_plates into maxp from public.fleets where id = new.fleet_id;
  if maxp is not null and maxp > 0 then
    perform 1 from public.fleets where id = new.fleet_id for update;   -- sérialise les ajouts concurrents d'une même flotte
    select count(*) into cnt
      from public.plates
     where fleet_id = new.fleet_id
       and active
       and (tg_op = 'INSERT' or id <> new.id);   -- ne pas se compter soi-même en UPDATE
    if cnt >= maxp then
      raise exception 'Limite de plaques atteinte (max %) pour cette flotte', maxp
        using hint = 'limite_plaques';
    end if;
  end if;
  return new;
end
$$;

-- INSERT (ajout) ET UPDATE (réactivation d'une plaque) sont couverts.
drop trigger if exists plates_max_check on public.plates;
create trigger plates_max_check
  before insert or update of active, fleet_id on public.plates
  for each row execute function public.plates_enforce_max();

-- ---------------------------------------------------------------------------
-- 2) opt_recettes : un patron ne peut lire les carnets (via carnet_periode) que si
--    sa flotte a l'option débloquée. Le super-admin, lui, garde tout.
--    On re-crée la fonction (celle de l'étape 8) avec cette condition en plus.
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
    and (p_to - p_from) <= 92
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
        -- NOUVEAU : l'option Recettes doit être débloquée et la flotte non suspendue
        and exists (
          select 1 from public.fleets f
          where f.id = public.my_fleet()
            and f.opt_recettes
            and not f.suspended
        )
      )
      or (p_driver = auth.uid() and public.my_role_sd() = 'chauffeur')
    )
$$;
revoke all on function public.carnet_periode(uuid, date, date) from public, anon;
grant execute on function public.carnet_periode(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';

-- Vérification :
-- select tgname from pg_trigger where tgrelid='public.plates'::regclass and not tgisinternal;


-- ============================================================
-- SOURCE: supabase/etape10-grants.sql
-- ============================================================

-- =====================================================================
-- ÉTAPE 10 — Exposition Data API explicite + permissions finales
-- Requise par les nouveaux projets Supabase. Sûre à relancer.
-- La RLS reste la barrière de lignes pour chaque table.
-- =====================================================================

revoke all on table
  public.fleets,
  public.profiles,
  public.carnets,
  public.plates,
  public.plate_sessions,
  public.positions,
  public.fleet_config
from anon;

grant select, insert, update, delete on table
  public.fleets,
  public.profiles,
  public.carnets,
  public.plates,
  public.plate_sessions,
  public.positions,
  public.fleet_config
to authenticated;

revoke all on function public.my_role() from public, anon;
revoke all on function public.my_fleet() from public, anon;
revoke all on function public.my_role_sd() from public, anon;
revoke all on function public.carnet_periode(uuid, date, date) from public, anon;
revoke all on function public.positions_live(uuid, integer) from public, anon;

grant execute on function public.my_role() to authenticated;
grant execute on function public.my_fleet() to authenticated;
grant execute on function public.my_role_sd() to authenticated;
grant execute on function public.carnet_periode(uuid, date, date) to authenticated;
grant execute on function public.positions_live(uuid, integer) to authenticated;

notify pgrst, 'reload schema';
