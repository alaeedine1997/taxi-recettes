import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const driver=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const patron=fs.readFileSync(new URL('../patron.html',import.meta.url),'utf8');
const admin=fs.readFileSync(new URL('../admin.html',import.meta.url),'utf8');
const meter=fs.readFileSync(new URL('../android/app/src/main/java/be/taxirecettes/copilote/Meter.kt',import.meta.url),'utf8');
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
  const start=source.indexOf(`function ${name}(`);
  if(start<0) throw new Error(`fonction ${name} introuvable`);
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
assert.match(driver,/deletedRideIds/);
assert.match(driver,/fieldUpdatedAt/);
assert.match(driver,/syncUpdatedAt/);
assert.match(driver,/const started=JSON\.parse\(TaxiNative\.startMeter/);
assert.match(driver,/if\(speed>180\)/);
assert.match(driver,/supplementNuit:t\.supplementNuit, applyNight:night/);
assert.match(patron,/_liveReqSeq/);
assert.match(admin,/_liveReqSeq/);
assert.match(meter,/max\(roundSaut\(total\), minimumCourse\)/);
assert.match(meter,/MAX_PLAUSIBLE_SPEED_KMH/);
assert.match(meter,/optBoolean\("applyNight"/);
assert.match(driver,/TaxiNative\.stopPositionPush/);
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
assert.match(admin,/Mot de passe : 10 caractères minimum/);
assert.match(patron,/Mot de passe : 10 caractères minimum/);
assert.match(accountFunction,/password\.length < 10/);
assert.doesNotMatch(accountFunction,/detail:\s*(?:String\(|error\.message|pErr\.message)/);

console.log(JSON.stringify({
  moneyCases:100000,
  displayedTotalGroups:displayedGroups,
  meterCases:50000,
  moneyParity:true,
  moneyFunctionsExtracted:true,
  displayedTotalsMatch:true,
  meterParity:true,
  syncGuards:true,
  uiSystem:true,
  androidWebViewIsolated:true
},null,2));
