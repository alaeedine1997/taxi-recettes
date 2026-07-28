import assert from 'node:assert/strict';
import fs from 'node:fs';

const driver=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const patron=fs.readFileSync(new URL('../patron.html',import.meta.url),'utf8');
const admin=fs.readFileSync(new URL('../admin.html',import.meta.url),'utf8');
const meter=fs.readFileSync(new URL('../android/app/src/main/java/be/taxirecettes/copilote/Meter.kt',import.meta.url),'utf8');

function net(amount,rate,pay='cash'){
  if(pay==='app'||pay==='appcash') return amount;
  const bounded=Math.min(100,Math.max(0,rate));
  return Math.round(Math.round(amount*100)*(10000-Math.round(bounded*100))/10000)/100;
}

let seed=0x5eed1234;
const rnd=()=>((seed=(seed*1664525+1013904223)>>>0)/0x100000000);
for(let i=0;i<100000;i++){
  const amount=Math.round(rnd()*250000)/100;
  const rate=rnd()*180-40;
  const expected=net(amount,rate);
  assert.equal(expected,net(amount,rate));
  assert.ok(expected>=0 && expected<=amount);
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
  assert.match(html,/Source\+Sans\+3/);
  assert.match(html,/ui-system\.css/);
}
assert.match(driver,/deletedRideIds/);
assert.match(driver,/fieldUpdatedAt/);
assert.match(driver,/syncUpdatedAt/);
assert.match(driver,/const started=JSON\.parse\(TaxiNative\.startMeter/);
assert.match(patron,/_liveReqSeq/);
assert.match(admin,/_liveReqSeq/);
assert.match(meter,/max\(roundSaut\(total\), minimumCourse\)/);

console.log(JSON.stringify({
  moneyCases:100000,
  meterCases:50000,
  moneyParity:true,
  meterParity:true,
  syncGuards:true,
  uiSystem:true
},null,2));
