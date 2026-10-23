const KEY='vros-spatial-shell-v2.2';
const FILES=['./','./index.html','./styles.css','./app.js','./icon.svg','./manifest.webmanifest'];
self.addEventListener('install',event=>event.waitUntil(caches.open(KEY).then(cache=>cache.addAll(FILES)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('vros-spatial-shell-')&&key!==KEY).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET'||new URL(event.request.url).origin!==self.location.origin)return;
  event.respondWith(fetch(event.request).then(res=>{if(res.ok){const copy=res.clone();caches.open(KEY).then(c=>c.put(event.request,copy)).catch(()=>{});}return res;}).catch(()=>caches.match(event.request)));
});
