-- ÉTAPE 9 — Faire RESPECTER les quotas (max_plates) et l'option Recettes
-- À lancer dans l'éditeur SQL Supabase. Idempotent : relançable sans risque.
--
-- Jusqu'ici, « Plaques max » et l'option « Recettes » cochées par le super-admin
-- étaient purement décoratives : rien ne les faisait respecter côté serveur.

-- ---------------------------------------------------------------------------
-- 1) max_plates : on ne peut plus ajouter une plaque ACTIVE au-delà du quota.
--    (max_plates <= 0 = pas de limite. On compte les plaques ACTIVES : désactiver
--     une vieille plaque libère un emplacement.)
-- ---------------------------------------------------------------------------
create or replace function public.plates_enforce_max()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  maxp int;
  cnt  int;
begin
  if not coalesce(new.active, true) then
    return new;                       -- une plaque inactive ne consomme pas d'emplacement
  end if;
  select max_plates into maxp from public.fleets where id = new.fleet_id;
  if maxp is not null and maxp > 0 then
    select count(*) into cnt
      from public.plates
     where fleet_id = new.fleet_id
       and active
       and (tg_op = 'INSERT' or id <> new.id);   -- ne pas se compter soi-même en UPDATE
    if cnt >= maxp then
      raise exception 'Limite de plaques atteinte (max %) pour cette flotte', maxp
        using hint = 'limite_plaques';
    end if;
  end if;
  return new;
end
$$;

-- INSERT (ajout) ET UPDATE (réactivation d'une plaque) sont couverts.
drop trigger if exists plates_max_check on public.plates;
create trigger plates_max_check
  before insert or update of active, fleet_id on public.plates
  for each row execute function public.plates_enforce_max();

-- ---------------------------------------------------------------------------
-- 2) opt_recettes : un patron ne peut lire les carnets (via carnet_periode) que si
--    sa flotte a l'option débloquée. Le super-admin, lui, garde tout.
--    On re-crée la fonction (celle de l'étape 8) avec cette condition en plus.
-- ---------------------------------------------------------------------------
create or replace function public.carnet_periode(
  p_driver uuid,
  p_from   date,
  p_to     date
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'sources',   case when jsonb_typeof(c.data->'sources')   = 'array'
                      then c.data->'sources'   else '[]'::jsonb end,
    'fuelPerKm', case when jsonb_typeof(c.data->'fuelPerKm') = 'number'
                      then c.data->'fuelPerKm' else '0'::jsonb end,
    'days',      coalesce((
        select jsonb_object_agg(kv.key, kv.value)
        from jsonb_each(
               case when jsonb_typeof(c.data->'days') = 'object'
                    then c.data->'days' else '{}'::jsonb end
             ) kv
        where kv.key ~ '^\d{4}-\d{2}-\d{2}$'
          and kv.key >= to_char(p_from, 'YYYY-MM-DD')
          and kv.key <= to_char(p_to,   'YYYY-MM-DD')
      ), '{}'::jsonb)
  )
  from public.carnets c
  where c.user_id = p_driver
    and p_from <= p_to
    and (p_to - p_from) <= 92
    and exists (select 1 from public.profiles me where me.id = auth.uid() and me.active)
    and (
      public.my_role_sd() = 'superadmin'
      or (
        public.my_role_sd() = 'patron'
        and exists (
          select 1 from public.profiles p
          where p.id = p_driver
            and p.role::text = 'chauffeur'
            and p.fleet_id is not null
            and p.fleet_id = public.my_fleet()
        )
        -- NOUVEAU : l'option Recettes doit être débloquée et la flotte non suspendue
        and exists (
          select 1 from public.fleets f
          where f.id = public.my_fleet()
            and f.opt_recettes
            and not f.suspended
        )
      )
      or p_driver = auth.uid()
    )
$$;
revoke all on function public.carnet_periode(uuid, date, date) from public, anon;
grant execute on function public.carnet_periode(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';

-- Vérification :
-- select tgname from pg_trigger where tgrelid='public.plates'::regclass and not tgisinternal;
