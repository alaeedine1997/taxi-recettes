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
