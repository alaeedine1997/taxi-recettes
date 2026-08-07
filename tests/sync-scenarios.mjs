import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');

function extractFunction(source,name){
  const start=source.indexOf(`function ${name}(`);
  if(start<0) throw new Error(`fonction ${name} introuvable`);
  const open=source.indexOf('{',start);
  let depth=0;
  for(let i=open;i<source.length;i++){
    if(source[i]==='{') depth++;
    if(source[i]==='}'&&--depth===0) return source.slice(start,i+1);
  }
  throw new Error(`fonction ${name} incomplète`);
}

const carnetStart=html.indexOf('const carnet = (function(){');
const carnetEnd=html.indexOf('})();\ncarnetSyncHook',carnetStart);
if(carnetStart<0||carnetEnd<0) throw new Error('module carnet introuvable');
const carnetSource=html.slice(carnetStart,carnetEnd+5);
const mergeSource=extractFunction(html,'mergeDaysInto');

const STORE_KEY='taxiRecettesV1';
const SYNC_META='taxiSyncV1';
const userId='20000000-0000-0000-0000-00000000000a';
const dateKey='2026-07-28';
const clone=value=>JSON.parse(JSON.stringify(value));

function day(rides=[]){
  return {
    kmStart:null,kmEnd:null,openedAt:'08:00',closedAt:null,
    fieldUpdatedAt:{},rides:clone(rides),charges:[]
  };
}

function book(rides=[],syncUpdatedAt=0){
  return {
    version:2,syncUpdatedAt,deletedRideIds:[],deletedChargeIds:[],
    sources:[],days:{[dateKey]:day(rides)},activeDay:dateKey,
    fuelPerKm:0,taxi:{}
  };
}

class MemoryStorage {
  constructor(values={}){
    this.values=new Map(Object.entries(values));
    this.failKey=null;
  }
  getItem(key){ return this.values.has(key)?this.values.get(key):null; }
  setItem(key,value){
    if(this.failKey&&this.failKey(key)) throw new Error('quota');
    this.values.set(key,String(value));
  }
  removeItem(key){ this.values.delete(key); }
}

class FakePostgrest {
  constructor(data,updatedAt){
    this.row={user_id:userId,data:clone(data),updated_at:new Date(updatedAt).toISOString(),device:'test'};
    this.offline=false;
    this.requests=[];
  }
  async fetch(url,options={}){
    if(this.offline) throw new Error('offline');
    const parsed=new URL(url);
    const method=options.method||'GET';
    this.requests.push({method,path:parsed.pathname+parsed.search});
    if(method==='GET'){
      return response(200,this.row?[clone(this.row)]:[]);
    }
    if(method==='POST'){
      const incoming=JSON.parse(options.body)[0];
      if(this.row) return response(201,[]);
      this.row=clone(incoming);
      return response(201,[clone(this.row)]);
    }
    if(method==='PATCH'){
      const seen=(parsed.searchParams.get('updated_at')||'').replace(/^lte\./,'');
      if(!this.row||Date.parse(this.row.updated_at)>Date.parse(seen)) return response(200,[]);
      const incoming=JSON.parse(options.body);
      this.row={...this.row,...clone(incoming)};
      return response(200,[clone(this.row)]);
    }
    return response(405,{});
  }
}

function response(status,data){
  return {ok:status>=200&&status<300,status,json:async()=>clone(data)};
}

function normalized(value){
  const out=clone(value||{});
  out.version=2;
  out.syncUpdatedAt=Number(out.syncUpdatedAt)||0;
  out.deletedRideIds=Array.isArray(out.deletedRideIds)?out.deletedRideIds:[];
  out.deletedChargeIds=Array.isArray(out.deletedChargeIds)?out.deletedChargeIds:[];
  out.sources=Array.isArray(out.sources)?out.sources:[];
  out.days=out.days&&typeof out.days==='object'?out.days:{};
  out.taxi=out.taxi&&typeof out.taxi==='object'?out.taxi:{};
  out.fuelPerKm=Number(out.fuelPerKm)||0;
  return out;
}

function createDevice(server,initialDb,meta={}){
  const storage=new MemoryStorage({
    [STORE_KEY]:JSON.stringify(initialDb),
    [SYNC_META]:JSON.stringify(meta)
  });
  let nextTimer=1;
  const context=vm.createContext({
    console,JSON,Date,Math,Set,URL,encodeURIComponent,
    STORE_KEY,SYNC_META,SB_KEY:'publishable-test',SB_URL:'https://fake.supabase.test',
    localStorage:storage,
    navigator:{userAgent:'Node sync test'},
    db:clone(initialDb),
    persistedDb:clone(initialDb),
    normalizeDb:normalized,
    freshDb:()=>book([],0),
    renderAll:()=>{},
    toast:()=>{},
    setTimeout:()=>nextTimer++,
    clearTimeout:()=>{},
    auth:{
      ensureFresh:async()=>true,
      isLogged:()=>true,
      role:()=>'chauffeur',
      token:()=>'jwt-test',
      userId:()=>userId
    },
    fetch:(...args)=>server.fetch(...args)
  });
  new vm.Script(
    `${mergeSource}\n${carnetSource}\nglobalThis.__carnet=carnet;`,
    {filename:'index.html#carnet'}
  ).runInContext(context);
  return {context,storage,carnet:context.__carnet};
}

function ids(value){
  return value.days[dateKey].rides.map(ride=>ride.id).sort();
}

function readMeta(device){
  return JSON.parse(device.storage.getItem(SYNC_META)||'{}');
}

function assertInvariant(device,expectedUnsynced){
  const meta=readMeta(device);
  assert.equal(
    (Number(meta.localUpdatedAt)||0)>(Number(meta.lastSyncedAt)||0),
    expectedUnsynced,
    'invariant non-synchronisé'
  );
}

const baseT=Date.now()-60_000;
const initial=book([{id:'serveur',amt:10}],baseT);
const server=new FakePostgrest(initial,baseT);
const sharedMeta={ownerId:userId,localUpdatedAt:baseT,lastSyncedAt:baseT};
const phoneA=createDevice(server,initial,sharedMeta);
const phoneB=createDevice(server,initial,sharedMeta);

phoneA.context.db.days[dateKey].rides.push({id:'telephone-a',amt:12});
phoneA.carnet.schedulePush(baseT+1_000);
assertInvariant(phoneA,true);
assert.equal(await phoneA.carnet.flush(),true);
assertInvariant(phoneA,false);

phoneB.context.db.days[dateKey].rides.push({id:'telephone-b',amt:14});
phoneB.carnet.schedulePush(baseT+2_000);
assert.equal(await phoneB.carnet.flush(),true);
assert.deepEqual(ids(server.row.data),['serveur','telephone-a','telephone-b']);
assertInvariant(phoneB,false);

/* Login effectué hors-ligne : la saisie locale doit être fusionnée au retour. */
const loginServer=new FakePostgrest(book([{id:'compte',amt:20}],baseT),baseT);
loginServer.offline=true;
const guest=book([{id:'hors-ligne',amt:9}],baseT+5_000);
const loginDevice=createDevice(
  loginServer,guest,{ownerId:null,localUpdatedAt:baseT+5_000,lastSyncedAt:0}
);
await loginDevice.carnet.claim(userId);
assert.deepEqual(ids(loginDevice.context.db),['hors-ligne']);
assert.equal(readMeta(loginDevice).unverified,true);
loginServer.offline=false;
await loginDevice.carnet.pull();
assert.deepEqual(ids(loginServer.row.data),['compte','hors-ligne']);
assert.equal(Boolean(readMeta(loginDevice).unverified),false);
assertInvariant(loginDevice,false);

/* Une suppression locale ne doit pas ressusciter depuis un autre téléphone. */
const deleteServer=new FakePostgrest(book([{id:'a-supprimer',amt:30}],baseT),baseT);
const deleteDevice=createDevice(deleteServer,deleteServer.row.data,sharedMeta);
deleteDevice.context.db.days[dateKey].rides=[];
deleteDevice.context.db.deletedRideIds=['a-supprimer'];
deleteDevice.carnet.schedulePush(baseT+3_000);
deleteServer.row.data.days[dateKey].rides.push({id:'autre-telephone',amt:18});
deleteServer.row.updated_at=new Date(baseT+4_000).toISOString();
await deleteDevice.carnet.pull();
assert.deepEqual(ids(deleteServer.row.data),['autre-telephone']);
assertInvariant(deleteDevice,false);

/* Quota plein : la déconnexion est annulée si le backup ne peut pas être écrit. */
const quotaServer=new FakePostgrest(initial,baseT);
const quotaDevice=createDevice(
  quotaServer,book([{id:'non-synchronise',amt:25}],baseT+8_000),
  {ownerId:userId,localUpdatedAt:baseT+8_000,lastSyncedAt:baseT}
);
quotaDevice.storage.failKey=key=>key.includes('_backup_');
assert.equal(quotaDevice.carnet.release(),false);
assert.deepEqual(ids(quotaDevice.context.db),['non-synchronise']);
assertInvariant(quotaDevice,true);

/* Horloge en recul : toute nouvelle écriture dépasse quand même le dernier sync. */
phoneB.carnet.schedulePush(baseT-100_000);
assertInvariant(phoneB,true);
assert.ok(readMeta(phoneB).localUpdatedAt>readMeta(phoneB).lastSyncedAt);

/* Si taxiSyncV1 refuse l'écriture, le marqueur reste dans le carnet lui-même.
   Après redémarrage, la course doit donc encore partir vers le serveur. */
const splitServer=new FakePostgrest(book([{id:'avant',amt:11}],baseT),baseT);
const splitDevice=createDevice(splitServer,splitServer.row.data,sharedMeta);
splitDevice.context.db.days[dateKey].rides.push({id:'stockage-fractionne',amt:17});
splitDevice.storage.failKey=key=>key===SYNC_META;
splitDevice.carnet.schedulePush(baseT-100_000);
const persistedSplit=JSON.parse(splitDevice.storage.getItem(STORE_KEY));
const persistedSplitMeta=readMeta(splitDevice);
assert.ok(persistedSplit.syncUpdatedAt>persistedSplitMeta.lastSyncedAt);
const restartedSplit=createDevice(splitServer,persistedSplit,persistedSplitMeta);
assert.equal(await restartedSplit.carnet.flush(),true);
assert.deepEqual(ids(splitServer.row.data),['avant','stockage-fractionne']);

console.log(JSON.stringify({
  twoDevicesNoLoss:true,
  offlineLoginMerged:true,
  deletionNotResurrected:true,
  quotaLogoutBlocked:true,
  clockRollbackMonotone:true,
  splitStorageFailureRecovered:true,
  invariantChecked:true,
  fakePostgrestRequests:
    server.requests.length+loginServer.requests.length+deleteServer.requests.length+splitServer.requests.length
},null,2));
