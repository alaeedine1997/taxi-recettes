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
    driver_id = auth.uid()
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
  for select using (driver_id = auth.uid());

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

-- =====================================================================
--  NOTE rétention (à faire plus tard, hors v0) : purger les vieux points
--  pour ne garder que ~le trajet du jour, ex. via un cron :
--    delete from public.positions where recorded_at < now() - interval '2 days';
--  (le "trajet du jour" n'a besoin que des points d'aujourd'hui.)
-- =====================================================================
