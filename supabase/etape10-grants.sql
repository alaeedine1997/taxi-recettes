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
