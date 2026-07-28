import fs from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const sql=fs.readFileSync(new URL('../supabase/INSTALLATION-COMPLETE.sql',import.meta.url),'utf8')
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
}

const tables=await db.query(`
  select table_name from information_schema.tables
  where table_schema='public' order by table_name
`);
const policies=await db.query(`select count(*)::int as n from pg_policies where schemaname='public'`);
const functions=await db.query(`
  select proname, prosecdef from pg_proc
  where proname in ('my_role','my_fleet','my_role_sd','carnet_periode','plates_enforce_max')
  order by proname
`);
const rls=await db.query(`
  select relname, relrowsecurity from pg_class
  where relname in ('fleets','profiles','carnets','plates','plate_sessions','positions','fleet_config')
  order by relname
`);

if(tables.rows.length<7) throw new Error('tables manquantes');
if(Number(policies.rows[0].n)<15) throw new Error('policies manquantes');
if(functions.rows.length!==5 || functions.rows.some(x=>!x.prosecdef)) throw new Error('fonctions privilégiées incorrectes');
if(rls.rows.length!==7 || rls.rows.some(x=>!x.relrowsecurity)) throw new Error('RLS manquante');

const ids={
  fa:'00000000-0000-0000-0000-00000000000a',
  fb:'00000000-0000-0000-0000-00000000000b',
  pa:'10000000-0000-0000-0000-00000000000a',
  pb:'10000000-0000-0000-0000-00000000000b',
  da:'20000000-0000-0000-0000-00000000000a',
  db:'20000000-0000-0000-0000-00000000000b',
  pla:'30000000-0000-0000-0000-00000000000a',
  plb:'30000000-0000-0000-0000-00000000000b',
};
await db.exec(`
  insert into auth.users(id) values ('${ids.pa}'),('${ids.pb}'),('${ids.da}'),('${ids.db}');
  insert into public.fleets(id,name) values ('${ids.fa}','A'),('${ids.fb}','B');
  insert into public.profiles(id,username,display_name,role,fleet_id) values
    ('${ids.pa}','pa','Patron A','patron','${ids.fa}'),
    ('${ids.pb}','pb','Patron B','patron','${ids.fb}'),
    ('${ids.da}','da','Driver A','chauffeur','${ids.fa}'),
    ('${ids.db}','db','Driver B','chauffeur','${ids.fb}');
  insert into public.plates(id,fleet_id,label) values
    ('${ids.pla}','${ids.fa}','A-1'),('${ids.plb}','${ids.fb}','B-1');
  insert into public.plate_sessions(plate_id,driver_id,fleet_id,started_at) values
    ('${ids.pla}','${ids.da}','${ids.fa}',now()-interval '1 hour'),
    ('${ids.plb}','${ids.db}','${ids.fb}',now()-interval '1 hour');
  insert into public.positions(driver_id,fleet_id,plate_id,lat,lng) values
    ('${ids.da}','${ids.fa}','${ids.pla}',50.85,4.35),
    ('${ids.db}','${ids.fb}','${ids.plb}',50.86,4.36);
  insert into public.carnets(user_id,data) values
    ('${ids.da}','{"days":{"2026-07-28":{"rides":[]}}}'),
    ('${ids.db}','{"days":{"2026-07-28":{"rides":[]}}}');
`);

await db.exec(`select set_config('request.jwt.claim.sub','${ids.pa}',false); set role authenticated;`);
const patronProfiles=await db.query(`select username from public.profiles order by username`);
const patronPositions=await db.query(`select driver_id from public.positions`);
const patronOtherCarnet=await db.query(`select public.carnet_periode('${ids.db}','2026-07-01','2026-07-31') as data`);
if(patronProfiles.rows.map(x=>x.username).join(',')!=='da,pa') throw new Error('fuite profiles inter-flotte');
if(patronPositions.rows.length!==1 || patronPositions.rows[0].driver_id!==ids.da) throw new Error('fuite positions inter-flotte');
if(patronOtherCarnet.rows[0].data!==null) throw new Error('fuite carnet inter-flotte');
let elevated=false;
try{ await db.exec(`update public.profiles set role='patron' where id='${ids.da}'`); elevated=true; }catch{}
if(elevated) throw new Error('élévation chauffeur par patron');
let identityChanged=false;
try{ await db.exec(`update public.profiles set username='detourne' where id='${ids.da}'`); identityChanged=true; }catch{}
if(identityChanged) throw new Error('identité chauffeur réécrite par patron');
await db.exec(`update public.profiles set display_name='Chauffeur A' where id='${ids.da}'`);
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
let outsideSession=false;
try{
  await db.exec(`insert into public.positions(driver_id,fleet_id,plate_id,lat,lng,recorded_at)
    values ('${ids.da}','${ids.fa}','${ids.pla}',50.84,4.34,now()-interval '3 hours')`);
  outsideSession=true;
}catch{}
if(outsideSession) throw new Error('position GPS hors session acceptée');
await db.exec('reset role');

await db.exec('set role anon');
let anonRead=false;
try{ await db.query('select * from public.positions'); anonRead=true; }catch{}
if(anonRead) throw new Error('lecture anon autorisée');
await db.exec('reset role');

console.log(JSON.stringify({
  passes:2,
  tables:tables.rows.map(x=>x.table_name),
  policies:Number(policies.rows[0].n),
  securityDefinerFunctions:functions.rows.map(x=>x.proname),
  rls:true,
  multiTenantIsolation:true,
  anonDenied:true,
  roleEscalationDenied:true,
  profileScopeLocked:true,
  gpsInputValidated:true,
  offlineGpsReplay:true
},null,2));
