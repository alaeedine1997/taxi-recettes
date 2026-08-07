-- =====================================================================
-- ETAPE 13 - Carte de supervision par chauffeur actif
-- Upgrade cible : n'ecrase aucune policy deja durcie par l'etape 11.
-- =====================================================================

create index if not exists positions_live_session_time
  on public.positions (driver_id, plate_id, fleet_id, recorded_at desc, id desc);

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

revoke all on function public.positions_live(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.positions_live(uuid, integer)
  to authenticated;

notify pgrst, 'reload schema';
