// VR OS Spatial 2 — browser-based camera passthrough and orientation-relative window shell.
// A browser cannot use ARKit's world tracking: anchors here are angular, not positional.
'use strict';

const $ = (selector,root=document) => root.querySelector(selector);
const $$ = (selector,root=document) => [...root.querySelectorAll(selector)];
const glyph = name => `<svg aria-hidden="true"><use href="#i-${name}"></use></svg>`;
const htmlEscape = value => String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const clamp = (value,min,max) => Math.max(min,Math.min(max,value));
const persistent = {
  get(key,fallback){try{const raw=localStorage.getItem('vros2.'+key);return raw===null?fallback:JSON.parse(raw)}catch{return fallback}},
  set(key,value){try{localStorage.setItem('vros2.'+key,JSON.stringify(value));return true}catch{return false}}
};
const defaults={accent:'#aacbf7',opacity:.76,camera:'ultrawide',gyro:true,scale:1,handsFps:15,showPoints:false,mirror:false,handSensitivity:.43,reduceMotion:false};
const settings={...defaults,...persistent.get('settings',{})};
settings.opacity=clamp(Number(settings.opacity)||defaults.opacity,.48,.96);
settings.scale=clamp(Number(settings.scale)||1,.70,1.18);
settings.handsFps=[10,15,20].includes(Number(settings.handsFps))?Number(settings.handsFps):15;
settings.handSensitivity=clamp(Number(settings.handSensitivity)||defaults.handSensitivity,.15,.8);
if(!/^#[0-9a-f]{6}$/i.test(settings.accent))settings.accent=defaults.accent;
const apps={
  home:['Início','home'], apps:['Aplicativos','grid'], notes:['Notas','note'], clock:['Relógio','clock'],
  calc:['Calculadora','calc'], files:['Arquivos','folder'], gallery:['Galeria','photo'],music:['Música','music'],
  calendar:['Calendário','calendar'],hands:['Gestos','hand'],settings:['Ajustes','settings'],
  spaces:['Janelas','windows'],about:['Sobre o VR OS','info']
};
const state={
  started:false,starting:false,video:$('#cameraVideo'),stream:null,cameras:[],lastError:'',logs:[],
  orientationAllowed:false,poseReady:false,pose:null,poseTarget:null,renderScheduled:false,sensorAge:0,
  cameraSwitching:false,dbPromise:null,landmarkErrors:0,lastHandPresence:0,
  dockDir:null,windows:new Map(),z:12,windId:0,full:0,handModel:null,handRunning:false,
  handLoop:0,handLastVideo:-1,handLastTick:0,handFps:0,handCount:0,handLastFrame:0,
  pointers:[{position:null,pinch:false,frames:0},{position:null,pinch:false,frames:0}],gesture:null,hover:null,
  stopwatch:{elapsed:0,since:0,active:false},mediaURL:null,audio:null,db:null,memoryFiles:new Map()
};
const log=(message)=>{state.logs.unshift(new Date().toLocaleTimeString('pt-BR')+' — '+String(message));state.logs.length=Math.min(state.logs.length,16);};
function toast(message,duration=3400){const element=$('#toast');element.textContent=String(message);element.classList.add('shown');clearTimeout(toast.timer);toast.timer=setTimeout(()=>element.classList.remove('shown'),duration)}
function saveSettings(){persistent.set('settings',settings);applySettings()}
function applySettings(){
  document.documentElement.style.setProperty('--accent',settings.accent);
  document.documentElement.style.setProperty('--panel-alpha',String(settings.opacity));
  document.documentElement.style.setProperty('--motion',settings.reduceMotion?'0':'1');
  document.body.classList.toggle('debug-hands',settings.showPoints);
  document.body.classList.toggle('hand-control-active',state.handRunning);
  document.body.classList.toggle('reduce-motion',settings.reduceMotion);
  for(const w of state.windows.values())applyWindowSize(w);
  scheduleRender();
}
function setStatus(label,kind='ok'){const el=$('#trackState');el.innerHTML=`<span class="led"></span> ${htmlEscape(label)}`;el.dataset.kind=kind}
function measure(){return{width:window.innerWidth,height:window.innerHeight}}
function availableRect(){const{width,height}=measure();return{width,height,landscape:width>height}}

// Quaternion calculations: iOS DeviceOrientation -> screen-relative 3-D camera pose.
const qIdentity=()=>({x:0,y:0,z:0,w:1});
const qMultiply=(a,b)=>({
  x:a.x*b.w+a.w*b.x+a.y*b.z-a.z*b.y,
  y:a.y*b.w+a.w*b.y+a.z*b.x-a.x*b.z,
  z:a.z*b.w+a.w*b.z+a.x*b.y-a.y*b.x,
  w:a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z
});
function qYXZ(x,y,z){
  const c1=Math.cos(x/2),c2=Math.cos(y/2),c3=Math.cos(z/2),s1=Math.sin(x/2),s2=Math.sin(y/2),s3=Math.sin(z/2);
  return{x:s1*c2*c3+c1*s2*s3,y:c1*s2*c3-s1*c2*s3,z:c1*c2*s3-s1*s2*c3,w:c1*c2*c3+s1*s2*s3};
}
function qNormalize(q){const l=Math.hypot(q.x,q.y,q.z,q.w)||1;return{x:q.x/l,y:q.y/l,z:q.z/l,w:q.w/l}}
function qNlerp(a,b,t){const sign=a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w<0?-1:1;return qNormalize({x:a.x*(1-t)+b.x*t*sign,y:a.y*(1-t)+b.y*t*sign,z:a.z*(1-t)+b.z*t*sign,w:a.w*(1-t)+b.w*t*sign})}
function orientationQuat(e){
  const rad=Math.PI/180,alpha=e.alpha*rad,beta=e.beta*rad,gamma=e.gamma*rad;
  const angle=Number(screen.orientation?.angle??window.orientation??0)*rad;
  const q=qYXZ(beta,alpha,-gamma),q1={x:-Math.SQRT1_2,y:0,z:0,w:Math.SQRT1_2};
  const q0={x:0,y:0,z:Math.sin(-angle/2),w:Math.cos(-angle/2)};
  return qNormalize(qMultiply(qMultiply(q,q1),q0));
}
const vec=(x,y,z)=>({x,y,z});
const cross=(a,b)=>vec(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x);
const dot=(a,b)=>a.x*b.x+a.y*b.y+a.z*b.z;
const vNormalize=a=>{const l=Math.hypot(a.x,a.y,a.z)||1;return vec(a.x/l,a.y/l,a.z/l)};
function rotated(q,v){const u=vec(q.x,q.y,q.z),uv=cross(u,v),uuv=cross(u,uv);return vec(v.x+2*(q.w*uv.x+uuv.x),v.y+2*(q.w*uv.y+uuv.y),v.z+2*(q.w*uv.z+uuv.z))}
function basis(){const q=state.pose||qIdentity();return{forward:rotated(q,vec(0,0,-1)),right:rotated(q,vec(1,0,0)),up:rotated(q,vec(0,1,0))}}
function focal(){const{width}=measure();return width/(2*Math.tan((62*Math.PI/180)/2))}
function rayAt(x,y){const{width,height}=measure(),b=basis(),f=focal();return vNormalize(vec(
  b.forward.x+b.right.x*((x-width/2)/f)-b.up.x*((y-height/2)/f),
  b.forward.y+b.right.y*((x-width/2)/f)-b.up.y*((y-height/2)/f),
  b.forward.z+b.right.z*((x-width/2)/f)-b.up.z*((y-height/2)/f)
))}
function projection(direction){const{width,height}=measure(),b=basis();const z=dot(direction,b.forward);if(z<=.12)return{x:-9999,y:-9999,z,visible:false};const f=focal();return{x:width/2+dot(direction,b.right)/z*f,y:height/2-dot(direction,b.up)/z*f,z,visible:true}}
function sensorUpdate(event){
  if(!state.started||!settings.gyro)return;
  if(![event.alpha,event.beta,event.gamma].every(Number.isFinite))return;
  const q=orientationQuat(event);state.sensorAge=Date.now();state.poseTarget=q;
  if(!state.poseReady){state.pose=q;state.poseReady=true;recenterAll(true);log('Orientação ativa');}
  setStatus(state.handRunning?`${state.handCount} mão(s) • ${state.handFps} FPS`:'Câmera • movimento ativo');
  scheduleRender();
}
window.addEventListener('deviceorientation',sensorUpdate,{passive:true});
function scheduleRender(){if(state.renderScheduled)return;state.renderScheduled=true;requestAnimationFrame(render)}
function render(){
  state.renderScheduled=false;
  if(state.poseReady&&state.poseTarget){
    const q=state.pose,newQ=qNlerp(q,state.poseTarget,settings.reduceMotion?1:.28);
    state.pose=newQ;
    // Compare against the TARGET: frame-to-frame change can be tiny even when the target is far away.
    const remaining=1-Math.min(1,Math.abs(dotQuat(newQ,state.poseTarget)));
    if(remaining>.0000003 && !document.hidden)scheduleRender();
  }
  const{width,height}=measure();
  for(const w of state.windows.values()){
    const p=projection(w.dir),visible=p.visible&&p.x>-w.width*.54&&p.x<width+w.width*.54&&p.y>-w.height*.54&&p.y<height+w.height*.54;
    w.el.classList.toggle('offscreen',!visible);
    if(!visible)continue;
    w.el.style.left=p.x.toFixed(2)+'px';w.el.style.top=p.y.toFixed(2)+'px';
    const a=clamp((p.x-width/2)/width,-.5,.5),b=clamp((p.y-height/2)/height,-.5,.5);
    w.el.style.setProperty('--tilt-y',(-a*7).toFixed(2)+'deg');
    w.el.style.setProperty('--tilt-x',(b*5).toFixed(2)+'deg');
  }
  if(state.dockDir){const p=projection(state.dockDir),el=$('#dock'),ok=p.visible&&p.x>30&&p.x<width-30&&p.y>15&&p.y<height-15;el.classList.toggle('offscreen',!ok);if(ok){el.style.left=p.x+'px';el.style.top=p.y+'px';}}
}
const dotQuat=(a,b)=>a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w;
function recenterAll(silent=false){
  const list=[...state.windows.values()],{width,height}=measure();
  list.forEach((w,i)=>{w.dir=rayAt(width/2+(i%3-1)*Math.min(90,width*.11),height*.48+(i%3-1)*8)});
  state.dockDir=rayAt(width/2,height*(width>height?.9:.86));
  scheduleRender();saveLayout();if(!silent)toast('Espaço recentralizado');
}
function centerWindow(w){const{width,height}=measure();
  // Center inside the visible area, not behind Safari's top controls.
  const cy=clamp(height*.48,48+w.height*settings.scale*.5+4,height-35);
  w.dir=rayAt(width/2,cy);focusWindow(w);scheduleRender();saveLayout()}
function requireStarted(){if(!state.started){toast('Inicie a câmera primeiro');return false}return true}

function defaultWindowSize(){const{width,height,landscape}=availableRect(),scale=settings.scale;return{
  width:Math.round(clamp(width*(landscape?.53:.86),landscape?310:260,Math.min(landscape?640:470,(width-24)/scale))),
  height:Math.round(clamp(height*(landscape?.64:.53),landscape?190:260,Math.min(landscape?480:590,(height-(landscape?118:128))/scale)))
}}
function applyWindowSize(w){
  const{width,height}=measure(),scale=settings.scale;
  const maxW=Math.max(200,(width-28)/scale),maxH=Math.max(145,(height-(width>height?110:116))/scale);
  w.width=clamp(w.width,Math.min(200,maxW),maxW);w.height=clamp(w.height,Math.min(145,maxH),maxH);
  w.el.style.width=Math.round(w.width)+'px';w.el.style.height=Math.round(w.height)+'px';
  w.el.style.setProperty('--window-scale',settings.scale);
}
function saveLayout(){const{width,height}=measure();persistent.set('workspace',[...state.windows.values()].map(w=>{
  const p=projection(w.dir);return{kind:w.kind,x:clamp(p.x/width,-.5,1.5),y:clamp(p.y/height,-.5,1.5),width:w.width,height:w.height,minimized:w.minimized};
}));}
function windowMarkup(w){return `<div class="window-head">
  <div class="window-controls">
    <button type="button" data-win="close" title="Fechar ${htmlEscape(apps[w.kind][0])}" aria-label="Fechar janela">${glyph('close')}</button>
    <button type="button" data-win="min" title="Minimizar" aria-label="Minimizar janela">${glyph('minimize')}</button>
    <button type="button" data-win="max" title="Expandir" aria-label="Expandir janela">${glyph('expand')}</button>
  </div><span class="window-title">${htmlEscape(apps[w.kind][0])}</span>
  <button type="button" class="window-pin" data-win="center" title="Trazer para frente" aria-label="Trazer para frente">${glyph('pin')}</button>
</div><div class="window-content"></div><div class="resizer" role="separator" aria-label="Redimensionar janela"></div>`}
function openWindow(kind,opts={}){
  if(!apps[kind]||!requireStarted())return null;
  // One window per app: avoids invisible duplicates and accidental stacking on iPhone.
  const existing=[...state.windows.values()].find(w=>w.kind===kind);
  if(existing){existing.minimized=false;existing.el.classList.remove('minimized');centerWindow(existing);return existing;}
  const id=++state.windId;const size=defaultWindowSize();const{width,height}=measure();
  const x=opts.x!==undefined?opts.x*width:width/2+(state.windows.size%3-1)*Math.min(85,width*.10);
  const y=opts.y!==undefined?opts.y*height:Math.max(height*.48,48+(opts.height||size.height)*settings.scale*.5+4);
  const w={id,kind,dir:rayAt(x,y),width:Number(opts.width)||size.width,height:Number(opts.height)||size.height,minimized:!!opts.minimized,maxOld:null,disposers:[],el:null};
  const el=document.createElement('section');el.className='spatial-window glass';el.dataset.windowId=String(id);el.setAttribute('role','region');el.setAttribute('aria-label',apps[kind][0]);el.innerHTML=windowMarkup(w);w.el=el;
  $('#worldLayer').appendChild(el);state.windows.set(id,w);applyWindowSize(w);el.classList.toggle('minimized',w.minimized);focusWindow(w);installWindowInput(w);mountApp(w);scheduleRender();saveLayout();return w;
}
function focusWindow(w){if(!w||!state.windows.has(w.id))return;for(const item of state.windows.values())item.el.classList.toggle('focused',item===w);w.el.style.zIndex=++state.z;$$('.dock-item').forEach(btn=>btn.classList.toggle('active',btn.dataset.open===w.kind))}
function closeWindow(w){
  if(!w||!state.windows.has(w.id))return;
  if(state.gesture?.w===w)state.gesture=null;
  if(state.hover && w.el.contains(state.hover))clearHover();
  for(const fn of w.disposers)try{fn()}catch(error){log(error.message)}
  w.el.remove();state.windows.delete(w.id);saveLayout();scheduleRender();toast(apps[w.kind][0]+' fechado');
  if(state.windows.size===0)$$('.dock-item').forEach(btn=>btn.classList.remove('active'));
}
function minimizeWindow(w){if(!w||!state.windows.has(w.id))return;w.minimized=!w.minimized;w.el.classList.toggle('minimized',w.minimized);saveLayout();scheduleRender()}
function maximizeWindow(w){const{width,height}=measure();if(w.maxOld){w.width=w.maxOld.width;w.height=w.maxOld.height;w.maxOld=null}else{w.maxOld={width:w.width,height:w.height};w.width=width*.82;w.height=height*.74}applyWindowSize(w);centerWindow(w)}
function installWindowInput(w){
  const head=$('.window-head',w.el),grip=$('.resizer',w.el);
  w.el.addEventListener('pointerdown',()=>focusWindow(w));
  head.addEventListener('click',event=>{
    const button=event.target.closest('[data-win]');if(!button)return;
    const action=button.dataset.win;event.stopPropagation();
    if(action==='close')closeWindow(w);else if(action==='min')minimizeWindow(w);
    else if(action==='max')maximizeWindow(w);else if(action==='center')centerWindow(w);
  });
  let drag=null;
  head.addEventListener('pointerdown',event=>{
    if(event.target.closest('button')||!event.isPrimary)return;
    const p=projection(w.dir);drag={id:event.pointerId,dx:p.x-event.clientX,dy:p.y-event.clientY};
    head.setPointerCapture(event.pointerId);focusWindow(w);event.preventDefault();
  });
  head.addEventListener('pointermove',event=>{
    if(!drag||drag.id!==event.pointerId)return;
    // Keep the window reachable while dragging; dragging outside the screen would
    // previously leave an untouchable spatial window behind.
    const safeX=clamp(event.clientX+drag.dx,30,innerWidth-30);
    const safeY=clamp(event.clientY+drag.dy,55,innerHeight-28);
    w.dir=rayAt(safeX,safeY);scheduleRender();
  });
  for(const type of ['pointerup','pointercancel','lostpointercapture'])head.addEventListener(type,()=>{if(drag){drag=null;saveLayout()}});
  let sizing=null;
  grip.addEventListener('pointerdown',event=>{if(!event.isPrimary)return;event.preventDefault();event.stopPropagation();sizing={id:event.pointerId,x:event.clientX,y:event.clientY,w:w.width,h:w.height};grip.setPointerCapture(event.pointerId);focusWindow(w)});
  grip.addEventListener('pointermove',event=>{if(!sizing||sizing.id!==event.pointerId)return;w.width=sizing.w+event.clientX-sizing.x;w.height=sizing.h+event.clientY-sizing.y;applyWindowSize(w);scheduleRender()});
  for(const type of ['pointerup','pointercancel','lostpointercapture'])grip.addEventListener(type,()=>{if(sizing){sizing=null;saveLayout()}});
}
function restoreWorkspace(){const saved=persistent.get('workspace',[]);const entries=Array.isArray(saved)?saved.slice(0,5).filter(w=>apps[w.kind]):[];
  if(entries.length){for(const item of entries)openWindow(item.kind,item)}else openWindow('apps');
}
function showApps(){openWindow('apps')}
function makeDock(){const entries=['apps','notes','spaces','hands','settings'];$('#dock').innerHTML=entries.map(name=>`<button class="dock-item" type="button" data-open="${name}" title="${apps[name][0]}">${glyph(apps[name][1])}<span>${apps[name][0]}</span></button>`).join('')}
makeDock();applySettings();

// Central event delegation keeps app buttons functional after remounting or focusing.
document.addEventListener('click',event=>{const button=event.target.closest('button[data-open]');if(button){openWindow(button.dataset.open)}});
$('#quickApps').addEventListener('click',showApps);
$('#quickSettings').addEventListener('click',()=>openWindow('settings'));
$('#recenter').addEventListener('click',()=>{if(requireStarted())recenterAll()});
$('#quickLens').addEventListener('click',async()=>{if(!requireStarted())return;const choice=settings.camera==='ultrawide'?'auto':'ultrawide';await switchCamera(choice);refreshCameraInfo()});
window.addEventListener('resize',()=>{for(const w of state.windows.values())applyWindowSize(w);scheduleRender()});
window.addEventListener('orientationchange',()=>setTimeout(()=>{for(const w of state.windows.values())applyWindowSize(w);scheduleRender()},160));
window.addEventListener('error',e=>{log('JavaScript: '+e.message);console.warn(e.message)});
window.addEventListener('unhandledrejection',e=>{log('Promise: '+String(e.reason?.message||e.reason))});

// Camera access uses exactly one video stream; the hand model analyzes that stream.
async function requestOrientation(){
  if(!settings.gyro)return false;
  try{
    if(typeof DeviceOrientationEvent!=='undefined'&&typeof DeviceOrientationEvent.requestPermission==='function'){
      const answer=await DeviceOrientationEvent.requestPermission();state.orientationAllowed=answer==='granted';
    }else state.orientationAllowed=typeof DeviceOrientationEvent!=='undefined';
  }catch(error){state.orientationAllowed=false;log('Permissão de movimento: '+error.message)}
  return state.orientationAllowed;
}
function formatCameraLabel(track){const id=track?.getSettings?.().deviceId;const known=state.cameras.find(d=>d.id===id);return known?.label||track?.label||'Câmera traseira (nome indisponível)'}
async function discoverCameras(){try{
  const devices=(await navigator.mediaDevices.enumerateDevices()).filter(d=>d.kind==='videoinput');
  state.cameras=devices.map((d,i)=>({id:d.deviceId,label:d.label||`Câmera ${i+1}`}));
}catch(error){state.cameras=[];log('Câmeras: '+error.message)}return state.cameras}
function ultraCamera(){return state.cameras.find(d=>/ultra[ -]?(wide|angular)|0[.,]5\s*x|0\.5\s*x/i.test(d.label))}
function cameraOptions(){
  const list=[{value:'ultrawide',label:'0,5x (tentar)'},{value:'auto',label:'Traseira automática'},...state.cameras.map(d=>({value:'device:'+d.id,label:d.label}))];
  return list.map(entry=>`<option value="${htmlEscape(entry.value)}" ${settings.camera===entry.value?'selected':''}>${htmlEscape(entry.label)}</option>`).join('');
}
function cameraTrack(){return state.stream?.getVideoTracks()?.[0]||null}
async function tryMinZoom(track){
  try{const caps=track?.getCapabilities?.();if(caps?.zoom&&Number.isFinite(caps.zoom.min)&&caps.zoom.min<1){
    await track.applyConstraints({advanced:[{zoom:caps.zoom.min}]});return caps.zoom.min;
  }}catch(error){log('Zoom mínimo: '+error.message)}return null;
}
async function startCamera(){
  if(!navigator.mediaDevices?.getUserMedia)throw new Error('Este navegador não disponibiliza a câmera. Use Safari com HTTPS.');
  const stream=await navigator.mediaDevices.getUserMedia({audio:false,video:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:720},frameRate:{ideal:30}}});
  const video=state.video;video.srcObject=stream;await video.play();state.stream=stream;
  await discoverCameras();
  if(settings.camera==='ultrawide'){
    const candidate=ultraCamera();
    if(candidate)await switchCamera('device:'+candidate.id,{silent:true,remember:false});
    else await tryMinZoom(cameraTrack());
  }else if(settings.camera.startsWith('device:')){
    const found=state.cameras.some(d=>settings.camera==='device:'+d.id);
    if(found)await switchCamera(settings.camera,{silent:true,remember:false});
    else {settings.camera='auto';saveSettings()}
  }
  refreshCameraInfo();return state.stream;
}
async function switchCamera(preference,{silent=false,remember=true}={}){
  if(!state.stream)return false;
  if(state.cameraSwitching)return false;
  const original=state.stream,oldTrack=cameraTrack();let candidate=null;
  if(preference.startsWith('device:'))candidate=state.cameras.find(d=>d.id===preference.slice(7));
  if(preference==='ultrawide')candidate=ultraCamera();
  if(preference==='ultrawide'&&!candidate){
    const zoom=await tryMinZoom(oldTrack);if(remember){settings.camera=preference;saveSettings()}
    if(!silent)toast(zoom!==null?`Zoom mínimo aplicado (${zoom.toFixed(2)}x), lente não confirmada`:'Safari não identificou a câmera 0,5x; usando traseira padrão');
    refreshCameraInfo();return zoom!==null;
  }
  if(preference.startsWith('device:')&&!candidate){if(!silent)toast('Câmera não encontrada; mantendo a atual');return false}
  const resumeHands=state.handRunning;
  state.cameraSwitching=true;
  if(resumeHands)stopHands({quiet:true}); // don't analyze frames while the stream changes
  try{
    // iOS often refuses two simultaneous camera tracks: release previous first.
    original.getTracks().forEach(t=>t.stop());
    const constraints=candidate?{deviceId:{exact:candidate.id},width:{ideal:1280},height:{ideal:720}}:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:720}};
    const stream=await navigator.mediaDevices.getUserMedia({video:constraints,audio:false});
    state.video.srcObject=stream;await state.video.play();state.stream=stream;
    if(remember){settings.camera=preference;saveSettings()}
    state.handLastVideo=-1;
    refreshCameraInfo();if(!silent)toast('Câmera: '+formatCameraLabel(cameraTrack()));return true;
  }catch(error){
    log('Troca de câmera: '+error.message);
    try{const fallback=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});state.video.srcObject=fallback;await state.video.play();state.stream=fallback}
    catch(fallbackError){log('Câmera fallback: '+fallbackError.message);toast('Não foi possível reativar a câmera. Recarregue o VR OS.',5000);return false}
    refreshCameraInfo();if(!silent)toast('Não foi possível trocar lente; câmera traseira restaurada');return false;
  }finally{
    state.cameraSwitching=false;
    if(resumeHands&&state.started&&state.stream?.active){
      const ok=await startHands();if(!ok)log('Rastreamento não voltou após troca de lente');
    }
  }
}
function refreshCameraInfo(){
  const label=formatCameraLabel(cameraTrack());
  const readout=$('#activeCameraName');if(readout)readout.textContent=label;
  const option=$('#cameraOptions');if(option)option.innerHTML=cameraOptions();
  $('#quickLens').style.color=settings.camera==='ultrawide'?'var(--accent)':'';
  log('Câmera: '+label);
}
async function startReality(){
  if(state.started||state.starting)return;state.starting=true;
  $('#start').disabled=true;$('#start').textContent='Preparando espaço...';$('#startError').textContent='';
  // Initiate sensor permission while the click is still a trusted user gesture.
  const orientationPermission=requestOrientation();
  try{
    await startCamera();await orientationPermission;
    state.started=true;document.body.classList.add('started');
    state.pose=qIdentity();state.poseTarget=null;state.poseReady=false;
    setStatus(state.orientationAllowed?'Câmera ligada • aguardando movimento':'Câmera ligada • toque para mover');
    state.dockDir=rayAt(innerWidth/2,innerHeight*(innerWidth>innerHeight?.9:.86));
    restoreWorkspace();scheduleRender();
    toast('VR OS iniciado. Gire o iPhone para explorar o espaço.');
  }catch(error){
    log('Início: '+error.message);$('#startError').textContent=error.name==='NotAllowedError'?'Permita o uso da câmera nas configurações do Safari.':(error.message||'Não foi possível abrir a câmera.');
    $('#start').disabled=false;$('#start').innerHTML=glyph('camera')+' Tentar novamente';
    state.stream?.getTracks().forEach(t=>t.stop());state.stream=null;state.started=false;
  }finally{state.starting=false}
}
$('#start').addEventListener('click',startReality);
function recoverInactiveCamera(){
  if(!state.started||state.stream?.active)return;
  state.started=false;state.stream=null;state.video.srcObject=null;
  document.body.classList.remove('started');
  stopHands({quiet:true});
  const button=$('#start');button.disabled=false;button.innerHTML=glyph('camera')+' Retomar câmera e espaço';
  $('#startError').textContent='O Safari interrompeu a câmera. Toque para continuar.';
  setStatus('Câmera interrompida','warn');log('Câmera interrompida; aguarda retomada manual');
}
window.addEventListener('pageshow',recoverInactiveCamera);

function makeTile(kind){return `<button type="button" class="app-tile" data-open="${kind}">${glyph(apps[kind][1])}<span>${apps[kind][0]}</span></button>`}
function layoutActions(){return `<div class="row"><button class="button" data-app-action="recenter">${glyph('focus')} Recentrar</button><button class="button" data-open="apps">${glyph('grid')} Apps</button></div>`}
function appHTML(kind){
  if(kind==='apps')return `<h2>Aplicativos</h2><p>Escolha uma janela para posicionar na realidade mista.</p><div class="app-grid">${Object.keys(apps).filter(k=>k!=='apps').map(makeTile).join('')}</div>`;
  if(kind==='home')return `<h2>Seu espaço, suas regras.</h2><p>Janelas posicionadas na direção para a qual você aponta o iPhone. Mova a cabeça ou o telefone; toque em Recentrar quando quiser.</p><div class="quick-grid"><div class="info-tile">${glyph('windows')}<strong>${state.windows.size}</strong><span>Janelas</span></div><div class="info-tile">${glyph('camera')}<strong>Ativa</strong><span>Câmera</span></div><div class="info-tile">${glyph('focus')}<strong>${state.poseReady?'Ligado':'Pendente'}</strong><span>Movimento</span></div></div><div class="rule"></div>${layoutActions()}`;
  if(kind==='notes')return `<h2>Bloco de notas</h2><textarea id="notesText" class="field notes-area" placeholder="Suas ideias ficam salvas neste dispositivo...">${htmlEscape(persistent.get('notes',''))}</textarea><p class="micro">Salvamento local automático.</p>`;
  if(kind==='clock')return `<h2>Relógio</h2><div class="clock-time" id="clockNow">--:--:--</div><p id="clockDate"></p><div class="rule"></div><h3>Cronômetro</h3><div id="clockStopwatch" class="clock-seconds">00:00.0</div><div class="row" style="margin-top:10px"><button type="button" class="button primary" id="timerToggle">Iniciar</button><button type="button" class="button" id="timerReset">Zerar</button></div>`;
  if(kind==='calc')return `<h2>Calculadora</h2><input id="calcScreen" class="field calc-result" readonly value="0" aria-label="Resultado"><div id="calcKeys" class="calc-grid">${['C','(',')','÷','7','8','9','×','4','5','6','−','1','2','3','+','0','.','⌫','='].map(v=>`<button type="button" data-key="${v}" class="${'+−×÷='.includes(v)?'op':''}">${v}</button>`).join('')}</div>`;
  if(kind==='files')return `<div class="row between"><h2>Arquivos</h2><button type="button" class="button primary small" id="fileImport">${glyph('plus')} Importar</button></div><div id="filesList"></div><p class="micro">Arquivos guardados no armazenamento local do navegador.</p>`;
  if(kind==='gallery')return `<div class="row between"><h2>Galeria</h2><div class="row"><button type="button" class="button small" id="capture">${glyph('camera')} Capturar</button><button type="button" class="button primary small" id="photoImport">${glyph('plus')} Fotos</button></div></div><div id="galleryList"></div>`;
  if(kind==='music')return `<div class="row between"><h2>Música</h2><button type="button" class="button primary small" id="musicImport">${glyph('plus')} Adicionar</button></div><div id="musicList"></div><div id="audioContainer"></div><p class="micro">Reproduza arquivos de áudio escolhidos por você.</p>`;
  if(kind==='calendar')return `<div class="row between"><h2>Calendário</h2><span id="calendarMonth" class="pill"></span></div><div class="row" style="margin-bottom:10px"><button class="button small" id="monthPrev">◀ Anterior</button><button class="button small" id="monthNext">Próximo ▶</button></div><div id="calendarGrid"></div><div class="rule"></div><div class="row"><input id="eventDate" type="date" class="field" style="flex:1;min-width:120px" aria-label="Data"><input id="eventTitle" class="field" placeholder="Novo evento" style="flex:2;min-width:150px" aria-label="Título do evento"><button class="button primary" id="eventAdd">Adicionar</button></div><div id="calendarEvents" style="margin-top:10px"></div>`;
  if(kind==='hands')return `<h2>Controle com as mãos</h2><p>Mostre a mão para a câmera traseira. O indicador controla o cursor, a pinça clica, e uma pinça no título move a janela. Use duas mãos para redimensionar.</p><div class="row"><button class="button primary" id="handsToggle">${glyph('hand')} Ativar gestos</button><span class="pill" id="handsState">Desligado</span></div><div class="setting-row"><span>Mostrar pontos da mão (diagnóstico)</span><input id="pointsToggle" type="checkbox" ${settings.showPoints?'checked':''}></div><div class="setting-row"><span>Espelhar cursor</span><input id="mirrorToggle" type="checkbox" ${settings.mirror?'checked':''}></div><div class="setting-row"><span>Sensibilidade</span><input id="handSensitivity" type="range" min=".15" max=".8" step=".05" value="${settings.handSensitivity}"></div><div class="setting-row"><span>FPS máximo</span><select id="handFpsSelect"><option value="10" ${settings.handsFps===10?'selected':''}>10 (econômico)</option><option value="15" ${settings.handsFps===15?'selected':''}>15 (equilibrado)</option><option value="20" ${settings.handsFps===20?'selected':''}>20 (rápido)</option></select></div><p id="handsError" class="micro"></p><p class="micro">A câmera é compartilhada com o ambiente. Sem recortes artificiais da mão e sem profundidade real no Safari.</p>`;
  if(kind==='settings')return `<h2>Ajustes do espaço</h2>
    <div class="setting-row"><span>Câmera / lente</span><select id="cameraOptions" aria-label="Lente">${cameraOptions()}</select></div>
    <p class="micro">Em uso: <span id="activeCameraName">${htmlEscape(formatCameraLabel(cameraTrack()))}</span>. A opção 0,5x só funciona se o navegador expuser a lente ou o zoom mínimo.</p>
    <div class="setting-row"><span>Giroscópio</span><input id="gyroSetting" type="checkbox" ${settings.gyro?'checked':''}></div>
    <div class="setting-row"><span>Tamanho das janelas</span><input id="scaleSetting" type="range" min=".75" max="1.18" step=".05" value="${settings.scale}"></div>
    <div class="setting-row"><span>Transparência</span><input id="opacitySetting" type="range" min=".58" max=".94" step=".02" value="${settings.opacity}"></div>
    <div class="setting-row"><span>Cor de destaque</span><input id="accentSetting" type="color" value="${settings.accent}"></div>
    <div class="setting-row"><span>Reduzir animações</span><input id="motionSetting" type="checkbox" ${settings.reduceMotion?'checked':''}></div>
    <div class="row" style="margin-top:14px"><button class="button" id="cameraScan">${glyph('camera')} Procurar lentes</button><button class="button" id="settingsReset">Restaurar ajustes</button><button class="button" id="fullscreenSetting">${glyph('expand')} Tela cheia</button></div>`;
  if(kind==='spaces')return `<div class="row between"><h2>Gerenciador de janelas</h2><button class="button small" id="windowsRecenter">${glyph('focus')} Recentrar</button></div><div id="windowItems"></div><div class="row"><button class="button danger" id="closeAll">${glyph('trash')} Fechar tudo</button><button class="button" data-open="apps">${glyph('plus')} Nova janela</button></div>`;
  if(kind==='about')return `<h2>VR OS Spatial 2.3</h2><p>Um sistema espacial experimental que roda no navegador, criado em HTML, CSS e JavaScript.</p><div class="stack"><div class="setting-row"><span>Câmera</span><span id="aboutCamera">${htmlEscape(formatCameraLabel(cameraTrack()))}</span></div><div class="setting-row"><span>Orientação</span><span id="aboutSensor">${state.poseReady?'Detectada':'Indisponível/aguardando'}</span></div><div class="setting-row"><span>Rastreamento de mãos</span><span id="aboutHands">${state.handRunning?'Ativo':'Desligado'}</span></div><div class="setting-row"><span>Armazenamento</span><span>Local ao aparelho</span></div></div><div class="rule"></div><p class="micro">Limite técnico: o Safari não oferece ancoragem de posição ARKit a uma página web. A orientação muda a projeção das janelas, mas andar pela sala não gera deslocamento 3D real.</p><div class="row between"><h3>Diagnóstico</h3><button class="button small" id="copyDiagnostics" type="button">Copiar registro</button></div><pre id="debugText" style="white-space:pre-wrap;font:10px/1.5 ui-monospace,monospace;color:var(--secondary)">${htmlEscape(state.logs.join('\n'))}</pre>`;
  return `<h2>Aplicativo indisponível</h2>`;
}
function on(el,type,cb,w){if(!el)return;el.addEventListener(type,cb);w.disposers.push(()=>el.removeEventListener(type,cb))}
function mountApp(w){
  const content=$('.window-content',w.el);content.innerHTML=appHTML(w.kind);
  const find=id=>content.querySelector('#'+id),kind=w.kind;
  if(kind==='home')on(content,'click',e=>{if(e.target.closest('[data-app-action="recenter"]'))recenterAll()},w);
  if(kind==='notes')on(find('notesText'),'input',e=>persistent.set('notes',e.target.value),w);
  if(kind==='calc')mountCalculator(w,content);
  if(kind==='clock')mountClock(w,find);
  if(kind==='files'||kind==='gallery'||kind==='music')mountLibrary(w,find);
  if(kind==='calendar')mountCalendar(w,find);
  if(kind==='hands')mountHands(w,find);
  if(kind==='settings')mountSettings(w,find);
  if(kind==='spaces')mountSpaces(w,find);
  if(kind==='about'){
    on(content,'click',async e=>{if(!e.target.closest('#copyDiagnostics'))return;
      try{await navigator.clipboard.writeText(`VR OS 2.3\n${navigator.userAgent}\n${state.logs.join('\n')}`);toast('Diagnóstico copiado')}
      catch{toast('Abra o diagnóstico e copie o texto manualmente')}
    },w);
    const interval=setInterval(()=>{if(w.el.isConnected){find('aboutSensor').textContent=state.poseReady?'Orientação ativa':'Aguardando/indisponível';find('aboutHands').textContent=state.handRunning?'Ativo':'Desligado';find('debugText').textContent=state.logs.join('\n');}},1000);
    w.disposers.push(()=>clearInterval(interval));
  }
}

function evaluateExpression(input){
  const clean=input.replace(/\s+/g,'').replaceAll('×','*').replaceAll('÷','/').replaceAll('−','-');
  if(!/^[\d.()+\-*/]+$/.test(clean))throw Error('Caractere inválido');
  const tokens=clean.match(/(?:\d+\.?\d*|\.\d+|[()+\-*/])/g)||[];
  if(tokens.join('')!==clean)throw Error('Formato inválido');
  let index=0;
  function factor(){const t=tokens[index++];if(t==='+'||t==='-')return(t==='-'?-1:1)*factor();if(t==='('){const r=expr();if(tokens[index++]!==')')throw Error('Parênteses');return r}const n=Number(t);if(t===undefined||!Number.isFinite(n))throw Error('Número inválido');return n}
  function term(){let n=factor();while(tokens[index]==='*'||tokens[index]==='/'){const op=tokens[index++],b=factor();n=op==='*'?n*b:n/b}return n}
  function expr(){let n=term();while(tokens[index]==='+'||tokens[index]==='-'){const op=tokens[index++],b=term();n=op==='+'?n+b:n-b}return n}
  const result=expr();if(index!==tokens.length||!Number.isFinite(result))throw Error('Expressão inválida');return String(Number(result.toPrecision(11)));
}
function mountCalculator(w,content){let expression='';on(content.querySelector('#calcKeys'),'click',event=>{const button=event.target.closest('[data-key]');if(!button)return;const key=button.dataset.key,screen=content.querySelector('#calcScreen');
  if(key==='C')expression='';else if(key==='⌫')expression=expression.slice(0,-1);
  else if(key==='='){try{expression=evaluateExpression(expression)}catch{expression='Erro'}}
  else{if(expression==='Erro')expression='';expression+=key}
  screen.value=expression||'0';},w);
}
function stopwatchMs(){return state.stopwatch.elapsed+(state.stopwatch.active?Date.now()-state.stopwatch.since:0)}
function stopwatchText(ms){const s=Math.floor(ms/1000),m=Math.floor(s/60),d=Math.floor((ms%1000)/100);return `${String(m).padStart(2,'0')}:${String(s%60).padStart(2,'0')}.${d}`}
function mountClock(w,find){const refresh=()=>{const now=new Date();find('clockNow').textContent=now.toLocaleTimeString('pt-BR');find('clockDate').textContent=now.toLocaleDateString('pt-BR',{weekday:'long',month:'long',day:'numeric'});find('clockStopwatch').textContent=stopwatchText(stopwatchMs());find('timerToggle').textContent=state.stopwatch.active?'Pausar':'Iniciar'};
  on(find('timerToggle'),'click',()=>{if(state.stopwatch.active){state.stopwatch.elapsed+=Date.now()-state.stopwatch.since;state.stopwatch.active=false}else{state.stopwatch.active=true;state.stopwatch.since=Date.now()}refresh()},w);
  on(find('timerReset'),'click',()=>{state.stopwatch.elapsed=0;state.stopwatch.active=false;refresh()},w);
  refresh();const interval=setInterval(refresh,150);w.disposers.push(()=>clearInterval(interval));
}

// Files, photos and music use the browser's persistent IndexedDB (memory fallback).
function fileId(){return crypto.randomUUID?.()||('vr-'+Date.now()+'-'+Math.random().toString(36).slice(2))}
function dbOpen(){return new Promise(resolve=>{
  if(!('indexedDB'in window)){resolve(null);return}
  let settled=false;const complete=db=>{if(settled)return;settled=true;clearTimeout(timer);resolve(db)};
  const timer=setTimeout(()=>{log('Armazenamento local demorou para responder');complete(null)},2800);
  try{const request=indexedDB.open('VR-OS-Storage',2);
    request.onupgradeneeded=()=>{if(!request.result.objectStoreNames.contains('assets'))request.result.createObjectStore('assets',{keyPath:'id'})};
    request.onsuccess=()=>{const db=request.result;if(settled){db.close();return}db.onversionchange=()=>{db.close();state.db=null;state.dbPromise=null};complete(db)};
    request.onerror=()=>complete(null);request.onblocked=()=>log('IndexedDB bloqueado por outra aba');
  }catch{complete(null)}
})}
async function fileDB(){if(state.db)return state.db;if(!state.dbPromise)state.dbPromise=dbOpen();state.db=await state.dbPromise;return state.db}
async function filePut(file,category){const entry={id:fileId(),name:file.name||'Arquivo',type:file.type||'application/octet-stream',size:file.size||0,created:Date.now(),category,blob:file};const db=await fileDB();if(!db){state.memoryFiles.set(entry.id,entry);return entry}
  return new Promise((resolve,reject)=>{const transaction=db.transaction('assets','readwrite');transaction.objectStore('assets').put(entry);transaction.oncomplete=()=>resolve(entry);transaction.onerror=()=>reject(transaction.error)})}
async function fileList(category){const db=await fileDB();let entries=[];if(!db)entries=[...state.memoryFiles.values()];else entries=await new Promise(resolve=>{const request=db.transaction('assets','readonly').objectStore('assets').getAll();request.onsuccess=()=>resolve(request.result||[]);request.onerror=()=>resolve([])});return entries.filter(e=>!category||e.category===category).sort((a,b)=>b.created-a.created)}
async function fileGet(id){const db=await fileDB();if(!db)return state.memoryFiles.get(id);return new Promise(resolve=>{const request=db.transaction('assets','readonly').objectStore('assets').get(id);request.onsuccess=()=>resolve(request.result);request.onerror=()=>resolve(null)})}
async function fileDelete(id){const db=await fileDB();if(!db){state.memoryFiles.delete(id);return}await new Promise(resolve=>{const request=db.transaction('assets','readwrite').objectStore('assets').delete(id);request.onsuccess=()=>resolve();request.onerror=()=>resolve()})}
function chooseFiles(accept,callback){const input=$('#filePicker');input.value='';input.accept=accept;input.onchange=async()=>{const files=[...(input.files||[])];try{await callback(files)}catch(error){log('Importação: '+error.message);toast('Erro ao importar arquivo: '+error.message)}input.value=''};input.click()}
async function downloadFile(id){const item=await fileGet(id);if(!item)return;const url=URL.createObjectURL(item.blob);const link=document.createElement('a');link.href=url;link.download=item.name;document.body.appendChild(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),5000)}
function prettyBytes(n){return n>=1048576?(n/1048576).toFixed(1)+' MB':n>=1024?(n/1024).toFixed(0)+' KB':n+' B'}
function mountLibrary(w,find){const kind=w.kind;let urls=[];let alive=true;const clean=()=>{urls.forEach(url=>URL.revokeObjectURL(url));urls=[]};w.disposers.push(()=>{alive=false;clean();if(kind==='music'&&state.audio){state.audio.pause();state.audio=null}});
  const render=async()=>{
    const entries=await fileList(kind==='gallery'?'photo':kind==='music'?'audio':null);
    if(!alive)return;clean();
    if(kind==='files'){
      find('filesList').innerHTML=entries.length?entries.map(e=>`<div class="item-row" data-id="${e.id}">${glyph('folder')}<span class="label" title="${htmlEscape(e.name)}">${htmlEscape(e.name)}</span><span class="size">${prettyBytes(e.size)}</span><button class="button small" data-file="download" title="Baixar">${glyph('download')}</button><button class="button small danger" data-file="delete" title="Excluir">${glyph('trash')}</button></div>`).join(''):`<div class="empty">${glyph('folder')}Nenhum arquivo importado</div>`;
    }else if(kind==='gallery'){
      const items=entries.map(e=>{const url=URL.createObjectURL(e.blob);urls.push(url);return`<div class="photo-card" data-id="${e.id}"><img src="${url}" alt="${htmlEscape(e.name)}"><button data-file="delete" title="Excluir foto">${glyph('trash')}</button></div>`}).join('');
      find('galleryList').innerHTML=items?`<div class="photos">${items}</div>`:`<div class="empty">${glyph('photo')}Nenhuma foto ainda</div>`;
    }else{
      find('musicList').innerHTML=entries.length?entries.map(e=>`<div class="item-row" data-id="${e.id}">${glyph('music')}<span class="label">${htmlEscape(e.name)}</span><button class="button small" data-file="play">${glyph('play')}</button><button class="button small danger" data-file="delete">${glyph('trash')}</button></div>`).join(''):`<div class="empty">${glyph('music')}Adicione um áudio para ouvir</div>`;
    }
  };
  const target=kind==='files'?find('filesList'):kind==='gallery'?find('galleryList'):find('musicList');
  on(target,'click',async event=>{const action=event.target.closest('[data-file]');if(!action)return;const id=action.closest('[data-id]')?.dataset.id;if(!id)return;
    if(action.dataset.file==='download')await downloadFile(id);
    if(action.dataset.file==='delete'){await fileDelete(id);render()}
    if(action.dataset.file==='play'){
      const item=await fileGet(id);if(!item)return;
      if(state.audio){state.audio.pause();state.audio=null}
      clean();const url=URL.createObjectURL(item.blob);urls.push(url);
      const container=find('audioContainer');container.innerHTML=`<p class="micro">${htmlEscape(item.name)}</p><audio class="audio-player" controls autoplay></audio>`;
      const audio=container.querySelector('audio');state.audio=audio;audio.src=url;
      audio.play().catch(()=>toast('Toque em reproduzir para iniciar o áudio.'));
    }
  },w);
  if(kind==='files')on(find('fileImport'),'click',()=>chooseFiles('*/*',async files=>{for(const file of files)await filePut(file,file.type.startsWith('image/')?'photo':file.type.startsWith('audio/')?'audio':'file');render();toast(files.length+' arquivo(s) importado(s)')}),w);
  if(kind==='gallery'){
    on(find('photoImport'),'click',()=>chooseFiles('image/*',async files=>{for(const file of files.filter(f=>f.type.startsWith('image/')))await filePut(file,'photo');render()}),w);
    on(find('capture'),'click',async()=>{
      if(state.video.readyState<2){toast('Câmera ainda não está pronta');return}
      const canvas=document.createElement('canvas');canvas.width=state.video.videoWidth;canvas.height=state.video.videoHeight;canvas.getContext('2d').drawImage(state.video,0,0);
      const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',.86));if(!blob){toast('Não foi possível capturar');return}
      const image=new File([blob],`VR-OS-${new Date().toISOString().replace(/[:.]/g,'-')}.jpg`,{type:'image/jpeg'});await filePut(image,'photo');render();toast('Foto capturada e salva');
    },w);
  }
  if(kind==='music')on(find('musicImport'),'click',()=>chooseFiles('audio/*',async files=>{for(const file of files.filter(f=>f.type.startsWith('audio/')))await filePut(file,'audio');render()}),w);
  render().catch(error=>log('Arquivos: '+error.message));
}

function localDateISO(d=new Date()){return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function mountCalendar(w,find){let month=0;const events=persistent.get('events',[]);if(!Array.isArray(events))return;
  find('eventDate').value=localDateISO(new Date());
  const render=()=>{
    const now=new Date(),monthDate=new Date(now.getFullYear(),now.getMonth()+month,1),year=monthDate.getFullYear(),m=monthDate.getMonth();
    find('calendarMonth').textContent=monthDate.toLocaleDateString('pt-BR',{month:'long',year:'numeric'});
    const first=(new Date(year,m,1).getDay()+6)%7,days=new Date(year,m+1,0).getDate();
    let html='<div class="quick-grid" style="grid-template-columns:repeat(7,1fr);gap:3px">';
    for(const day of ['S','T','Q','Q','S','S','D'])html+=`<span class="micro" style="text-align:center">${day}</span>`;
    for(let i=0;i<first;i++)html+='<span></span>';
    for(let d=1;d<=days;d++){
      const date=`${year}-${String(m+1).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
      const marked=events.some(e=>e.date===date);const today=localDateISO(new Date())===date;
      html+=`<button type="button" class="button small" data-date="${date}" style="min-width:0;padding:5px 0;${marked?'border-color:var(--accent);':''}${today?'background:rgba(170,203,247,.22);':''}">${d}</button>`;
    }
    find('calendarGrid').innerHTML=html+'</div>';
    find('calendarEvents').innerHTML=events.length?events.slice().sort((a,b)=>a.date.localeCompare(b.date)).map(e=>`<div class="item-row" data-event="${e.id}"><span class="micro">${e.date.split('-').reverse().join('/')}</span><span class="label">${htmlEscape(e.title)}</span><button class="button small danger" data-delete-event="1">${glyph('close')}</button></div>`).join(''):'<div class="empty">Nenhum evento salvo</div>';
    persistent.set('events',events);
  };
  on(find('monthPrev'),'click',()=>{month--;render()},w);on(find('monthNext'),'click',()=>{month++;render()},w);
  on(find('calendarGrid'),'click',e=>{const btn=e.target.closest('[data-date]');if(btn)find('eventDate').value=btn.dataset.date},w);
  on(find('eventAdd'),'click',()=>{const title=find('eventTitle').value.trim(),date=find('eventDate').value;if(!title||!date){toast('Informe data e título');return}events.push({id:fileId(),date,title});find('eventTitle').value='';render();toast('Evento adicionado')},w);
  on(find('calendarEvents'),'click',e=>{const b=e.target.closest('[data-delete-event]');if(!b)return;const idx=events.findIndex(v=>v.id===b.closest('[data-event]').dataset.event);if(idx>=0){events.splice(idx,1);render()}},w);render();
}
function mountSpaces(w,find){const draw=()=>{if(!w.el.isConnected)return;const list=[...state.windows.values()];find('windowItems').innerHTML=list.map(item=>`<div class="item-row" data-target="${item.id}">${glyph(apps[item.kind][1])}<span class="label">${apps[item.kind][0]}</span><button class="button small" data-space="focus">Trazer</button><button class="button small danger" data-space="close">${glyph('close')}</button></div>`).join('')};
  on(find('windowItems'),'click',e=>{const action=e.target.closest('[data-space]');if(!action)return;const item=state.windows.get(Number(action.closest('[data-target]').dataset.target));if(!item)return;if(action.dataset.space==='close')closeWindow(item);else centerWindow(item);if(w.el.isConnected)draw()},w);
  on(find('closeAll'),'click',()=>{[...state.windows.values()].forEach(closeWindow)},w);
  on(find('windowsRecenter'),'click',()=>recenterAll(),w);
  const timer=setInterval(draw,1200);w.disposers.push(()=>clearInterval(timer));draw();
}

function mountSettings(w,find){
  const update=(name,value)=>{settings[name]=value;saveSettings()};
  on(find('cameraOptions'),'change',async event=>{
    const preference=event.target.value;const ok=await switchCamera(preference);
    if(!ok && preference.startsWith('device:'))event.target.value=settings.camera;
    refreshCameraInfo();
  },w);
  on(find('gyroSetting'),'change',async event=>{
    settings.gyro=event.target.checked;saveSettings();
    if(settings.gyro){const permitted=await requestOrientation();state.poseReady=false;state.pose=qIdentity();state.poseTarget=null;recenterAll(true);if(!permitted)toast('Movimento não autorizado; janelas permanecem na tela')}
    else{state.poseReady=false;state.pose=qIdentity();state.poseTarget=null;recenterAll(true);setStatus('Câmera • giroscópio desligado')}
  },w);
  on(find('scaleSetting'),'input',event=>update('scale',Number(event.target.value)),w);
  on(find('opacitySetting'),'input',event=>update('opacity',Number(event.target.value)),w);
  on(find('accentSetting'),'input',event=>update('accent',event.target.value),w);
  on(find('motionSetting'),'change',event=>update('reduceMotion',event.target.checked),w);
  on(find('cameraScan'),'click',async()=>{await discoverCameras();refreshCameraInfo();toast(`${state.cameras.length} câmera(s) disponíveis`)},w);
  on(find('settingsReset'),'click',()=>{Object.assign(settings,defaults);saveSettings();toast('Ajustes restaurados');mountApp(w)},w);
  on(find('fullscreenSetting'),'click',async()=>{try{if(!document.fullscreenElement&&document.documentElement.requestFullscreen)await document.documentElement.requestFullscreen();else if(document.fullscreenElement&&document.exitFullscreen)await document.exitFullscreen();else throw Error('indisponível')}catch{toast('No iPhone, use Safari > Compartilhar > Adicionar à Tela de Início',5500)}},w);
}
function mountHands(w,find){
  function show(){const enabled=state.handRunning;find('handsToggle').innerHTML=glyph('hand')+(enabled?' Desativar gestos':' Ativar gestos');find('handsState').textContent=enabled?`${state.handCount} mão(s), ${state.handFps} FPS`:'Desligado'}
  on(find('handsToggle'),'click',async()=>{if(state.handRunning)stopHands();else await startHands();show()},w);
  on(find('pointsToggle'),'change',e=>{settings.showPoints=e.target.checked;saveSettings()},w);
  on(find('mirrorToggle'),'change',e=>{settings.mirror=e.target.checked;saveSettings()},w);
  on(find('handSensitivity'),'input',e=>{settings.handSensitivity=Number(e.target.value);saveSettings()},w);
  on(find('handFpsSelect'),'change',e=>{settings.handsFps=Number(e.target.value);saveSettings()},w);
  const interval=setInterval(()=>{if(find('handsState'))show()},450);w.disposers.push(()=>clearInterval(interval));show();
}

// Gesture control uses 21 2-D hand landmarks. It deliberately DOES NOT draw a fake silhouette.
const MP='https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.1.1';
const MODEL='https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';
async function startHands(){
  if(state.handRunning)return true;if(!state.started||!state.stream?.active){toast('Inicie a câmera do espaço primeiro');return false}
  const button=$('#handsToggle');if(button){button.disabled=true;button.textContent='Carregando modelo...'}
  let step='Biblioteca';
  try{
    if(!state.handModel){
      const {FilesetResolver,HandLandmarker}=await import(MP+'/vision_bundle.mjs');
      step='WebAssembly';const fileset=await FilesetResolver.forVisionTasks(MP+'/wasm');
      step='Modelo de mãos';
      const options={baseOptions:{modelAssetPath:MODEL,delegate:'GPU'},runningMode:'VIDEO',numHands:2,minHandDetectionConfidence:.58,minHandPresenceConfidence:.55,minTrackingConfidence:.53};
      try{state.handModel=await HandLandmarker.createFromOptions(fileset,options)}
      catch(gpuError){log('GPU indisponível, tentando CPU');options.baseOptions.delegate='CPU';state.handModel=await HandLandmarker.createFromOptions(fileset,options)}
    }
    if(!state.stream?.active)throw Error('A câmera não está ativa.');
    state.handRunning=true;state.handLastVideo=-1;state.handLastTick=0;state.handCount=0;state.landmarkErrors=0;
    document.body.classList.add('hand-control-active');
    state.pointers=[{position:null,pinch:false,frames:0},{position:null,pinch:false,frames:0}];
    state.handLoop=requestAnimationFrame(handFrame);
    toast('Gestos ativados. Mostre as mãos à câmera traseira.');return true;
  }catch(error){
    const message=`${step}: ${error.message||error}`;state.lastError=message;log('Gestos: '+message);
    toast('Falha no rastreamento: '+message.slice(0,110),6000);
    const info=$('#handsError');if(info)info.textContent=message;
    stopHands({quiet:true});return false;
  }finally{if(button)button.disabled=false}
}
function stopHands({quiet=false}={}){
  state.handRunning=false;cancelAnimationFrame(state.handLoop);state.handLoop=0;state.gesture=null;
  document.body.classList.remove('hand-control-active');$$('.spatial-window.hand-near').forEach(el=>el.classList.remove('hand-near'));
  for(let i=0;i<2;i++){const dot=$('#handCursor'+(i+1));dot.style.display='none'}
  if(state.hover){state.hover.classList.remove('hand-hover');state.hover=null}
  const canvas=$('#landmarkCanvas');canvas.getContext('2d')?.clearRect(0,0,canvas.width,canvas.height);
  // Retain the compiled model across pause/resume; close on unload.
  if(!quiet)toast('Gestos desativados');setStatus(state.poseReady?'Câmera • movimento ativo':'Câmera ativa');
}
function videoPoint(handPoint,video){
  const{width,height}=measure(),sw=video.videoWidth||1280,sh=video.videoHeight||720;
  const factor=Math.max(width/sw,height/sh),rw=sw*factor,rh=sh*factor;
  const x=(settings.mirror?1-handPoint.x:handPoint.x)*rw+(width-rw)/2;
  return{x,y:handPoint.y*rh+(height-rh)/2};
}
const distance2=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
function renderHandDebug(hands,video){
  const canvas=$('#landmarkCanvas');if(!settings.showPoints){if(canvas.width)canvas.getContext('2d').clearRect(0,0,canvas.width,canvas.height);return}
  const{width,height}=measure(),ratio=Math.min(2,devicePixelRatio||1);
  if(canvas.width!==Math.round(width*ratio)||canvas.height!==Math.round(height*ratio)){canvas.width=Math.round(width*ratio);canvas.height=Math.round(height*ratio)}
  const ctx=canvas.getContext('2d');ctx.setTransform(ratio,0,0,ratio,0,0);ctx.clearRect(0,0,width,height);ctx.strokeStyle='rgba(197,224,255,.73)';ctx.fillStyle='rgba(204,233,255,.88)';ctx.lineWidth=1.4;
  const segments=[[0,1,2,3,4],[0,5,6,7,8],[5,9,10,11,12],[9,13,14,15,16],[13,17,18,19,20],[0,17]];
  for(const hand of hands){const pts=hand.map(p=>videoPoint(p,video));for(const seg of segments){ctx.beginPath();seg.forEach((n,i)=>i?ctx.lineTo(pts[n].x,pts[n].y):ctx.moveTo(pts[n].x,pts[n].y));ctx.stroke()}
    for(const p of pts){ctx.beginPath();ctx.arc(p.x,p.y,2.4,0,Math.PI*2);ctx.fill()}}
}
function handFrame(now){
  if(!state.handRunning)return;
  state.handLoop=requestAnimationFrame(handFrame);
  if(document.hidden||state.video.readyState<2)return;
  if(now-state.handLastTick<1000/settings.handsFps||state.video.currentTime===state.handLastVideo)return;
  state.handLastTick=now;state.handLastVideo=state.video.currentTime;
  try{
    const result=state.handModel.detectForVideo(state.video,now),hands=result.landmarks||[];
    state.handCount=hands.length;state.landmarkErrors=0;
    if(state.handLastFrame)state.handFps=Math.round(1000/Math.max(1,now-state.handLastFrame));
    state.handLastFrame=now;
    renderHandDebug(hands,state.video);
    // Stable visual left-to-right assignment; the first pointer clicks, second resizes.
    let sorted=[...hands].sort((a,b)=>a[8].x-b[8].x);
    if(sorted.length===1&&state.pointers[1].position){
      const p=videoPoint(sorted[0][8],state.video);
      if(!state.pointers[0].position||distance2(p,state.pointers[1].position)+28<distance2(p,state.pointers[0].position))sorted=[null,sorted[0]];
    }
    if(sorted.length===2&&state.pointers[0].position&&state.pointers[1].position){
      const first=videoPoint(sorted[0][8],state.video),second=videoPoint(sorted[1][8],state.video);
      const direct=distance2(first,state.pointers[0].position)+distance2(second,state.pointers[1].position);
      const inverse=distance2(second,state.pointers[0].position)+distance2(first,state.pointers[1].position);
      if(inverse+22<direct)sorted.reverse();
    }
    const current=[];
    for(let i=0;i<2;i++){
      const lm=sorted[i],pointer=state.pointers[i],cursor=$('#handCursor'+(i+1));
      if(!lm){cursor.style.display='none';pointer.position=null;pointer.pinch=false;pointer.frames=0;current.push(null);continue}
      const raw=videoPoint(lm[8],state.video),previous=pointer.position;
      const factor=clamp(settings.handSensitivity,.15,.8);
      const position=previous?{x:previous.x+(raw.x-previous.x)*factor,y:previous.y+(raw.y-previous.y)*factor}:raw;
      const width=Math.max(.045,distance2(lm[5],lm[17]));
      const ratio=distance2(lm[4],lm[8])/width;
      const intent=pointer.pinch?ratio<.65:ratio<.46;
      pointer.frames=clamp(pointer.frames+(intent?1:-1),-3,3);
      const pinched=pointer.pinch?pointer.frames>-2:pointer.frames>=2;
      pointer.position=position;pointer.pinch=pinched;
      cursor.style.display='block';cursor.style.left=position.x+'px';cursor.style.top=position.y+'px';cursor.classList.toggle('pinch',pinched);
      current.push({position,pinched});
    }
    if(current[0])dispatchHandGesture(current[0].position,current[0].pinched,current[1]);
    else if(current[1])dispatchHandGesture(current[1].position,current[1].pinched,null);
    else{clearHover();$$('.spatial-window.hand-near').forEach(el=>el.classList.remove('hand-near'));
      if(state.gesture)finishGesture(state.gesture,lastPointer(state.gesture),{cancelled:true});}
    setStatus(`${state.handCount} mão(s) • ${state.handFps} FPS`);
  }catch(error){
    state.landmarkErrors++;log('Rastreamento: '+error.message);state.lastError=error.message;
    // Transient GPU context errors happen on Safari after backgrounding; stop only
    // after a few consecutive failures, instead of killing gestures on one frame.
    if(state.landmarkErrors>=3){stopHands({quiet:true});toast('Gestos interrompidos: '+error.message.slice(0,110),5000)}
  }
}
function lastPointer(g){return state.pointers[0].position||g.origin}
function clearHover(){if(state.hover){state.hover.classList.remove('hand-hover');state.hover=null}}
function dispatchHandGesture(point,pinched,second){
  const hover=document.elementFromPoint(point.x,point.y);
  const hoveringWindow=hover?.closest('.spatial-window');
  $$('.spatial-window.hand-near').forEach(el=>{if(el!==hoveringWindow)el.classList.remove('hand-near')});
  if(hoveringWindow)hoveringWindow.classList.add('hand-near');
  if(!state.gesture){
    const candidate=hover?.closest('button,input,textarea,select,a');
    if(candidate!==state.hover){clearHover();if(candidate){candidate.classList.add('hand-hover');state.hover=candidate}}
  }
  if(pinched&&!state.gesture){
    const windowElement=hover?.closest('.spatial-window');
    const w=windowElement?state.windows.get(Number(windowElement.dataset.windowId)):null;
    if(w)focusWindow(w);
    const clickable=hover?.closest('button,input,textarea,select,a');
    const p=w?projection(w.dir):null;
    state.gesture={w,target:clickable||hover,origin:point,startCenter:p?{x:p.x,y:p.y}:null,mode:w&&hover?.closest('.window-head')&&!clickable?'drag':'tap',didMove:false,startWidth:w?.width||0,startHeight:w?.height||0,pairDistance:null};
  }
  const g=state.gesture;if(!g)return;
  if(pinched&&g.w){
    if(second?.pinched){
      const dist=distance2(point,second.position);
      if(!g.pairDistance){g.pairDistance=Math.max(dist,35);g.startWidth=g.w.width;g.startHeight=g.w.height}
      const factor=clamp(dist/g.pairDistance,.62,1.75);
      g.w.width=g.startWidth*factor;g.w.height=g.startHeight*factor;applyWindowSize(g.w);g.mode='resize';g.didMove=true;
    }else if(g.mode==='drag'){
      const deltaX=point.x-g.origin.x,deltaY=point.y-g.origin.y;
      if(Math.hypot(deltaX,deltaY)>7)g.didMove=true;
      g.w.dir=rayAt(g.startCenter.x+deltaX,g.startCenter.y+deltaY);
    }
    scheduleRender();
  }
  if(!pinched)finishGesture(g,point);
}
function finishGesture(g,point,{cancelled=false}={}){
  if(!cancelled&&g.mode==='tap'&&!g.didMove&&distance2(point,g.origin)<42){
    // Click window chrome and internal controls; iOS requires real touch for file pickers.
    const target=g.target;
    if(target?.isConnected){if(target.matches('input[type=range]')){
      const rect=target.getBoundingClientRect(),ratio=clamp((point.x-rect.left)/rect.width,0,1);
      target.value=String(Number(target.min)+ratio*(Number(target.max)-Number(target.min)));
      target.dispatchEvent(new Event('input',{bubbles:true}));
    }else if(target.matches('button,input[type=checkbox],a'))target.click();
    else if(target.matches('input,textarea,select'))target.focus()}
  }
  state.gesture=null;saveLayout();
}

// File and camera tracks are never requested in the background.
document.addEventListener('visibilitychange',()=>{
  if(document.hidden){clearHover();if(state.gesture)finishGesture(state.gesture,lastPointer(state.gesture),{cancelled:true});}
  else if(state.started){recoverInactiveCamera();state.handLastVideo=-1;state.handLastTick=0;scheduleRender()}
});
window.addEventListener('pagehide',()=>{
  if(state.handRunning)stopHands({quiet:true});
  state.handModel?.close?.();state.handModel=null;
  state.stream?.getTracks().forEach(track=>track.stop());
  if(state.audio){state.audio.pause();state.audio=null}
});
setInterval(()=>{if(!state.started||state.handRunning||!settings.gyro)return;
  if(!state.poseReady)setStatus(state.orientationAllowed?'Câmera • aguardando sensor':'Câmera • sem sensor');
  else if(Date.now()-state.sensorAge>8000)setStatus('Câmera • sensor sem atualizar');
},3000);
if('serviceWorker' in navigator&&location.protocol==='https:')navigator.serviceWorker.register('./sw.js').catch(error=>log('PWA: '+error.message));

// Development smoke-test hooks are only exposed with ?debug=1.
if(new URLSearchParams(location.search).get('debug')==='1'){
  window.VROSDebug={state,apps,openWindow,closeWindow,recenterAll,rayAt,projection,orientationQuat,evaluateExpression,stopHands,startHands,switchCamera,dispatchHandGesture,finishGesture,centerWindow,focusWindow,minimizeWindow,videoPoint};
}
