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
  select role from public.profiles
  where id = auth.uid() and active
$$;

create or replace function public.my_fleet()
returns uuid
language sql stable security definer
set search_path = public, pg_temp
as $$
  select fleet_id from public.profiles
  where id = auth.uid() and active
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

drop policy if exists fleets_member_read on public.fleets;
create policy fleets_member_read on public.fleets
  for select to authenticated
  using (
    public.my_role() = 'superadmin'
    or (id = public.my_fleet() and not suspended)
  );

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
