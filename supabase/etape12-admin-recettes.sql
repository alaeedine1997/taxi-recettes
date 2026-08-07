-- =====================================================================
-- ETAPE 12 - Correction des courses par le super-admin
-- Mutation atomique d'une seule course + audit prive immuable.
-- Idempotente et sans cle service_role.
-- =====================================================================

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.carnet_audit (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid not null,
  driver_id   uuid not null,
  action      text not null check (action in ('ride_update', 'ride_delete')),
  ride_day    date not null,
  ride_id     text not null,
  before_data jsonb not null,
  after_data  jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists carnet_audit_driver_time
  on private.carnet_audit (driver_id, created_at desc);
alter table private.carnet_audit enable row level security;
revoke all on table private.carnet_audit from public, anon, authenticated;

create or replace function public.admin_ride_mutation(
  p_action  text,
  p_driver  uuid,
  p_day     date,
  p_ride_id text,
  p_ride    jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_data       jsonb;
  v_day_key    text := to_char(p_day, 'YYYY-MM-DD');
  v_day        jsonb;
  v_rides      jsonb;
  v_new_rides  jsonb;
  v_deleted    jsonb;
  v_before     jsonb;
  v_after      jsonb;
  v_amount     numeric;
  v_rate       numeric;
  v_cash       numeric;
  v_time       text;
  v_source     text;
  v_source_name text;
  v_payment    text;
  v_updated_at timestamptz;
begin
  if public.my_role_sd() is distinct from 'superadmin' then
    raise exception using errcode = '42501', message = 'admin_required';
  end if;

  if p_action is null
     or p_action not in ('update', 'delete')
     or p_driver is null
     or p_day is null
     or p_ride_id is null
     or length(p_ride_id) < 1
     or length(p_ride_id) > 160 then
    raise exception using errcode = '22023', message = 'ride_request_invalid';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_driver and p.role = 'chauffeur'
  ) then
    raise exception using errcode = '22023', message = 'driver_not_found';
  end if;

  select c.data
  into v_data
  from public.carnets c
  where c.user_id = p_driver
  for update;

  if v_data is null then
    raise exception using errcode = 'P0002', message = 'carnet_not_found';
  end if;

  v_day := v_data->'days'->v_day_key;
  if jsonb_typeof(v_day) <> 'object'
     or jsonb_typeof(v_day->'rides') <> 'array' then
    raise exception using errcode = 'P0002', message = 'ride_not_found';
  end if;
  v_rides := v_day->'rides';

  select e.value
  into v_before
  from jsonb_array_elements(v_rides) e(value)
  where e.value->>'id' = p_ride_id
  limit 1;

  if v_before is null then
    raise exception using errcode = 'P0002', message = 'ride_not_found';
  end if;

  if p_action = 'update' then
    if p_ride is null or jsonb_typeof(p_ride) <> 'object' then
      raise exception using errcode = '22023', message = 'ride_invalid';
    end if;

    begin
      v_amount := round((p_ride->>'amt')::numeric, 2);
      v_rate := round(coalesce((p_ride->>'rate')::numeric, 0), 2);
      v_cash := round(coalesce((p_ride->>'cash')::numeric, 0), 2);
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception using errcode = '22023', message = 'ride_invalid';
    end;

    v_time := coalesce(p_ride->>'t', '');
    v_source := coalesce(p_ride->>'src', '');
    v_source_name := coalesce(p_ride->>'srcName', '');
    v_payment := coalesce(p_ride->>'pay', '');

    if v_amount is null or v_amount <= 0 or v_amount > 100000
       or v_rate < 0 or v_rate > 100
       or (v_time <> '' and v_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
       or length(v_source) < 1 or length(v_source) > 80
       or length(v_source_name) > 120
       or v_payment not in ('app', 'cash', 'sumup', 'cheque', 'appcash')
       or (v_payment = 'appcash' and (v_cash < 0 or v_cash > v_amount)) then
      raise exception using errcode = '22023', message = 'ride_invalid';
    end if;

    if v_payment in ('app', 'appcash') then
      v_rate := 0;
    end if;

    v_after := v_before || jsonb_build_object(
      'id', p_ride_id,
      't', v_time,
      'src', v_source,
      'srcName', v_source_name,
      'pay', v_payment,
      'amt', v_amount,
      'rate', v_rate
    );
    if v_payment = 'appcash' then
      v_after := v_after || jsonb_build_object('cash', v_cash);
    else
      v_after := v_after - 'cash';
    end if;

    select jsonb_agg(
      case when e.value->>'id' = p_ride_id then v_after else e.value end
      order by e.ord
    )
    into v_new_rides
    from jsonb_array_elements(v_rides) with ordinality e(value, ord);
  else
    select coalesce(jsonb_agg(e.value order by e.ord), '[]'::jsonb)
    into v_new_rides
    from jsonb_array_elements(v_rides) with ordinality e(value, ord)
    where e.value->>'id' is distinct from p_ride_id;

    v_deleted := case
      when jsonb_typeof(v_data->'deletedRideIds') = 'array'
        then v_data->'deletedRideIds'
      else '[]'::jsonb
    end;
    if not v_deleted @> jsonb_build_array(p_ride_id) then
      v_deleted := v_deleted || jsonb_build_array(p_ride_id);
    end if;
    select coalesce(jsonb_agg(x.value order by x.ord), '[]'::jsonb)
    into v_deleted
    from (
      select e.value, e.ord
      from jsonb_array_elements(v_deleted) with ordinality e(value, ord)
      where jsonb_typeof(e.value) = 'string'
      order by e.ord desc
      limit 5000
    ) x;
    v_data := jsonb_set(v_data, '{deletedRideIds}', v_deleted, true);
  end if;

  v_data := jsonb_set(
    v_data,
    array['days', v_day_key, 'rides'],
    coalesce(v_new_rides, '[]'::jsonb),
    false
  );

  update public.carnets
  set data = v_data,
      updated_at = now(),
      device = 'superadmin'
  where user_id = p_driver
  returning updated_at into v_updated_at;

  insert into private.carnet_audit (
    actor_id, driver_id, action, ride_day, ride_id, before_data, after_data
  ) values (
    auth.uid(), p_driver, 'ride_' || p_action, p_day, p_ride_id, v_before, v_after
  );

  return jsonb_build_object(
    'ok', true,
    'action', p_action,
    'ride', coalesce(v_after, v_before),
    'updated_at', v_updated_at
  );
end
$$;

revoke all on function public.admin_ride_mutation(text, uuid, date, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.admin_ride_mutation(text, uuid, date, text, jsonb)
  to authenticated;

notify pgrst, 'reload schema';
