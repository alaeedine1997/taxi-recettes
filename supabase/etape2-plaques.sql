-- =====================================================================
--  ÉTAPE 2 — Plaques + Prise de plaque
--  À exécuter dans l'éditeur SQL Supabase (projet taxi-recettes).
--  Sûr à relancer (idempotent : if not exists / or replace / drop policy).
-- =====================================================================

-- Helper : fleet_id du chauffeur/patron courant (security definer → contourne la RLS de profiles)
create or replace function public.my_fleet()
returns uuid
language sql stable security definer set search_path = public
as $$ select fleet_id from public.profiles where id = auth.uid() $$;

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
    driver_id = auth.uid()
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

-- IMMUABILITÉ : sur une session, seul ended_at est modifiable (check-out). Empêche de réécrire
-- plate_id / driver_id / fleet_id / started_at par une requête PostgREST forgée (le WITH CHECK ne voit pas OLD).
create or replace function public.plate_session_lock_cols()
returns trigger language plpgsql as $$
begin
  if new.plate_id  is distinct from old.plate_id
  or new.driver_id is distinct from old.driver_id
  or new.fleet_id  is distinct from old.fleet_id
  or new.started_at is distinct from old.started_at then
    raise exception 'plate_sessions : seul ended_at est modifiable';
  end if;
  -- ended_at est UNIDIRECTIONNEL : on peut clôturer (NULL→date) mais pas ré-ouvrir (date→NULL).
  -- Sinon un chauffeur ressusciterait sa session close sur une plaque désactivée / annulerait une libération patron.
  if old.ended_at is not null and new.ended_at is null then
    raise exception 'plate_sessions : une session close ne peut pas être rouverte (reprends la plaque)';
  end if;
  return new;
end $$;
drop trigger if exists plate_session_lock on public.plate_sessions;
create trigger plate_session_lock before update on public.plate_sessions
  for each row execute function public.plate_session_lock_cols();

-- chauffeur : relit ses propres sessions
drop policy if exists psess_driver_read on public.plate_sessions;
create policy psess_driver_read on public.plate_sessions
  for select using (driver_id = auth.uid());

-- =====================================================================
--  (Optionnel) Jeu de test pour valider tout de suite :
--  1) récupère l'id de ta flotte :   select id, name from public.fleets;
--  2) insère 2 plaques (remplace <FLEET_ID>) :
--     insert into public.plates (fleet_id, label) values
--       ('<FLEET_ID>', 'TX-AA-101'), ('<FLEET_ID>', 'TX-AA-102');
--  3) lie le compte de test à la flotte (pour tester la prise de plaque) :
--     update public.profiles set fleet_id = '<FLEET_ID>' where username = 'audit-test';
-- =====================================================================
