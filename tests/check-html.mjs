import fs from 'node:fs';
import vm from 'node:vm';

const files=[
  'index.html',
  'dashboard.html',
  'patron.html',
  'admin.html',
  'android/app/src/main/assets/webapp/index.html'
];

for(const file of files){
  const html=fs.readFileSync(new URL('../'+file,import.meta.url),'utf8');
  const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/gi)];
  if(!scripts.length) throw new Error(`${file}: script principal introuvable`);
  scripts.forEach((match,i)=>new vm.Script(match[1],{filename:`${file}#${i+1}`}));
}

const rootIndex=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8')
  .split(/\r?\n/).filter(line=>!line.includes('rel="manifest"')).join('\n');
const embeddedIndex=fs.readFileSync(
  new URL('../android/app/src/main/assets/webapp/index.html',import.meta.url),'utf8'
);
if(rootIndex!==embeddedIndex) throw new Error('asset Android désynchronisé de index.html');
const rootCss=fs.readFileSync(new URL('../ui-system.css',import.meta.url),'utf8');
const embeddedCss=fs.readFileSync(
  new URL('../android/app/src/main/assets/webapp/ui-system.css',import.meta.url),'utf8'
);
if(rootCss!==embeddedCss) throw new Error('CSS Android désynchronisé');

const sw=fs.readFileSync(new URL('../sw.js',import.meta.url),'utf8');
new vm.Script(sw,{filename:'sw.js'});
if(!sw.includes('taxi-recettes-shell-v5-feature-access')) throw new Error('cache PWA iPhone non versionné');
if(!sw.includes("'./patron.html'")) throw new Error('espace patron absent du cache PWA');
const manifest=JSON.parse(fs.readFileSync(new URL('../manifest.json',import.meta.url),'utf8'));
if(!Array.isArray(manifest.icons)||manifest.icons.length<2) throw new Error('icônes PWA manquantes');
if(manifest.theme_color!=='#0F172A') throw new Error('couleur PWA non alignée sur le design final');
for(const icon of manifest.icons){
  if(!fs.existsSync(new URL('../'+icon.src,import.meta.url))) throw new Error(`icône absente : ${icon.src}`);
}
const patronPwa=fs.readFileSync(new URL('../patron.html',import.meta.url),'utf8');
for(const marker of [
  'apple-mobile-web-app-capable',
  'href="manifest-patron.json"',
  'rel="apple-touch-icon"',
  "serviceWorker.register('./sw.js')"
]){
  if(!patronPwa.includes(marker)) throw new Error(`PWA patron incomplète : ${marker}`);
}
const patronManifest=JSON.parse(
  fs.readFileSync(new URL('../manifest-patron.json',import.meta.url),'utf8')
);
if(patronManifest.id!=='./patron.html'||patronManifest.start_url!=='./patron.html'){
  throw new Error('le PWA patron ne démarre pas sur son propre espace');
}
if(patronManifest.display!=='standalone') throw new Error('le PWA patron ne démarre pas comme une app');
for(const icon of patronManifest.icons||[]){
  if(!fs.existsSync(new URL('../'+icon.src,import.meta.url))) throw new Error(`icône patron absente : ${icon.src}`);
}
for(const selector of ['body.app-driver','body.app-manager','body.app-admin','prefers-reduced-motion']){
  if(!rootCss.includes(selector)) throw new Error(`règle UI finale absente : ${selector}`);
}
for(const file of ['index.html','patron.html','admin.html']){
  const html=fs.readFileSync(new URL('../'+file,import.meta.url),'utf8');
  if(/[\u{1F300}-\u{1FAFF}]/u.test(html)) throw new Error(`${file}: emoji structurel interdit`);
}

console.log(JSON.stringify({htmlSyntax:true,files,pwa:true,embeddedSynced:true},null,2));
