-- =====================================================================
--  ÉTAPE 4 — Rétention des positions GPS (purge automatique)
--  À exécuter dans l'éditeur SQL Supabase (projet taxi-recettes).
--  But : ne garder que ~2 jours de points (le "trajet du jour" n'a besoin
--        que d'aujourd'hui) → évite l'accumulation infinie + respecte la vie privée.
--  Prérequis : etape3-gps.sql (table positions).
--  FACULTATIF : si pg_cron n'est pas disponible sur ton offre, tu peux ignorer
--  ce fichier ; tu peux aussi lancer la ligne DELETE à la main de temps en temps.
-- =====================================================================

-- Active pg_cron si l'offre le permet, puis planifie la purge. Si l'extension
-- n'est pas disponible, l'installation continue et affiche seulement un NOTICE.
do $outer$
begin
  begin
    execute 'create extension if not exists pg_cron';
  exception when others then
    raise notice 'pg_cron indisponible : purge automatique non activée (%)', sqlerrm;
  end;

  if to_regnamespace('cron') is null then
    return;
  end if;

  if exists (select 1 from cron.job where jobname = 'purge-positions-2j') then
    perform cron.unschedule('purge-positions-2j');
  end if;
  perform cron.schedule(
    'purge-positions-2j',
    '0 3 * * *',
    $job$delete from public.positions where recorded_at < now() - interval '2 days'$job$
  );
end
$outer$;

-- Vérifier :   select jobname, schedule, active from cron.job;
-- Débrancher : select cron.unschedule('purge-positions-2j');
-- Purge manuelle immédiate :
--   delete from public.positions where recorded_at < now() - interval '2 days';
