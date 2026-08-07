import fs from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const normalizeSql=s=>s.replace(/\r\n/g,'\n').trim();
const installationSql=normalizeSql(
  fs.readFileSync(new URL('../supabase/INSTALLATION-COMPLETE.sql',import.meta.url),'utf8')
);
const sqlSources=[
  'etape1-base.sql',
  'etape2-plaques.sql',
  'etape3-gps.sql',
  'etape4-reglages-flotte.sql',
  'etape4-retention.sql',
  'etape5-calcul-patron.sql',
  'etape6-plaques-occupees.sql',
  'etape7-recette-periode.sql',
  'etape8-durcissement.sql',
  'etape9-quotas.sql',
  'etape10-grants.sql',
  'etape11-advisors.sql',
  'etape12-admin-recettes.sql',
  'etape13-carte-supervision.sql'
];
for(const file of sqlSources){
  const source=normalizeSql(fs.readFileSync(new URL(`../supabase/${file}`,import.meta.url),'utf8'));
  if(!installationSql.includes(source)) throw new Error(`INSTALLATION-COMPLETE.sql désynchronisé de ${file}`);
}

const sql=installationSql
  .replace(/create extension if not exists pgcrypto;/i,'');
const db=new PGlite();
await db.exec(`
  create role anon nologin;
  create role authenticated nologin;
  create schema auth;
  create table auth.users(id uuid primary key default gen_random_uuid());
  create function auth.uid() returns uuid language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
`);

for(let pass=1;pass<=2;pass++){
  try{ await db.exec(sql); }
  catch(error){
    console.error('PASS',pass,error.message);
    process.exit(1);
  }
  if(pass===1){
    await db.exec(`
      create policy member_reads_own_fleet on public.fleets
        for select to authenticated using (id = public.my_fleet());
      create policy own_profile_read on public.profiles
        for select to authenticated using (id = auth.uid());
      create policy own_carnet_all on public.carnets
        for all to authenticated
        using (user_id = auth.uid())
        with check (user_id = auth.uid());
      create policy superadmin_all_fleets on public.fleets
        for all using (public.my_role() = 'superadmin')
        with check (public.my_role() = 'superadmin');
      create policy superadmin_all_profiles on public.profiles
        for all using (public.my_role() = 'superadmin')
        with check (public.my_role() = 'superadmin');
    `);
  }
}

const tables=await db.query(`
  select table_name from information_schema.tables
  where table_schema='public' order by table_name
`);
const policies=await db.query(`select count(*)::int as n from pg_policies where schemaname='public'`);
const functions=await db.query(`
  select proname, prosecdef from pg_proc
  where proname in ('my_role','my_fleet','my_role_sd','carnet_periode','plates_enforce_max','positions_live','admin_ride_mutation')
  order by proname
`);
const rls=await db.query(`
  select relname, relrowsecurity from pg_class
  where relname in ('fleets','profiles','carnets','plates','plate_sessions','positions','fleet_config')
  order by relname
`);
const legacyPolicies=await db.query(`
  select policyname from pg_policies
  where schemaname='public'
    and policyname in (
      'member_reads_own_fleet','own_profile_read','own_carnet_all',
      'superadmin_all_fleets','superadmin_all_profiles'
    )
`);
const publicTargetPolicies=await db.query(`
  select policyname from pg_policies
  where schemaname='public' and 'public' = any(roles)
`);
const triggerFunctionHardening=await db.query(`
  select
    proname,
    coalesce(array_to_string(proconfig, ','),'') as config,
    has_function_privilege('anon', oid, 'EXECUTE') as anon_execute,
    has_function_privilege('authenticated', oid, 'EXECUTE') as authenticated_execute
  from pg_proc
  where pronamespace='public'::regnamespace
    and proname in ('plate_session_lock_cols','profile_lock_scope','plates_enforce_max')
  order by proname
`);
const adminMutationPrivileges=await db.query(`
  select
    has_function_privilege('anon', 'public.admin_ride_mutation(text,uuid,date,text,jsonb)', 'EXECUTE') as anon_execute,
    has_function_privilege('authenticated', 'public.admin_ride_mutation(text,uuid,date,text,jsonb)', 'EXECUTE') as authenticated_execute
`);
const liveMapIndex=await db.query(`
  select indexdef from pg_indexes
  where schemaname='public' and indexname='positions_live_session_time'
`);

if(tables.rows.length<7) throw new Error('tables manquantes');
if(Number(policies.rows[0].n)<15) throw new Error('policies manquantes');
if(functions.rows.length!==7 || functions.rows.some(x=>!x.prosecdef)) throw new Error('fonctions privilégiées incorrectes');
if(rls.rows.length!==7 || rls.rows.some(x=>!x.relrowsecurity)) throw new Error('RLS manquante');
if(legacyPolicies.rows.length) throw new Error('anciennes policies permissives encore actives');
if(publicTargetPolicies.rows.length) throw new Error('policy applicative encore ciblée sur public');
if(
  liveMapIndex.rows.length!==1
  || !/\(driver_id, plate_id, fleet_id, recorded_at desc, id desc\)/i.test(liveMapIndex.rows[0].indexdef)
) throw new Error('index composite de la carte live manquant');
if(
  triggerFunctionHardening.rows.length!==3
  || triggerFunctionHardening.rows.some(x=>x.anon_execute || x.authenticated_execute)
  || !triggerFunctionHardening.rows
    .find(x=>x.proname==='plate_session_lock_cols')
    ?.config.includes('search_path=public, pg_temp')
) throw new Error('fonctions trigger insuffisamment protégées');
if(adminMutationPrivileges.rows[0].anon_execute || !adminMutationPrivileges.rows[0].authenticated_execute) {
  throw new Error('permissions RPC de correction de course incorrectes');
}

const ids={
  fa:'00000000-0000-0000-0000-00000000000a',
  fb:'00000000-0000-0000-0000-00000000000b',
  pa:'10000000-0000-0000-0000-00000000000a',
  pb:'10000000-0000-0000-0000-00000000000b',
  sa:'10000000-0000-0000-0000-000000000009',
  da:'20000000-0000-0000-0000-00000000000a',
  db:'20000000-0000-0000-0000-00000000000b',
  dc:'20000000-0000-0000-0000-00000000000c',
  pla:'30000000-0000-0000-0000-00000000000a',
  plb:'30000000-0000-0000-0000-00000000000b',
  plc:'30000000-0000-0000-0000-00000000000c',
  pld:'30000000-0000-0000-0000-00000000000d',
  psf:'40000000-0000-0000-0000-00000000000a',
  psp:'40000000-0000-0000-0000-00000000000b',
};
await db.exec(`
  insert into auth.users(id) values
    ('${ids.pa}'),('${ids.pb}'),('${ids.sa}'),('${ids.da}'),('${ids.db}'),('${ids.dc}');
  insert into public.fleets(id,name) values ('${ids.fa}','A'),('${ids.fb}','B');
  insert into public.profiles(id,username,display_name,role,fleet_id) values
    ('${ids.pa}','pa','Patron A','patron','${ids.fa}'),
    ('${ids.pb}','pb','Patron B','patron','${ids.fb}'),
    ('${ids.sa}','sa','Super Admin','superadmin',null),
    ('${ids.da}','da','Driver A','chauffeur','${ids.fa}'),
    ('${ids.db}','db','Driver B','chauffeur','${ids.fb}'),
    ('${ids.dc}','dc','Driver C','chauffeur','${ids.fa}');
  insert into public.plates(id,fleet_id,label) values
    ('${ids.pla}','${ids.fa}','A-1'),('${ids.plb}','${ids.fb}','B-1'),
    ('${ids.plc}','${ids.fa}','A-2'),('${ids.pld}','${ids.fa}','A-3');
  insert into public.plate_sessions(plate_id,driver_id,fleet_id,started_at) values
    ('${ids.pla}','${ids.da}','${ids.fa}',now()-interval '1 hour'),
    ('${ids.plb}','${ids.db}','${ids.fb}',now()-interval '1 hour'),
    ('${ids.plc}','${ids.dc}','${ids.fa}',now()-interval '1 hour');
  insert into public.positions(driver_id,fleet_id,plate_id,lat,lng) values
    ('${ids.da}','${ids.fa}','${ids.pla}',50.85,4.35),
    ('${ids.db}','${ids.fb}','${ids.plb}',50.86,4.36);
  insert into public.carnets(user_id,data) values
    ('${ids.da}','{"version":2,"deletedRideIds":[],"sources":[{"id":"prive","name":"Course privée","rate":10}],"days":{"2026-07-28":{"rides":[{"id":"ride-a","t":"10:15","src":"prive","srcName":"Course privée","pay":"cash","amt":50,"rate":10}],"charges":[]}}}'),
    ('${ids.db}','{"days":{"2026-07-28":{"rides":[]}}}');
`);

await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);
const patronProfiles=await db.query(`select username from public.profiles order by username`);
const patronPositions=await db.query(`select driver_id from public.positions`);
const patronOtherCarnet=await db.query(`select public.carnet_periode('${ids.db}','2026-07-01','2026-07-31') as data`);
if(patronProfiles.rows.map(x=>x.username).join(',')!=='da,dc,pa') throw new Error('fuite profiles inter-flotte');
if(patronPositions.rows.length!==1 || patronPositions.rows[0].driver_id!==ids.da) throw new Error('fuite positions inter-flotte');
if(patronOtherCarnet.rows[0].data!==null) throw new Error('fuite carnet inter-flotte');

await db.exec('reset role');
await db.exec(`update public.fleets set opt_recettes=false where id='${ids.fa}'`);
await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);
const disabledRecettes=await db.query(`
  select public.carnet_periode('${ids.da}','2026-07-01','2026-07-31') as data
`);
if(disabledRecettes.rows[0].data!==null) throw new Error('recettes encore visibles après retrait de l\'option');

await db.exec('reset role');
await db.exec(`
  update public.fleets
  set opt_recettes=true,opt_gps_live=false,opt_replay=false
  where id='${ids.fa}'
`);
await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);
const disabledGpsRows=await db.query(`select id from public.positions`);
const disabledGpsRpc=await db.query(`select plate_id from public.positions_live('${ids.fa}',3)`);
if(disabledGpsRows.rows.length!==0 || disabledGpsRpc.rows.length!==0) {
  throw new Error('positions encore visibles après retrait des options GPS');
}

await db.exec('reset role');
await db.exec(`
  update public.fleets
  set opt_gps_live=true,opt_replay=true
  where id='${ids.fa}'
`);
await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);
const pendingGps=await db.query(`
  select driver_id,lat from public.positions_live('${ids.fa}',3)
  where driver_id='${ids.dc}'
`);
if(pendingGps.rows.length!==1 || pendingGps.rows[0].lat!==null) {
  throw new Error('chauffeur actif sans point GPS absent de la carte');
}
await db.exec('reset role');
await db.exec(`
  insert into public.positions(driver_id,fleet_id,plate_id,lat,lng,recorded_at)
  select '${ids.da}','${ids.fa}','${ids.pla}',50.85,4.35,now()-(n||' seconds')::interval
  from generate_series(1,45) n;
  insert into public.positions(driver_id,fleet_id,plate_id,lat,lng,recorded_at)
  values ('${ids.dc}','${ids.fa}','${ids.plc}',50.84,4.34,now()-interval '9 minutes');
`);
await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);
const liveOwnFleet=await db.query(`
  select plate_id,driver_id from public.positions_live('${ids.fa}',3)
`);
const liveOtherFleet=await db.query(`
  select plate_id from public.positions_live('${ids.fb}',3)
`);
if(
  liveOwnFleet.rows.length!==4
  || !liveOwnFleet.rows.some(x=>x.driver_id===ids.dc && x.plate_id===ids.plc)
) {
  throw new Error('carte live limitée globalement au lieu de chaque chauffeur');
}
if(liveOtherFleet.rows.length!==0) throw new Error('RPC carte live inter-flotte');

let patronMutatedRide=false;
try{
  await db.query(`select public.admin_ride_mutation(
    'delete','${ids.da}','2026-07-28','ride-a',null
  )`);
  patronMutatedRide=true;
}catch{}
if(patronMutatedRide) throw new Error('patron autorisé à corriger une course');

await db.exec('reset role');
await db.exec(`select set_config('request.jwt.claim.sub','${ids.sa}',false); set role authenticated;`);
const networkDrivers=await db.query(`
  select distinct driver_id from public.positions_live(null,1) order by driver_id
`);
if(networkDrivers.rows.map(x=>x.driver_id).join(',')!==[ids.da,ids.db,ids.dc].sort().join(',')) {
  throw new Error('carte super-admin incomplète sur toutes les flottes');
}
const editedRide=await db.query(`select public.admin_ride_mutation(
  'update','${ids.da}','2026-07-28','ride-a',
  '{"t":"10:30","src":"prive","srcName":"Course privée","pay":"sumup","amt":75.25,"rate":10}'::jsonb
) as result`);
if(editedRide.rows[0].result?.ride?.amt!==75.25 || editedRide.rows[0].result?.ride?.pay!=='sumup') {
  throw new Error('correction de course super-admin non appliquée');
}
const editedCarnet=await db.query(`
  select public.carnet_periode(
    '${ids.da}','2026-07-28','2026-07-28'
  )->'days'->'2026-07-28'->'rides'->0 as ride
`);
if(editedCarnet.rows[0].ride.amt!==75.25 || editedCarnet.rows[0].ride.pay!=='sumup') {
  throw new Error('carnet non mis à jour après correction');
}
let auditExposed=false;
try{ await db.query(`select * from private.carnet_audit`); auditExposed=true; }catch{}
if(auditExposed) throw new Error('journal privé lisible via authenticated');
const deletedRide=await db.query(`select public.admin_ride_mutation(
  'delete','${ids.da}','2026-07-28','ride-a',null
) as result`);
if(deletedRide.rows[0].result?.action!=='delete') throw new Error('suppression de course non appliquée');
await db.exec('reset role');
const deletedCarnet=await db.query(`
  select
    jsonb_array_length(data->'days'->'2026-07-28'->'rides') as rides,
    data->'deletedRideIds' @> '["ride-a"]'::jsonb as tombstone
  from public.carnets where user_id='${ids.da}'
`);
const auditRows=await db.query(`select action from private.carnet_audit order by created_at,id`);
if(Number(deletedCarnet.rows[0].rides)!==0 || !deletedCarnet.rows[0].tombstone) {
  throw new Error('course supprimée susceptible de réapparaître hors ligne');
}
if(auditRows.rows.map(x=>x.action).join(',')!=='ride_update,ride_delete') {
  throw new Error('audit des corrections de course incomplet');
}

await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);

let elevated=false;
try{ await db.exec(`update public.profiles set role='patron' where id='${ids.da}'`); elevated=true; }catch{}
if(elevated) throw new Error('élévation chauffeur par patron');
let identityChanged=false;
try{ await db.exec(`update public.profiles set username='detourne' where id='${ids.da}'`); identityChanged=true; }catch{}
if(identityChanged) throw new Error('identité chauffeur réécrite par patron');
await db.exec(`update public.profiles set display_name='Chauffeur A' where id='${ids.da}'`);

let patronTookPlate=false;
try{
  await db.exec(`insert into public.plate_sessions(plate_id,driver_id,fleet_id)
    values ('${ids.pld}','${ids.pa}','${ids.fa}')`);
  patronTookPlate=true;
}catch{}
if(patronTookPlate) throw new Error('patron autorisé à se déclarer chauffeur');

await db.exec('reset role');
await db.exec(`insert into public.plate_sessions(id,plate_id,driver_id,fleet_id)
  values ('${ids.psp}','${ids.pld}','${ids.pa}','${ids.fa}')`);
await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);
let patronGps=false;
try{
  await db.exec(`insert into public.positions(driver_id,fleet_id,plate_id,lat,lng)
    values ('${ids.pa}','${ids.fa}','${ids.pld}',50.85,4.35)`);
  patronGps=true;
}catch{}
if(patronGps) throw new Error('patron autorisé à injecter une position chauffeur');
await db.exec('reset role');

await db.exec(`select set_config('request.jwt.claim.sub','${ids.da}',false); set role authenticated;`);
let forged=false;
try{
  await db.exec(`insert into public.positions(driver_id,fleet_id,plate_id,lat,lng)
    values ('${ids.da}','${ids.fb}','${ids.plb}',50,4)`);
  forged=true;
}catch{}
if(forged) throw new Error('position forgée inter-flotte');
let invalidCoordinates=false;
try{
  await db.exec(`insert into public.positions(driver_id,fleet_id,plate_id,lat,lng)
    values ('${ids.da}','${ids.fa}','${ids.pla}',200,4)`);
  invalidCoordinates=true;
}catch{}
if(invalidCoordinates) throw new Error('coordonnées GPS impossibles acceptées');
let futurePosition=false;
try{
  await db.exec(`insert into public.positions(driver_id,fleet_id,plate_id,lat,lng,recorded_at)
    values ('${ids.da}','${ids.fa}','${ids.pla}',50,4,now()+interval '1 day')`);
  futurePosition=true;
}catch{}
if(futurePosition) throw new Error('position GPS future acceptée');
await db.exec(`update public.plate_sessions
  set ended_at=now()-interval '30 minutes'
  where driver_id='${ids.da}'`);
await db.exec(`insert into public.positions(driver_id,fleet_id,plate_id,lat,lng,recorded_at)
  values ('${ids.da}','${ids.fa}','${ids.pla}',50.84,4.34,now()-interval '45 minutes')`);
let sessionRetimed=false;
try{
  await db.exec(`update public.plate_sessions
    set ended_at=now()+interval '1 day'
    where driver_id='${ids.da}'`);
  sessionRetimed=true;
}catch{}
if(sessionRetimed) throw new Error('session clôturée antidatée ou prolongée');
let outsideSession=false;
try{
  await db.exec(`insert into public.positions(driver_id,fleet_id,plate_id,lat,lng,recorded_at)
    values ('${ids.da}','${ids.fa}','${ids.pla}',50.84,4.34,now()-interval '3 hours')`);
  outsideSession=true;
}catch{}
if(outsideSession) throw new Error('position GPS hors session acceptée');

await db.exec(`insert into public.plate_sessions(
    id,plate_id,driver_id,fleet_id,started_at,ended_at
  ) values (
    '${ids.psf}','${ids.pla}','${ids.da}','${ids.fa}',
    now()-interval '2 days',now()-interval '1 day'
  )`);
const normalizedSession=await db.query(`
  select started_at > now()-interval '1 minute' as fresh,
         ended_at is null as open
  from public.plate_sessions where id='${ids.psf}'
`);
if(!normalizedSession.rows[0]?.fresh || !normalizedSession.rows[0]?.open) {
  throw new Error('horodatage de session forgé accepté');
}
await db.exec(`update public.plate_sessions set ended_at=now() where id='${ids.psf}'`);
await db.exec('reset role');

await db.exec(`update public.fleets set suspended=true where id='${ids.fa}'`);
await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);
const suspendedPatron=await db.query(`
  select public.my_role() as role, public.my_fleet() as fleet
`);
const suspendedPatronPlates=await db.query(`select id from public.plates`);
const suspendedPatronCarnet=await db.query(`
  select public.carnet_periode('${ids.da}','2026-07-01','2026-07-31') as data
`);
const suspendedPatronMap=await db.query(`
  select plate_id from public.positions_live('${ids.fa}',3)
`);
if(suspendedPatron.rows[0].role!==null || suspendedPatron.rows[0].fleet!==null) {
  throw new Error('identité patron encore active sur flotte suspendue');
}
if(suspendedPatronPlates.rows.length!==0) throw new Error('plaques visibles sur flotte suspendue');
if(suspendedPatronCarnet.rows[0].data!==null) throw new Error('carnet visible sur flotte suspendue');
if(suspendedPatronMap.rows.length!==0) throw new Error('carte visible sur flotte suspendue');
await db.exec('reset role');

await db.exec(`select set_config('request.jwt.claim.sub','${ids.da}',false); set role authenticated;`);
const suspendedDriver=await db.query(`select public.my_role() as role`);
const suspendedDriverPositions=await db.query(`select id from public.positions`);
const suspendedDriverSessions=await db.query(`select id from public.plate_sessions`);
const suspendedDriverCarnet=await db.query(`select user_id from public.carnets`);
const suspendedDriverRpc=await db.query(`
  select public.carnet_periode('${ids.da}','2026-07-01','2026-07-31') as data
`);
if(suspendedDriver.rows[0].role!==null) throw new Error('chauffeur encore actif sur flotte suspendue');
if(suspendedDriverPositions.rows.length!==0) throw new Error('positions visibles sur flotte suspendue');
if(suspendedDriverSessions.rows.length!==0) throw new Error('sessions clôturées visibles sur flotte suspendue');
if(suspendedDriverCarnet.rows.length!==0) throw new Error('carnet visible sur flotte suspendue');
if(suspendedDriverRpc.rows[0].data!==null) throw new Error('RPC carnet visible sur flotte suspendue');
let suspendedTake=false;
try{
  await db.exec(`insert into public.plate_sessions(plate_id,driver_id,fleet_id)
    values ('${ids.pla}','${ids.da}','${ids.fa}')`);
  suspendedTake=true;
}catch{}
if(suspendedTake) throw new Error('prise de plaque autorisée sur flotte suspendue');
await db.exec('reset role');

await db.exec('set role anon');
let anonRead=false;
try{ await db.query('select * from public.positions'); anonRead=true; }catch{}
if(anonRead) throw new Error('lecture anon autorisée');
let anonMap=false;
try{ await db.query('select * from public.positions_live(null,3)'); anonMap=true; }catch{}
if(anonMap) throw new Error('RPC carte live autorisé à anon');
await db.exec('reset role');

console.log(JSON.stringify({
  passes:2,
  sourcesInSync:true,
  tables:tables.rows.map(x=>x.table_name),
  policies:Number(policies.rows[0].n),
  securityDefinerFunctions:functions.rows.map(x=>x.proname),
  rls:true,
  multiTenantIsolation:true,
  anonDenied:true,
  roleEscalationDenied:true,
  profileScopeLocked:true,
  legacyPoliciesRemoved:true,
  policiesAuthenticatedOnly:true,
  triggerFunctionsHardened:true,
  authUidInitPlanOptimized:true,
  driverRoleEnforced:true,
  gpsInputValidated:true,
  liveMapPerDriver:true,
  liveMapPendingDriver:true,
  liveMapCompositeIndex:true,
  adminRideMutation:true,
  privateRideAudit:true,
  fleetOptionsEnforced:true,
  offlineGpsReplay:true,
  sessionTimesLocked:true,
  suspendedFleetDenied:true
},null,2));
