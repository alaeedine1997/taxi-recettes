import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const driver=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const patron=fs.readFileSync(new URL('../patron.html',import.meta.url),'utf8');
const admin=fs.readFileSync(new URL('../admin.html',import.meta.url),'utf8');
const meter=fs.readFileSync(new URL('../android/app/src/main/java/be/taxirecettes/copilote/Meter.kt',import.meta.url),'utf8');
const meterMath=fs.readFileSync(new URL('../android/app/src/main/java/be/taxirecettes/copilote/MeterMath.kt',import.meta.url),'utf8');
const taxiBridge=fs.readFileSync(
  new URL('../android/app/src/main/java/be/taxirecettes/copilote/TaxiBridge.kt',import.meta.url),'utf8'
);
const mainActivity=fs.readFileSync(
  new URL('../android/app/src/main/java/be/taxirecettes/copilote/MainActivity.kt',import.meta.url),'utf8'
);
const androidManifest=fs.readFileSync(
  new URL('../android/app/src/main/AndroidManifest.xml',import.meta.url),'utf8'
);
const androidGradle=fs.readFileSync(
  new URL('../android/app/build.gradle.kts',import.meta.url),'utf8'
);
const accountFunction=fs.readFileSync(
  new URL('../supabase/functions/rapid-function/index.ts',import.meta.url),'utf8'
);

function referenceNet(amount,rate,pay='cash',appCash=false){
  if(pay==='app'||pay==='appcash'||appCash) return amount;
  const bounded=Math.min(100,Math.max(0,rate));
  return Math.round(Math.round(amount*100)*(10000-Math.round(bounded*100))/10000)/100;
}

function extractFunction(source,name){
  let start=source.indexOf(`function ${name}(`);
  if(start<0) throw new Error(`fonction ${name} introuvable`);
  if(source.slice(start-6,start)==='async ') start-=6;
  const open=source.indexOf('{',start);
  let depth=0, quote='', lineComment=false, blockComment=false, escaped=false;
  for(let i=open;i<source.length;i++){
    const ch=source[i], next=source[i+1];
    if(lineComment){ if(ch==='\n') lineComment=false; continue; }
    if(blockComment){ if(ch==='*'&&next==='/'){ blockComment=false;i++; } continue; }
    if(quote){
      if(escaped){ escaped=false; continue; }
      if(ch==='\\'){ escaped=true; continue; }
      if(ch===quote) quote='';
      continue;
    }
    if(ch==='/'&&next==='/'){ lineComment=true;i++;continue; }
    if(ch==='/'&&next==='*'){ blockComment=true;i++;continue; }
    if(ch==='"'||ch==="'"||ch==='`'){ quote=ch;continue; }
    if(ch==='{') depth++;
    if(ch==='}'&&--depth===0) return source.slice(start,i+1);
  }
  throw new Error(`fonction ${name} incomplète`);
}

function compile(source,names,exported,extra={}){
  const context=vm.createContext({...extra});
  const code=names.map(name=>extractFunction(source,name)).join('\n')+
    `\nglobalThis.__tested=${exported};`;
  new vm.Script(code,{filename:'fonctions-extraites.html.js'}).runInContext(context);
  return context;
}

const driverCtx=compile(
  driver,
  ['sourceOf','rateOf','rideRate','sourceIsAppCash','rideNet'],
  'rideNet',
  {db:{sources:[]}}
);
const patronCtx=compile(patron,['cSrcAppCash','cRateOf','cRideNet'],'cRideNet');
const adminCtx=compile(admin,['cSrcAppCash','cRateOf','cRideNet'],'cRideNet');
const patronSettlementCtx=compile(
  patron,
  ['cRideOnboard','cSettlement'],
  '({cRideOnboard,cSettlement})'
);
const adminSettlementCtx=compile(
  admin,
  ['cRideOnboard','cSettlement'],
  '({cRideOnboard,cSettlement})'
);
let moneyInputValue='';
const moneyInputExtra={$:()=>({value:moneyInputValue})};
const patronMoneyInputCtx=compile(patron,['cMoneyInput'],'cMoneyInput',moneyInputExtra);
const adminMoneyInputCtx=compile(admin,['cMoneyInput'],'cMoneyInput',moneyInputExtra);
const patronFeaturesCtx=compile(
  patron,
  ['fleetFeatures','patronSectionAllowed'],
  '({fleetFeatures,patronSectionAllowed})'
);
const adminRideEditCtx=compile(
  admin,
  ['parseAdminDecimal','normalizeAdminRideInput'],
  'normalizeAdminRideInput'
);
const adminLiveMapCtx=compile(admin,['liveDriverGroups'],'liveDriverGroups');

const featureCases=[
  [null,{recettes:false,gpsLive:false,replay:false,carte:false}],
  [{opt_recettes:true,opt_gps_live:true,opt_replay:true,suspended:false},{recettes:true,gpsLive:true,replay:true,carte:true}],
  [{opt_recettes:false,opt_gps_live:false,opt_replay:true,suspended:false},{recettes:false,gpsLive:false,replay:true,carte:true}],
  [{opt_recettes:true,opt_gps_live:true,opt_replay:false,suspended:true},{recettes:false,gpsLive:false,replay:false,carte:false}]
];
for(const [fleet,expected] of featureCases){
  const actual=patronFeaturesCtx.__tested.fleetFeatures(fleet);
  assert.deepEqual(JSON.parse(JSON.stringify(actual)),expected);
  assert.equal(patronFeaturesCtx.__tested.patronSectionAllowed('recettes',actual),expected.recettes);
  assert.equal(patronFeaturesCtx.__tested.patronSectionAllowed('carte',actual),expected.carte);
  assert.equal(patronFeaturesCtx.__tested.patronSectionAllowed('reglages',actual),true);
}

let patchResponse={ok:true,data:[{id:'fleet-a',opt_recettes:false,max_plates:4}]};
let patchRequest=null;
const adminFleetCache=[{id:'fleet-a',opt_recettes:true,max_plates:2}];
const fleetError={textContent:''};
const adminPatchCtx=compile(admin,['patchFleet'],'patchFleet',{
  _fleetsCache:adminFleetCache,
  document:{querySelector:()=>fleetError},
  api:async(path,options)=>{ patchRequest={path,options}; return patchResponse; }
});
const savedFleet=await adminPatchCtx.__tested('fleet-a',{opt_recettes:false});
assert.equal(savedFleet.opt_recettes,false);
assert.equal(adminFleetCache[0].opt_recettes,false);
assert.match(patchRequest.path,/select=id,name,max_plates,suspended,opt_gps_live,opt_replay,opt_recettes/);
assert.equal(patchRequest.options.headers.Prefer,'return=representation');
patchResponse={ok:true,data:[]};
assert.equal(await adminPatchCtx.__tested('fleet-a',{opt_recettes:true}),null);
assert.equal(fleetError.textContent,'Échec de l\'enregistrement.');

const validAdminRide=adminRideEditCtx.__tested({
  time:'14:25',amount:'1.234,56',source:'prive',sourceName:'Course privée',
  pay:'cash',rate:'12,5',cash:''
});
assert.equal(validAdminRide.ok,true);
assert.equal(validAdminRide.ride.amt,1234.56);
assert.equal(validAdminRide.ride.rate,12.5);
const validAppCashRide=adminRideEditCtx.__tested({
  time:'',amount:'500',source:'uber',sourceName:'Uber',pay:'appcash',rate:'30',cash:'125,50'
});
assert.equal(validAppCashRide.ok,true);
assert.equal(validAppCashRide.ride.rate,0);
assert.equal(validAppCashRide.ride.cash,125.5);
assert.equal(adminRideEditCtx.__tested({time:'25:00',amount:'50',source:'x',pay:'cash',rate:'0'}).ok,false);
assert.equal(adminRideEditCtx.__tested({time:'10:00',amount:'50',source:'x',pay:'appcash',rate:'0',cash:'60'}).ok,false);

const liveGroups=adminLiveMapCtx.__tested([
  {driver_id:'driver-a',plate_id:'plate-a',driver_name:'A',lat:50.8,lng:4.3,recorded_at:'2026-08-07T10:00:00Z'},
  {driver_id:'driver-a',plate_id:'plate-a',driver_name:'A',lat:50.7,lng:4.2,recorded_at:'2026-08-07T09:59:00Z'},
  {driver_id:'driver-b',plate_id:'plate-b',driver_name:'B',lat:null,lng:null,recorded_at:null}
]);
assert.equal(liveGroups.length,2);
assert.equal(liveGroups[0].key,'driver-a');
assert.equal(liveGroups[0].points.length,2);
assert.equal(liveGroups[0].latest.lat,50.8);
assert.equal(liveGroups[1].key,'driver-b');
assert.equal(liveGroups[1].latest,null);

const moneyInputCases=[
  ['',null],
  ['0',0],
  ['0,00',0],
  ['125,50',125.5],
  ['1.234,56',1234.56],
  ['1.000',1000],
  ['12.5',12.5],
  ['-1',NaN],
  ['montant',NaN]
];
for(const [input,expected] of moneyInputCases){
  moneyInputValue=input;
  for(const ctx of [patronMoneyInputCtx,adminMoneyInputCtx]){
    const actual=ctx.__tested('amount');
    if(Number.isNaN(expected)) assert.ok(Number.isNaN(actual));
    else assert.equal(actual,expected);
  }
}

const onboardCases=[
  [{amt:100,pay:'cash',rate:40},100],
  [{amt:100,pay:'sumup',rate:40},100],
  [{amt:100,pay:'cheque',rate:40},100],
  [{amt:100,pay:'app'},0],
  [{amt:100,pay:'appcash',cash:37.25},37.25],
  [{amt:100,pay:'appcash',cash:-20},0],
  [{amt:100,pay:'appcash',cash:140},100]
];
for(const [ride,expected] of onboardCases){
  assert.equal(patronSettlementCtx.__tested.cRideOnboard(ride),expected);
  assert.equal(adminSettlementCtx.__tested.cRideOnboard(ride),expected);
}

const settlementCases=[
  {input:[1000,300,100,400],valid:true,patronHeld:400,chauffeurCash:600,balance:200},
  {input:[1000,600,100,700],valid:true,patronHeld:700,chauffeurCash:300,balance:-400},
  /* 100 € cash avec 20 % de commission : 80 € nets, part chauffeur 48 €.
     Le chauffeur détient bien 100 € bruts et reverse donc 52 € au patron. */
  {input:[100,0,0,48],valid:true,patronHeld:0,chauffeurCash:100,balance:52},
  {input:[100,100,0,48],valid:true,patronHeld:100,chauffeurCash:0,balance:-48},
  {input:[123.45,12.34,11.11,60],valid:true,patronHeld:23.45,chauffeurCash:100,balance:40},
  {input:[100,80,30,40],valid:false,patronHeld:110,chauffeurCash:-10,balance:null}
];
for(const expected of settlementCases){
  for(const ctx of [patronSettlementCtx,adminSettlementCtx]){
    const actual=ctx.__tested.cSettlement(...expected.input);
    assert.equal(actual.valid,expected.valid);
    assert.equal(actual.patronHeld,expected.patronHeld);
    assert.equal(actual.chauffeurCash,expected.chauffeurCash);
    assert.equal(actual.balance,expected.balance);
  }
}

let seed=0x5eed1234;
const rnd=()=>((seed=(seed*1664525+1013904223)>>>0)/0x100000000);
let displayedGroups=0;
for(let i=0;i<100000;i++){
  const amount=Math.round(rnd()*250000)/100;
  const configuredRate=rnd()*180-40;
  const sources=[
    {id:'appcash',rate:configuredRate,appCash:true},
    {id:'standard',rate:configuredRate,appCash:false}
  ];
  const sourceIds=['appcash','standard','inconnue'];
  const pays=['app','cash','sumup','cheque','appcash'];
  const src=sourceIds[Math.floor(rnd()*sourceIds.length)];
  const pay=pays[Math.floor(rnd()*pays.length)];
  const ride={amt:amount,src,pay};
  if(rnd()<.72) ride.rate=rnd()*180-40;
  const effectiveRate=typeof ride.rate==='number' ? ride.rate :
    (src==='standard'||src==='appcash' ? configuredRate : 0);
  const expected=referenceNet(amount,effectiveRate,pay,src==='appcash');
  driverCtx.db={sources};
  const driverNet=driverCtx.__tested(ride);
  const patronNet=patronCtx.__tested({sources},ride);
  const adminNet=adminCtx.__tested({sources},ride);
  assert.equal(driverNet,expected);
  assert.equal(patronNet,driverNet);
  assert.equal(adminNet,driverNet);
  assert.ok(expected>=0 && expected<=amount);

  /* Une période affichée doit totaliser exactement les centimes de ses lignes. */
  if(i%10===0){
    const rides=[ride];
    for(let j=0;j<Math.floor(rnd()*18);j++){
      rides.push({
        amt:Math.round(rnd()*100000)/100,
        src:sourceIds[Math.floor(rnd()*sourceIds.length)],
        pay:pays[Math.floor(rnd()*pays.length)],
        rate:rnd()*100
      });
    }
    const lineCents=rides.reduce((sum,item)=>sum+Math.round(driverCtx.__tested(item)*100),0);
    const totalCents=Math.round(rides.reduce((sum,item)=>sum+driverCtx.__tested(item),0)*100);
    assert.equal(totalCents,lineCents);
    displayedGroups++;
  }
}

for(let i=0;i<50000;i++){
  const total=Math.round(rnd()*500000)/100;
  const minimum=Math.round(rnd()*10000)/100;
  const jump=Math.max(.01,Math.round(rnd()*100)/100);
  const web=Math.round(Math.max(Math.round(total/jump)*jump,minimum)*100)/100;
  const native=Math.round(Math.max(Math.round(Math.round(total/jump)*jump*100)/100,minimum)*100)/100;
  assert.equal(native,web);
  assert.ok(native>=minimum);
}

for(const html of [driver,patron,admin]){
  assert.match(html,/IBM\+Plex\+Sans/);
  assert.match(html,/ui-system\.css/);
}
assert.match(driver,/class="app-driver"/);
assert.match(driver,/id="driverTaxiShortcut"/);
assert.match(driver,/id="driverHeroNet"/);
assert.match(patron,/class="app-manager"/);
assert.match(patron,/id="managerHero"/);
assert.match(admin,/class="app-admin"/);
assert.match(admin,/id="adminHero"/);
assert.equal((patron.match(/data-feature="recettes"/g)||[]).length,2);
assert.equal((patron.match(/data-feature="carte"/g)||[]).length,2);
assert.match(patron,/setInterval\(refreshPatronFeatures,15000\)/);
assert.match(patron,/window\.addEventListener\('focus',refreshPatronFeatures\)/);
assert.match(admin,/'Prefer':'return=representation'/);
assert.match(admin,/\/rest\/v1\/rpc\/admin_ride_mutation/);
assert.match(admin,/id="cRideAdminList"/);
assert.match(admin,/id="rideEditDialog"/);
assert.match(admin,/value="">Toutes les flottes<\/option>/);
assert.match(admin,/id="mapFitBtn"/);
assert.match(admin,/function liveDriverGroups\(/);
for(const html of [patron,admin]){
  assert.match(html,/id="cSumup"/);
  assert.match(html,/id="cTaxiCheque"/);
  assert.match(html,/function cRideOnboard\(/);
  assert.match(html,/function cSettlement\(/);
  assert.doesNotMatch(html,/id="cKeepCash"/);
}
assert.match(driver,/deletedRideIds/);
assert.match(driver,/fieldUpdatedAt/);
assert.match(driver,/syncUpdatedAt/);
assert.match(driver,/const started=JSON\.parse\(TaxiNative\.startMeter/);
assert.match(driver,/if\(speed>180\)/);
assert.match(driver,/supplementNuit:t\.supplementNuit, applyNight:night/);
assert.match(patron,/_liveReqSeq/);
assert.match(admin,/_liveReqSeq/);
assert.match(meter,/MeterMath\.finalPrice\(total, minimumCourse, saut\)/);
assert.match(meter,/MeterMath\.increment/);
assert.match(meterMath,/MAX_PLAUSIBLE_SPEED_KMH/);
assert.match(meterMath,/fun finalPrice/);
assert.match(meter,/optBoolean\("applyNight"/);
assert.match(taxiBridge,/catch \(_: Exception\) \{\s*try \{ Meter\.stop\(\) \}[\s\S]*Meter\.clearSnapshot\(ctx\)/);
assert.match(driver,/TaxiNative\.stopPositionPush/);
assert.match(driver,/function dialogFocusable\(el\)/);
assert.match(driver,/e\.key==='Escape'/);
assert.match(driver,/openDialog\(ov,\(\)=>\$\('ppCancel'\)\)/);
assert.match(fs.readFileSync(
  new URL('../android/app/src/main/java/be/taxirecettes/copilote/PositionPush.kt',import.meta.url),'utf8'
),/if \(!collecting\) clear\(ctx\)/);
assert.match(mainActivity,/if \(BuildConfig\.IS_DRIVER\) \{\s*web\.addJavascriptInterface/);
assert.match(mainActivity,/WebViewAssetLoader/);
assert.match(mainActivity,/shouldOverrideUrlLoading/);
assert.match(mainActivity,/appassets\.androidplatform\.net/);
assert.match(mainActivity,/allowUniversalAccessFromFileURLs = false/);
assert.match(androidManifest,/android:allowBackup="false"/);
assert.match(androidManifest,/android:usesCleartextTraffic="false"/);
assert.match(androidGradle,/https:\/\/appassets\.androidplatform\.net\/assets\/webapp\/index\.html/);
assert.doesNotMatch(admin,/prompt\('Nouveau mot de passe/);
assert.match(patron,/\/rest\/v1\/rpc\/positions_live/);
assert.match(admin,/\/rest\/v1\/rpc\/positions_live/);
assert.doesNotMatch(patron,/recorded_at\.desc&limit=1000/);
assert.doesNotMatch(admin,/recorded_at\.desc&limit=2000/);
assert.match(admin,/else if\(r\.status>0 && !r\.ok\)/);
assert.match(admin,/Réponse du serveur perdue/);
assert.match(admin,/Mot de passe : 10 caractères minimum/);
assert.match(patron,/Mot de passe : 10 caractères minimum/);
assert.match(accountFunction,/password\.length < 10/);
assert.doesNotMatch(accountFunction,/detail:\s*(?:String\(|error\.message|pErr\.message)/);

console.log(JSON.stringify({
  moneyCases:100000,
  moneyInputCases:moneyInputCases.length,
  settlementCases:settlementCases.length,
  displayedTotalGroups:displayedGroups,
  meterCases:50000,
  moneyParity:true,
  moneyFunctionsExtracted:true,
  displayedTotalsMatch:true,
  meterReferenceParity:true,
  nativeMeterMathDelegated:true,
  androidStartRollback:true,
  syncGuards:true,
  modalFocusManaged:true,
  adminRideEditing:true,
  adminRideValidation:true,
  liveMapUsesPerDriverRpc:true,
  liveMapShowsPendingDrivers:true,
  ambiguousCreatePreserved:true,
  uiSystem:true,
  androidWebViewIsolated:true
},null,2));
