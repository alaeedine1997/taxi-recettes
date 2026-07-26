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
