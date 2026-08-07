-- =====================================================================
-- ETAPE 11 - Durcissement issu des advisors Supabase
-- Idempotente : peut etre relancee apres chaque mise a jour.
-- =====================================================================

-- Les fonctions trigger ne doivent ni dependre du search_path de l'appelant,
-- ni etre appelables directement via la Data API.
alter function public.plate_session_lock_cols()
  set search_path = public, pg_temp;

revoke all on function public.plate_session_lock_cols()
  from public, anon, authenticated;
revoke all on function public.profile_lock_scope()
  from public, anon, authenticated;
revoke all on function public.plates_enforce_max()
  from public, anon, authenticated;

-- Policies historiques creees avant la nomenclature versionnee.
drop policy if exists superadmin_all_fleets on public.fleets;
drop policy if exists superadmin_all_profiles on public.profiles;

-- Toutes les policies de l'application ciblent explicitement les utilisateurs
-- connectes. Les roles techniques Supabase contournent deja la RLS si requis.
alter policy fleets_superadmin_all on public.fleets to authenticated;
alter policy fleets_member_read on public.fleets to authenticated;

alter policy profiles_self_read on public.profiles to authenticated;
alter policy profiles_superadmin_all on public.profiles to authenticated;
alter policy profiles_patron_read on public.profiles to authenticated;
alter policy profiles_patron_update_driver on public.profiles to authenticated;

alter policy carnets_owner_all on public.carnets to authenticated;

alter policy plates_superadmin_all on public.plates to authenticated;
alter policy plates_patron_all on public.plates to authenticated;
alter policy plates_member_read on public.plates to authenticated;

alter policy psess_superadmin_all on public.plate_sessions to authenticated;
alter policy psess_patron_read on public.plate_sessions to authenticated;
alter policy psess_driver_insert on public.plate_sessions to authenticated;
alter policy psess_driver_update on public.plate_sessions to authenticated;
alter policy psess_patron_update on public.plate_sessions to authenticated;
alter policy psess_driver_read on public.plate_sessions to authenticated;
alter policy psess_member_read_active on public.plate_sessions to authenticated;

alter policy positions_superadmin_all on public.positions to authenticated;
alter policy positions_driver_insert on public.positions to authenticated;
alter policy positions_driver_read on public.positions to authenticated;
alter policy positions_patron_read on public.positions to authenticated;

alter policy fcfg_superadmin_all on public.fleet_config to authenticated;
alter policy fcfg_patron_all on public.fleet_config to authenticated;
alter policy fcfg_member_read on public.fleet_config to authenticated;

-- Un SELECT scalaire permet a PostgreSQL d'evaluer auth.uid() une seule fois
-- par requete au lieu d'une fois par ligne.
alter policy profiles_self_read on public.profiles
  using (id = (select auth.uid()) and active);

alter policy carnets_owner_all on public.carnets
  using (
    user_id = (select auth.uid())
    and public.my_role() = 'chauffeur'
  )
  with check (
    user_id = (select auth.uid())
    and public.my_role() = 'chauffeur'
  );

alter policy psess_driver_insert on public.plate_sessions
  with check (
    public.my_role() = 'chauffeur'
    and driver_id = (select auth.uid())
    and fleet_id = public.my_fleet()
    and exists (
      select 1
      from public.plates p
      where p.id = plate_sessions.plate_id
        and p.fleet_id = public.my_fleet()
        and p.active
    )
  );

alter policy psess_driver_read on public.plate_sessions
  using (
    driver_id = (select auth.uid())
    and (ended_at is null or public.my_role() = 'chauffeur')
  );

alter policy psess_driver_update on public.plate_sessions
  using (driver_id = (select auth.uid()))
  with check (driver_id = (select auth.uid()));

alter policy positions_driver_insert on public.positions
  with check (
    public.my_role_sd() = 'chauffeur'
    and driver_id = (select auth.uid())
    and fleet_id = public.my_fleet()
    and lat between -90 and 90
    and lng between -180 and 180
    and (accuracy is null or accuracy between 0 and 10000)
    and recorded_at >= now() - interval '2 days'
    and recorded_at <= now() + interval '5 minutes'
    and exists (
      select 1
      from public.plate_sessions s
      where s.driver_id = (select auth.uid())
        and s.plate_id = positions.plate_id
        and s.fleet_id = public.my_fleet()
        and positions.recorded_at >= s.started_at - interval '5 minutes'
        and positions.recorded_at <= coalesce(
          s.ended_at + interval '5 minutes',
          now() + interval '5 minutes'
        )
    )
  );

alter policy positions_driver_read on public.positions
  using (
    driver_id = (select auth.uid())
    and public.my_role() = 'chauffeur'
  );

notify pgrst, 'reload schema';
