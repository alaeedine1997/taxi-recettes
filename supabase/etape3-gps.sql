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
create index if not exists positions_live_session_time
  on public.positions (driver_id, plate_id, fleet_id, recorded_at desc, id desc);
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

-- Carte live : part des sessions actives et cherche directement les derniers
-- points de chaque chauffeur. Le LEFT JOIN conserve aussi « GPS en attente ».
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
  active_sessions as materialized (
    select
      s.id,
      s.plate_id,
      s.fleet_id,
      s.driver_id,
      s.started_at
    from public.plate_sessions s
    cross join caller c
    where s.ended_at is null
      and (
        (
          c.role = 'superadmin'
          and (p_fleet is null or s.fleet_id = p_fleet)
        )
        or (
          c.role = 'patron'
          and s.fleet_id = c.fleet_id
          and (p_fleet is null or p_fleet = c.fleet_id)
          and exists (
            select 1
            from public.fleets f
            where f.id = s.fleet_id
              and not f.suspended
              and (f.opt_gps_live or f.opt_replay)
          )
        )
      )
  )
  select
    s.plate_id,
    s.fleet_id,
    s.driver_id,
    pos.lat,
    pos.lng,
    pos.accuracy,
    pos.recorded_at,
    pl.label,
    coalesce(nullif(pr.display_name, ''), pr.username)
  from active_sessions s
  left join lateral (
    select p.lat, p.lng, p.accuracy, p.recorded_at
    from public.positions p
    where p.driver_id = s.driver_id
      and p.plate_id = s.plate_id
      and p.fleet_id = s.fleet_id
      and p.recorded_at >= greatest(
        s.started_at - interval '5 minutes',
        now() - interval '10 minutes'
      )
      and p.recorded_at <= now() + interval '5 minutes'
    order by p.recorded_at desc, p.id desc
    limit least(greatest(coalesce(p_points, 40), 1), 100)
  ) pos on true
  join public.plates pl on pl.id = s.plate_id
  left join public.profiles pr on pr.id = s.driver_id
  order by pos.recorded_at desc nulls last, s.plate_id
$$;

revoke all on function public.positions_live(uuid, integer) from public, anon;
grant execute on function public.positions_live(uuid, integer) to authenticated;

-- =====================================================================
--  NOTE rétention (à faire plus tard, hors v0) : purger les vieux points
--  pour ne garder que ~le trajet du jour, ex. via un cron :
--    delete from public.positions where recorded_at < now() - interval '2 days';
--  (le "trajet du jour" n'a besoin que des points d'aujourd'hui.)
-- =====================================================================
