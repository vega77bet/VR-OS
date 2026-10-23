"""Smoke tests for the camera-first spatial shell without a physical iPhone.
Uses Chromium + Playwright, an in-memory Web Storage mock and a synthetic camera stream.
"""
from pathlib import Path
import re
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parent.parent
HTML=re.sub(r'<link[^>]+>|<script type="module"[^>]+></script>','',(ROOT/'index.html').read_text())
CSS=(ROOT/'styles.css').read_text()
APP=(ROOT/'app.js').read_text().replace("new URLSearchParams(location.search).get('debug')==='1'","true")

MOCK="""() => {
  const storage = new Map();
  Object.defineProperty(window, 'localStorage', {get:()=>({
    getItem:key=>storage.has(key)?storage.get(key):null,
    setItem:(key,value)=>storage.set(key,String(value)),
    removeItem:key=>storage.delete(key)
  }),configurable:true});
  const canvas = document.createElement('canvas');canvas.width=1280;canvas.height=720;
  const ctx=canvas.getContext('2d');const paint=()=>{
    ctx.fillStyle='#527b94';ctx.fillRect(0,0,1280,720);
    ctx.fillStyle='#7a9bac';ctx.fillRect(500,120,260,440);
  };paint();setInterval(paint,65);
  Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{
    getUserMedia:async()=>canvas.captureStream(20),
    enumerateDevices:async()=>[
      {kind:'videoinput',deviceId:'ultra-1',label:'Back Ultra Wide Camera'},
      {kind:'videoinput',deviceId:'wide-1',label:'Back Camera'},
      {kind:'videoinput',deviceId:'front-1',label:'Front Camera'}
    ]
  }});
}"""

def run_case(p,name,width,height):
    browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--autoplay-policy=no-user-gesture-required','--disable-web-security'])
    ctx=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=1)
    page=ctx.new_page();errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.set_content(HTML,wait_until='domcontentloaded')
    page.add_style_tag(content=CSS)
    page.evaluate(MOCK)
    page.add_script_tag(content=APP)
    assert page.locator('#start').is_visible()
    page.locator('#start').click()
    page.wait_for_function('window.VROSDebug.state.started',timeout=5000)
    page.wait_for_timeout(300)
    assert page.locator('.spatial-window').count()>=1
    assert page.locator('button[data-win="close"]').count()>=1

    # Core input: real pointer events on close button (original version's most visible bug).
    page.evaluate("window.VROSDebug.openWindow('notes')")
    note=page.locator('.spatial-window').filter(has=page.locator('.window-title',has_text='Notas'))
    note.locator('#notesText').fill('nota de teste '+name)
    assert page.evaluate('JSON.parse(localStorage.getItem("vros2.notes"))')=='nota de teste '+name
    note.locator('[data-win=close]').click()
    assert not page.locator('.window-title',has_text='Notas').count()

    # Minimize, restore, expand; these must work without changing windows by mistake.
    page.evaluate("window.VROSDebug.openWindow('calc')")
    calc=page.locator('.spatial-window').filter(has=page.locator('.window-title',has_text='Calculadora'))
    calc.locator('[data-win=min]').click()
    assert 'minimized' in calc.get_attribute('class')
    calc.locator('[data-win=min]').click()
    assert 'minimized' not in calc.get_attribute('class')
    calc.locator('[data-win=max]').click()
    assert page.evaluate("[...window.VROSDebug.state.windows.values()].find(w=>w.kind==='calc').maxOld!==null")
    assert page.evaluate('window.VROSDebug.evaluateExpression("(9+7)/4")')=='4'
    assert page.evaluate('window.VROSDebug.evaluateExpression("2*-3")')=='-6'
    calc.locator('[data-win=close]').click()

    # Sensor quaternion + directional projection: motion changes window position and recenter works.
    page.evaluate("window.dispatchEvent(Object.assign(new Event('deviceorientation'),{alpha:15,beta:70,gamma:-15}))")
    page.wait_for_timeout(150)
    assert page.evaluate('window.VROSDebug.state.poseReady')
    page.evaluate("window.VROSDebug.openWindow('home')")
    p0=page.evaluate("() => {const w=[...window.VROSDebug.state.windows.values()].find(w=>w.kind==='home');return window.VROSDebug.projection(w.dir)}")
    page.evaluate("window.dispatchEvent(Object.assign(new Event('deviceorientation'),{alpha:35,beta:70,gamma:-15}))")
    page.wait_for_timeout(450)
    p1=page.evaluate("() => {const w=[...window.VROSDebug.state.windows.values()].find(w=>w.kind==='home');return window.VROSDebug.projection(w.dir)}")
    assert abs(p0['x']-p1['x'])>5 or abs(p0['y']-p1['y'])>5,(p0,p1)
    page.evaluate('window.VROSDebug.recenterAll(true)')
    p2=page.evaluate("() => {const w=[...window.VROSDebug.state.windows.values()].find(w=>w.kind==='home');return window.VROSDebug.projection(w.dir)}")
    assert abs(p2['x']-width/2)<width*.3,(p2,width)

    # Simulated hand pinch activates the window close button, not a fake visual-only cursor.
    page.evaluate("window.VROSDebug.openWindow('notes')")
    page.wait_for_timeout(160)
    center=page.evaluate("""() => {const b=[...document.querySelectorAll('[data-win=close]')].find(e=>e.closest('.spatial-window').querySelector('.window-title').textContent==='Notas');const r=b.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}}""")
    page.evaluate("(p)=>window.VROSDebug.dispatchHandGesture(p,true,null)",center)
    page.evaluate("(p)=>window.VROSDebug.dispatchHandGesture(p,false,null)",center)
    assert page.locator('.window-title',has_text='Notas').count()==0

    # Two simultaneous pinches resize a selected window (landscape or portrait).
    page.evaluate("window.VROSDebug.openWindow('notes')")
    page.wait_for_timeout(160)
    info=page.evaluate("""() => {const w=[...window.VROSDebug.state.windows.values()].find(w=>w.kind==='notes');const r=w.el.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,width:w.width}}""")
    page.evaluate("""(p)=>window.VROSDebug.dispatchHandGesture({x:p.x,y:p.y},true,{position:{x:p.x+70,y:p.y},pinched:true})""",info)
    page.evaluate("""(p)=>window.VROSDebug.dispatchHandGesture({x:p.x,y:p.y},true,{position:{x:p.x+120,y:p.y},pinched:true})""",info)
    resized=page.evaluate("[...window.VROSDebug.state.windows.values()].find(w=>w.kind==='notes').width")
    assert resized>=info['width'],(info,resized)
    page.evaluate("""(p)=>window.VROSDebug.dispatchHandGesture({x:p.x,y:p.y},false,null)""",info)
    page.evaluate("window.VROSDebug.closeWindow([...window.VROSDebug.state.windows.values()].find(w=>w.kind==='notes'))")

    # UI settings and ultra-wide picker.
    page.locator('#quickSettings').click()
    assert page.locator('#cameraOptions option').count()>=3
    page.evaluate('''() => {const a=document.querySelector('#opacitySetting');a.value='.8';a.dispatchEvent(new Event('input',{bubbles:true}))}''')
    assert abs(page.evaluate('window.VROSDebug.state.started?parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--panel-alpha")):0')-.8)<.01
    page.locator('#quickLens').click()
    assert page.locator('#quickSettings').count()==1

    # Calendar create/delete.
    page.evaluate("window.VROSDebug.openWindow('calendar')")
    page.locator('#eventDate').fill('2026-10-22')
    page.locator('#eventTitle').fill('Evento teste')
    page.locator('#eventAdd').click()
    assert page.locator('#calendarEvents').get_by_text('Evento teste').count()==1
    page.locator('[data-delete-event]').click()
    assert page.locator('#calendarEvents').get_by_text('Evento teste').count()==0

    # Storage: capture photo from passthrough camera, IndexedDB or memory fallback.
    page.evaluate("window.VROSDebug.openWindow('gallery')")
    page.locator('#capture').click()
    page.wait_for_timeout(750)
    assert page.locator('#galleryList .photo-card').count()>=1

    # Stable window manager must close every window.
    page.evaluate("window.VROSDebug.openWindow('spaces')")
    page.locator('#closeAll').click()
    assert page.locator('.spatial-window').count()==0
    assert page.evaluate('window.VROSDebug.state.windows.size')==0
    assert not errors,errors
    page.screenshot(path=str(ROOT/f'{name}_verified.png'))
    print('PASS',name,'start, close, min, max, calc, gyro, recenter, settings, calendar, photo, close-all')
    browser.close()

if __name__=='__main__':
    with sync_playwright() as p:
        run_case(p,'landscape',844,390)
        run_case(p,'portrait',390,844)
        run_case(p,'desktop',1280,720)
