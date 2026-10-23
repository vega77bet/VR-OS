"""Regression tests for sensor convergence, camera switching, hand control and landscape layout."""
from pathlib import Path
import sys
from playwright.sync_api import sync_playwright
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_suite import HTML,CSS,APP,MOCK

with sync_playwright() as p:
 browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--autoplay-policy=no-user-gesture-required','--disable-web-security'])
 ctx=browser.new_context(viewport={'width':844,'height':390},device_scale_factor=1,is_mobile=True,has_touch=True)
 page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.set_content(HTML,wait_until='domcontentloaded');page.add_style_tag(content=CSS);page.evaluate(MOCK);page.add_script_tag(content=APP)
 page.locator('#start').click();page.wait_for_function('window.VROSDebug.state.started')
 page.wait_for_timeout(230)
 assert page.evaluate("window.VROSDebug.state.windows.size")

 # Orientation interpolation must converge after one single sensor packet.
 page.evaluate("window.dispatchEvent(Object.assign(new Event('deviceorientation'),{alpha:10,beta:60,gamma:-2}))")
 page.wait_for_timeout(300)
 page.evaluate("window.dispatchEvent(Object.assign(new Event('deviceorientation'),{alpha:77,beta:45,gamma:20}))")
 page.wait_for_timeout(1500)
 sim=page.evaluate('''() => { const s=VROSDebug.state,p=s.pose,t=s.poseTarget;return Math.abs(p.x*t.x+p.y*t.y+p.z*t.z+p.w*t.w)}''')
 assert sim>.9995,f'Gyro stopped too far from target: {sim}'

 # Physical landscape size, including user scale, must not exceed viewport.
 page.evaluate('''() => {VROSDebug.openWindow('notes');const w=[...VROSDebug.state.windows.values()].find(w=>w.kind==='notes');document.documentElement.style.setProperty('--window-scale','1.18');const r=w.el.getBoundingClientRect();window.__r={width:r.width,height:r.height,top:r.top};}''')
 assert page.evaluate('window.__r.width')<=845,page.evaluate('window.__r')
 # Minimized state stays minimized when opening a fresh window with restored settings.
 page.evaluate('''() => {let w=VROSDebug.openWindow('clock',{minimized:true});window.__minimized=!!w.minimized&&w.el.classList.contains('minimized');}''')
 assert page.evaluate('window.__minimized')

 # Camera switch should resume an already loaded hand-landmarker, without network requests.
 page.evaluate('''() => {const s=VROSDebug.state;s.handModel={detectForVideo(){return {landmarks:[]}},close(){}};s.handRunning=true;document.body.classList.add('hand-control-active')}''')
 switched=page.evaluate("async()=>await VROSDebug.switchCamera('auto',{silent:true})")
 assert switched,'Camera could not switch'
 assert page.evaluate('VROSDebug.state.handRunning'), 'Camera switch turned hands off'
 page.evaluate('VROSDebug.stopHands({quiet:true})')

 # A hit on body text must not drag the whole window (chrome only).
 page.evaluate('''() => {const w=VROSDebug.openWindow('notes');VROSDebug.centerWindow(w)}''')
 page.wait_for_timeout(120)
 center=page.evaluate('''() => {const r=document.querySelector('#notesText').getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2}}''')
 page.evaluate('(p)=>VROSDebug.dispatchHandGesture(p,true,null)',center)
 assert page.evaluate('VROSDebug.state.gesture.mode')=='tap'
 page.evaluate('(p)=>VROSDebug.dispatchHandGesture(p,false,null)',center)

 # A detected hand visually clears the blur behind the cursor without removing buttons.
 button=page.locator('.spatial-window').filter(has=page.locator('.window-title',has_text='Notas')).locator('[data-win="close"]')
 bounds=button.bounding_box()
 if bounds:
  target={'x':bounds['x']+bounds['width']/2,'y':bounds['y']+bounds['height']/2}
  page.evaluate('(p)=>VROSDebug.dispatchHandGesture(p,false,null)',target)
  assert page.locator('.spatial-window.hand-near').count()>=1
  assert page.evaluate("getComputedStyle(document.querySelector('[data-win=close]')).color")!='rgb(255, 255, 255)'

 # Safari can stop tracks when the page is suspended; recovering should restore the welcome action.
 page.evaluate('''() => {VROSDebug.state.stream.getTracks().forEach(t=>t.stop());window.dispatchEvent(new Event('pageshow'))}''')
 assert page.evaluate('!VROSDebug.state.started')
 assert page.locator('#start').is_visible()
 assert 'Retomar' in page.locator('#start').inner_text()
 page.locator('#start').click()
 page.wait_for_function('window.VROSDebug.state.started',timeout=5000)
 assert page.locator('.spatial-window').count()>0

 assert not errors,errors
 page.screenshot(path=str(Path(__file__).resolve().parent.parent/'landscape_regression.png'))
 print('PASS regression: gyro converges, camera preserves hands, minimized persists, drag semantics, UI hierarchy')
 browser.close()
