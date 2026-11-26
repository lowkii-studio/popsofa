/// Die Fernbedienungs-Webseite fürs iPhone (eine Datei, Vanilla-JS, keine externen Quellen).
/// Übernimmt den Stil der Mac-App (Apple, Pop-Art, Webmuster) aus der `state`-Nachricht.
enum RemotePage {
    static let html = #"""
<!doctype html>
<html lang="de"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="PopSofa">
<meta name="theme-color" content="#0A0A0F" id="tc">
<title>PopSofa</title>
<style>
:root{--bg:#0A0A0F;--pattern:none;--card:rgba(255,255,255,.08);--card2:rgba(255,255,255,.2);--btnfg:#fff;--line:rgba(255,255,255,.12);
 --border:1px solid transparent;--shadow:none;--press:none;--accent:#fff;--accentfg:#000;--head:-apple-system,system-ui,sans-serif;--headcol:#fff;
 --pad:rgba(255,255,255,.08);--padfg:rgba(255,255,255,.32);--input:rgba(255,255,255,.08);--inputfg:#fff;--nav:transparent;--navact:#fff;--dim:rgba(255,255,255,.62);--r:16px}
body[data-theme=pop]{--bg:#0E5E66;--pattern:radial-gradient(rgba(54,197,201,.38) 2.2px,transparent 2.8px) 0 0/16px 16px;
 --card:#FFF8E7;--card2:#FFD23F;--btnfg:#000;--line:#000;--border:3px solid #000;--shadow:4px 4px 0 #000;--press:translate(3px,3px);
 --accent:#FFD23F;--accentfg:#000;--head:'Futura-CondensedExtraBold','Futura','Avenir Next Condensed',sans-serif;--headcol:#FFD23F;
 --pad:rgba(0,0,0,.32);--padfg:rgba(255,255,255,.85);--input:#FFF8E7;--inputfg:#000;--nav:rgba(0,0,0,.55);--navact:#FFD23F;--dim:rgba(255,255,255,.92);--r:14px}
body[data-theme=woven]{--bg:#3B1F14;
 --pattern:linear-gradient(135deg,rgba(200,85,43,.3) 25%,transparent 25%) -11px 0/22px 22px,linear-gradient(225deg,rgba(200,85,43,.3) 25%,transparent 25%) -11px 0/22px 22px,repeating-linear-gradient(0deg,transparent 0 66px,rgba(244,182,63,.28) 66px 70px);
 --card:#F2E2C4;--card2:#F4B63F;--btnfg:#000;--line:#000;--border:3px solid #000;--shadow:4px 4px 0 #000;--press:translate(3px,3px);
 --accent:#F4B63F;--accentfg:#000;--head:'Rockwell-Bold','Rockwell','American Typewriter',Georgia,serif;--headcol:#F4B63F;
 --pad:rgba(0,0,0,.42);--padfg:rgba(255,255,255,.88);--input:#F2E2C4;--inputfg:#000;--nav:rgba(0,0,0,.55);--navact:#F4B63F;--dim:rgba(255,255,255,.92);--r:12px}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}
html,body{margin:0;height:100%;color:#fff;font:16px -apple-system,system-ui,sans-serif;overscroll-behavior:none;-webkit-text-size-adjust:100%;text-size-adjust:100%}
html{background:var(--bg)}
body{position:fixed;inset:0;display:flex;flex-direction:column;background:var(--pattern),var(--bg);padding:env(safe-area-inset-top) env(safe-area-inset-right) 0 env(safe-area-inset-left)}
.ic{width:26px;height:26px;fill:none;stroke:currentColor;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round;flex:0 0 auto}
.ic .f{fill:currentColor;stroke:none}
header{display:flex;align-items:center;gap:10px;padding:12px 16px}
header b{flex:1;font:800 24px var(--head);color:var(--headcol);letter-spacing:-.3px}
body:not([data-theme=apple]) header b{text-transform:uppercase;letter-spacing:.5px;text-shadow:2px 2px 0 #000;transform:rotate(-2deg);transform-origin:left}
#st{font-size:14px;color:var(--dim)}
#dot{width:10px;height:10px;border-radius:50%;background:#FF9F0A;box-shadow:0 0 0 2px rgba(0,0,0,.35)}
#dot.on{background:#30D158}
main{flex:1;min-height:0;position:relative}
section{position:absolute;inset:0;display:none;flex-direction:column;gap:12px;padding:4px 16px 10px;overflow-y:auto}
section.on{display:flex}
#pad{flex:1;min-height:180px;border-radius:24px;background:var(--pad);border:var(--border);border-color:var(--line);touch-action:none;display:flex;flex-direction:column;gap:10px;align-items:center;justify-content:center;text-align:center;padding:24px;color:var(--padfg);font-size:14px;line-height:1.6}
body[data-theme=apple] #pad{border:1px solid rgba(255,255,255,.12)}
#pad .ic{width:40px;height:40px;opacity:.6}
.row{display:flex;gap:12px}
button{flex:1;min-height:56px;border:var(--border);border-radius:var(--r);background:var(--card);color:var(--btnfg);box-shadow:var(--shadow);font:600 15px -apple-system,system-ui,sans-serif;touch-action:manipulation;display:flex;align-items:center;justify-content:center;gap:8px;padding:0 10px;transition:transform .06s}
button:active{background:var(--card2);transform:var(--press);box-shadow:none}
button.on{background:var(--accent);color:var(--accentfg)}
.dpad{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;width:100%;max-width:320px;margin:4px auto}
.dpad button{min-height:84px}
.dpad .ic{width:34px;height:34px}
.dpad .ok{border-radius:50%;font-size:20px;font-weight:800}
body[data-theme=apple] .dpad .ok{background:rgba(255,255,255,.18)}
body:not([data-theme=apple]) .dpad .ok{background:var(--accent)}
#svc{display:grid;grid-template-columns:repeat(2,1fr);gap:14px}
#svc button{min-height:100px;border-radius:20px;font:700 19px var(--head)}
body[data-theme=apple] #svc button{text-shadow:0 1px 4px rgba(0,0,0,.45)}
body:not([data-theme=apple]) #svc button{text-transform:uppercase;border-radius:var(--r)}
.empty{grid-column:1/-1;color:var(--dim);text-align:center;padding:40px 10px}
.txt{display:flex;gap:10px;padding:8px 16px 4px}
.txt input{flex:1;min-width:0;height:52px;border-radius:var(--r);border:var(--border);border-color:var(--line);background:var(--input);color:var(--inputfg);font-size:17px;padding:0 14px;-webkit-user-select:text;user-select:text}
body[data-theme=apple] .txt input{border:1px solid rgba(255,255,255,.12)}
.txt input::placeholder{color:currentColor;opacity:.5}
.txt button{flex:0 0 56px;min-height:52px;padding:0}
.live{display:flex;align-items:center;gap:8px;padding:4px 18px 6px;font-size:13px;color:var(--dim)}
.live input{width:20px;height:20px;margin:0;accent-color:var(--accent)}
nav{display:flex;background:var(--nav);border-top:1px solid rgba(255,255,255,.12);padding:4px 8px calc(4px + env(safe-area-inset-bottom))}
nav button,nav button:active{background:none;border:0;box-shadow:none;transform:none;color:var(--dim);font-size:12px;min-height:54px;flex-direction:column;gap:3px}
nav button.on{background:none;color:var(--navact)}
nav .ic{width:24px;height:24px}
#pinbox{position:fixed;inset:0;z-index:5;display:none;flex-direction:column;align-items:center;justify-content:center;gap:16px;padding:24px;text-align:center;background:var(--pattern),var(--bg)}
#pinbox.on{display:flex}
#pinbox b{font:800 26px var(--head);color:var(--headcol)}
#pin{width:240px;height:66px;border-radius:var(--r);border:var(--border);border-color:var(--line);background:var(--input);color:var(--inputfg);font-size:34px;letter-spacing:10px;text-align:center;-webkit-user-select:text;user-select:text}
body[data-theme=apple] #pin{border:1px solid rgba(255,255,255,.12)}
#pinbox button{flex:0 0 auto;width:240px}
.hint{max-width:330px;color:var(--dim);font-size:15px;line-height:1.45}
#err{min-height:20px;color:#FF8A80;font-weight:600}
</style></head>
<body data-theme="apple">
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
 <symbol id="i-back" viewBox="0 0 24 24"><path d="M19 12H5M11 6l-6 6 6 6"/></symbol>
 <symbol id="i-play" viewBox="0 0 24 24"><path class="f" d="M3 5v14l10-7z"/><path d="M16.5 5.5v13M20.5 5.5v13"/></symbol>
 <symbol id="i-full" viewBox="0 0 24 24"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></symbol>
 <symbol id="i-mute" viewBox="0 0 24 24"><path d="M3 9.5h4l5-4.5v14l-5-4.5H3z"/><path d="M16 9.5l5 5M21 9.5l-5 5"/></symbol>
 <symbol id="i-down" viewBox="0 0 24 24"><path d="M3 9.5h4l5-4.5v14l-5-4.5H3z"/><path d="M16.5 12H21"/></symbol>
 <symbol id="i-up" viewBox="0 0 24 24"><path d="M3 9.5h4l5-4.5v14l-5-4.5H3z"/><path d="M16 9a4.2 4.2 0 0 1 0 6M18.8 6.2a8.2 8.2 0 0 1 0 11.6"/></symbol>
 <symbol id="i-cu" viewBox="0 0 24 24"><path d="M5 15l7-7 7 7"/></symbol>
 <symbol id="i-cd" viewBox="0 0 24 24"><path d="M5 9l7 7 7-7"/></symbol>
 <symbol id="i-cl" viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></symbol>
 <symbol id="i-cr" viewBox="0 0 24 24"><path d="M9 5l7 7-7 7"/></symbol>
 <symbol id="i-home" viewBox="0 0 24 24"><path d="M3 11l9-7.5 9 7.5M5.5 9.5V20h5v-6h3v6h5V9.5"/></symbol>
 <symbol id="i-tp" viewBox="0 0 24 24"><path d="M12 6l-6 6 6 6M19 6l-6 6 6 6"/></symbol>
 <symbol id="i-tn" viewBox="0 0 24 24"><path d="M12 6l6 6-6 6M5 6l6 6-6 6"/></symbol>
 <symbol id="i-mouse" viewBox="0 0 24 24"><path d="M5 3l14 7-6.2 1.8L10.5 18z"/><path d="M13 12l5 6"/></symbol>
 <symbol id="i-send" viewBox="0 0 24 24"><path d="M21 3L10 14M21 3l-7 18-4-7-7-4z"/></symbol>
 <symbol id="i-enter" viewBox="0 0 24 24"><path d="M20 5v6a3 3 0 0 1-3 3H5M9 10l-4 4 4 4"/></symbol>
 <symbol id="i-pad" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><path d="M3 15h18M12 15v5"/></symbol>
 <symbol id="i-keys" viewBox="0 0 24 24"><path d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6z"/></symbol>
 <symbol id="i-grid" viewBox="0 0 24 24"><rect x="3" y="3" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="2"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="2"/></symbol>
 <symbol id="i-hand" viewBox="0 0 24 24"><path d="M9 11V5a1.5 1.5 0 0 1 3 0v5M12 10V3.5a1.5 1.5 0 0 1 3 0V10M15 10V5a1.5 1.5 0 0 1 3 0v8c0 4-2.5 8-7 8-3 0-4.5-1.5-6.5-4.5L3 13.5a1.5 1.5 0 0 1 2.5-1.6L9 15"/></symbol>
</svg>
<header><b>PopSofa</b><span id="st">Verbinde…</span><span id="dot"></span></header>
<main>
 <section id="t-pad" class="on">
  <div id="pad"><svg class="ic"><use href="#i-hand"/></svg><div>Wischen bewegt den Zeiger · Tippen klickt<br>Doppeltippen: Doppelklick · Halten: ziehen<br>Zwei Finger: scrollen · tippen = Rechtsklick</div></div>
  <div class="row">
   <button data-k="back" aria-label="Zurück"><svg class="ic"><use href="#i-back"/></svg></button>
   <button data-k="space" aria-label="Play/Pause"><svg class="ic"><use href="#i-play"/></svg></button>
   <button data-k="fullscreen" aria-label="Vollbild"><svg class="ic"><use href="#i-full"/></svg></button>
  </div>
  <div class="row">
   <button data-k="mute" aria-label="Stumm"><svg class="ic"><use href="#i-mute"/></svg></button>
   <button data-k="voldown" aria-label="Leiser"><svg class="ic"><use href="#i-down"/></svg></button>
   <button data-k="volup" aria-label="Lauter"><svg class="ic"><use href="#i-up"/></svg></button>
  </div>
 </section>
 <section id="t-keys">
  <div class="dpad">
   <span></span><button data-k="up" aria-label="Hoch"><svg class="ic"><use href="#i-cu"/></svg></button><span></span>
   <button data-k="left" aria-label="Links"><svg class="ic"><use href="#i-cl"/></svg></button><button class="ok" data-k="enter">OK</button><button data-k="right" aria-label="Rechts"><svg class="ic"><use href="#i-cr"/></svg></button>
   <span></span><button data-k="down" aria-label="Runter"><svg class="ic"><use href="#i-cd"/></svg></button><span></span>
  </div>
  <div class="row">
   <button data-k="back"><svg class="ic"><use href="#i-back"/></svg>Zurück</button>
   <button id="home"><svg class="ic"><use href="#i-home"/></svg>Home</button>
  </div>
  <div class="row">
   <button data-k="tabprev" aria-label="Tab zurück"><svg class="ic"><use href="#i-tp"/></svg></button>
   <button id="mouse" aria-label="Maus-Modus"><svg class="ic"><use href="#i-mouse"/></svg>Maus</button>
   <button data-k="tabnext" aria-label="Tab vor"><svg class="ic"><use href="#i-tn"/></svg></button>
  </div>
  <div class="row">
   <button data-k="voldown" aria-label="Leiser"><svg class="ic"><use href="#i-down"/></svg></button>
   <button data-k="space" aria-label="Play/Pause"><svg class="ic"><use href="#i-play"/></svg></button>
   <button data-k="volup" aria-label="Lauter"><svg class="ic"><use href="#i-up"/></svg></button>
  </div>
 </section>
 <section id="t-svc"><div id="svc"></div></section>
</main>
<div class="txt"><button data-k="cleft" aria-label="Cursor nach links"><svg class="ic"><use href="#i-cl"/></svg></button><input id="text" type="text" placeholder="Text an den Mac senden" enterkeyhint="send" autocomplete="off"><button data-k="cright" aria-label="Cursor nach rechts"><svg class="ic"><use href="#i-cr"/></svg></button><button id="send" aria-label="Senden"><svg class="ic"><use href="#i-send"/></svg></button><button id="enter" aria-label="Enter"><svg class="ic"><use href="#i-enter"/></svg></button></div>
<label class="live"><input type="checkbox" id="live"> Live: jedes Zeichen sofort senden</label>
<nav>
 <button data-tab="pad" class="on"><svg class="ic"><use href="#i-pad"/></svg>Touchpad</button>
 <button data-tab="keys"><svg class="ic"><use href="#i-keys"/></svg>Tasten</button>
 <button data-tab="svc"><svg class="ic"><use href="#i-grid"/></svg>Dienste</button>
</nav>
<div id="pinbox">
 <b>Mit PopSofa koppeln</b>
 <div class="hint">Gib die 6-stellige PIN ein, die PopSofa auf dem Mac unter „iPhone koppeln“ zeigt.</div>
 <input id="pin" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="one-time-code">
 <div id="err"></div>
 <button id="pinok">Koppeln</button>
</div>
<script>
(function(){
'use strict';
var $=function(s){return document.querySelector(s)},$$=function(s){return document.querySelectorAll(s)};
var KEY='popsofaToken',ws=null,authed=false,backoff=500,timer=null,state={services:[],mouse:false};
var BG={apple:'#0A0A0F',pop:'#0E5E66',woven:'#3B1F14'};
var urlPin=new URLSearchParams(location.search).get('pin');
var store={get:function(k){try{return localStorage.getItem(k)}catch(e){return null}},
 set:function(k,v){try{v?localStorage.setItem(k,v):localStorage.removeItem(k)}catch(e){}}};
function buzz(){try{if(navigator.vibrate)navigator.vibrate(8)}catch(e){}}
function status(t,ok){$('#st').textContent=t;$('#dot').className=ok?'on':''}
function send(o){if(ws&&ws.readyState===1&&(authed||o.t==='pair'||o.t==='auth'))ws.send(JSON.stringify(o))}
function devName(){var u=navigator.userAgent;return /iPad/.test(u)?'iPad':/iPhone/.test(u)?'iPhone':/Android/.test(u)?'Android':'Browser'}
function showPin(msg){$('#pinbox').classList.add('on');$('#err').textContent=msg||''}
function pair(p){send({t:'pair',pin:p,name:devName()})}
function hello(){var tok=store.get(KEY);if(tok)send({t:'auth',token:tok});else if(urlPin){pair(urlPin);urlPin=null}else showPin()}
function theme(t){if(!BG[t])t='apple';document.body.dataset.theme=t;$('#tc').setAttribute('content',BG[t]);store.set('popsofaTheme',t)}
theme(store.get('popsofaTheme'));

function connect(){
 clearTimeout(timer);
 if(ws&&ws.readyState<2)return;
 try{ws=new WebSocket('ws://'+location.host+'/ws')}catch(e){retry();return}
 ws.onopen=function(){backoff=500;hello()};
 ws.onmessage=function(e){var m;try{m=JSON.parse(e.data)}catch(x){return}
  if(m.t==='ok'){authed=true;if(m.token)store.set(KEY,m.token);
   if(location.search)history.replaceState(null,'',location.pathname);
   $('#pinbox').classList.remove('on');status('Verbunden',true)}
  else if(m.t==='err'){
   if(m.code==='token'){store.set(KEY,null);if(urlPin){pair(urlPin);urlPin=null;return}}
   showPin(m.msg)}
  else if(m.t==='state'){state=m;theme(m.theme);render()}};
 ws.onclose=function(){var was=authed;ws=null;authed=false;status(was?'Verbindung getrennt…':'Verbinde…',false);retry()};
 ws.onerror=function(){};
}
function retry(){clearTimeout(timer);timer=setTimeout(connect,backoff);backoff=Math.min(backoff*2,5000)}
document.addEventListener('visibilitychange',function(){if(!document.hidden&&!ws){backoff=500;connect()}});

$('#pinok').onclick=function(){var v=$('#pin').value.replace(/\D/g,'');
 if(v.length!==6){$('#err').textContent='Bitte 6 Ziffern eingeben.';return}
 $('#err').textContent='';if(ws&&ws.readyState===1)pair(v);else{urlPin=v;connect()}};
$('#pin').addEventListener('keydown',function(e){if(e.key==='Enter')$('#pinok').onclick()});

function render(){var box=$('#svc'),list=state.services||[],hex=/^#[0-9a-f]{6}$/i;box.textContent='';
 if(!list.length){var d=document.createElement('div');d.className='empty';d.textContent='Keine Dienste aktiviert.';box.appendChild(d)}
 list.forEach(function(s){var b=document.createElement('button');b.textContent=s.name;
  if(hex.test(s.c1)&&hex.test(s.c2))b.style.background=s.c1===s.c2?s.c1:'linear-gradient(135deg,'+s.c1+','+s.c2+')';
  if(hex.test(s.fg))b.style.color=s.fg;
  b.onclick=function(){buzz();send({t:'launch',id:s.id})};box.appendChild(b)});
 $('#mouse').classList.toggle('on',!!state.mouse)}

Array.prototype.forEach.call($$('[data-k]'),function(b){b.onclick=function(){buzz();send({t:'key',k:b.dataset.k})}});
$('#home').onclick=function(){buzz();send({t:'home'})};
$('#mouse').onclick=function(){buzz();send({t:'mode',mouse:!state.mouse})};
Array.prototype.forEach.call($$('nav button'),function(b){b.onclick=function(){
 Array.prototype.forEach.call($$('nav button'),function(x){x.classList.toggle('on',x===b)});
 Array.prototype.forEach.call($$('section'),function(s){s.classList.toggle('on',s.id==='t-'+b.dataset.tab)})}});

// Texteingabe (iOS-Tastatur inkl. Diktierfunktion)
var inp=$('#text'),last=[];
function live(){return $('#live').checked}
function flush(){if(!live()&&inp.value)send({t:'text',s:inp.value.slice(0,500)});inp.value='';last=[]}
$('#send').onclick=function(){buzz();flush()};
$('#enter').onclick=function(){buzz();flush();send({t:'submit'})};
inp.addEventListener('keydown',function(e){if(e.key==='Enter'){e.preventDefault();flush();if(live())send({t:'submit'})}});
// Live: nur die Änderung schicken – auch mitten im Text (gleicher Anfang UND gleiches Ende bleiben stehen).
inp.addEventListener('input',function(){if(!live())return;var v=Array.from(inp.value),i=0,j=0,k;
 while(i<last.length&&i<v.length&&last[i]===v[i])i++;
 while(j<last.length-i&&j<v.length-i&&last[last.length-1-j]===v[v.length-1-j])j++;
 for(k=0;k<j;k++)send({t:'key',k:'cleft'});
 for(k=last.length-j;k>i;k--)send({t:'key',k:'delete'});
 var add=v.slice(i,v.length-j).join('');if(add)send({t:'text',s:add.slice(0,500)});
 for(k=0;k<j;k++)send({t:'key',k:'cright'});
 last=v});
$('#live').onchange=function(){inp.value='';last=[]};

// Touchpad
var pad=$('#pad'),mx=0,my=0,sx=0,sy=0,prev=null,t0=0,maxT=0,dist=0,moved=false,drag=false,hold=null;
function avg(e){var x=0,y=0,n=e.touches.length;for(var i=0;i<n;i++){x+=e.touches[i].clientX;y+=e.touches[i].clientY}return{x:x/n,y:y/n,n:n}}
pad.addEventListener('touchstart',function(e){e.preventDefault();var a=avg(e);
 if(e.touches.length===e.changedTouches.length){t0=Date.now();maxT=0;dist=0;moved=false}
 maxT=Math.max(maxT,a.n);prev=a;clearTimeout(hold);
 if(a.n===1&&!moved)hold=setTimeout(function(){if(!moved){drag=true;buzz();send({t:'drag',state:'start'})}},450)},{passive:false});
pad.addEventListener('touchmove',function(e){e.preventDefault();var a=avg(e);
 if(!prev||a.n!==prev.n){prev=a;return}
 var dx=a.x-prev.x,dy=a.y-prev.y;prev=a;dist+=Math.abs(dx)+Math.abs(dy);
 if(dist>8){moved=true;clearTimeout(hold)}
 if(a.n>=2){sx+=dx*2;sy+=dy*2}
 else{var f=1.2+Math.min(Math.abs(dx)+Math.abs(dy),40)*0.1;mx+=dx*f;my+=dy*f}},{passive:false});
function end(e){e.preventDefault();if(e.touches.length){prev=avg(e);return}
 clearTimeout(hold);prev=null;
 if(drag){drag=false;send({t:'drag',state:'end'});return}
 if(!moved&&Date.now()-t0<350){if(maxT>=2){buzz();send({t:'click',b:'right',n:1})}else send({t:'click',b:'left',n:1})}}
pad.addEventListener('touchend',end,{passive:false});
pad.addEventListener('touchcancel',end,{passive:false});
(function loop(){var x=Math.round(mx),y=Math.round(my);
 if(x||y){send({t:'move',dx:x,dy:y});mx-=x;my-=y}
 var a=Math.trunc(sx),b=Math.trunc(sy);
 if(a||b){send({t:'scroll',dx:a,dy:b});sx-=a;sy-=b}
 requestAnimationFrame(loop)})();

render();connect();
})();
</script>
</body></html>
"""#
}
