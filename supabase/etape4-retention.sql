-- =====================================================================
--  ÉTAPE 4 — Rétention des positions GPS (purge automatique)
--  À exécuter dans l'éditeur SQL Supabase (projet taxi-recettes).
--  But : ne garder que ~2 jours de points (le "trajet du jour" n'a besoin
--        que d'aujourd'hui) → évite l'accumulation infinie + respecte la vie privée.
--  Prérequis : etape3-gps.sql (table positions).
--  FACULTATIF : si pg_cron n'est pas disponible sur ton offre, tu peux ignorer
--  ce fichier ; tu peux aussi lancer la ligne DELETE à la main de temps en temps.
-- =====================================================================

-- 1) Active l'ordonnanceur (une seule fois par projet)
create extension if not exists pg_cron;

-- 2) (Re)planifie une purge quotidienne à 03:00 UTC. Idempotent : on retire l'ancien job avant.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'purge-positions-2j') then
    perform cron.unschedule('purge-positions-2j');
  end if;
end $$;

select cron.schedule(
  'purge-positions-2j',
  '0 3 * * *',
  $$delete from public.positions where recorded_at < now() - interval '2 days'$$
);

-- Vérifier :   select jobname, schedule, active from cron.job;
-- Débrancher : select cron.unschedule('purge-positions-2j');
-- Purge manuelle immédiate :
--   delete from public.positions where recorded_at < now() - interval '2 days';
