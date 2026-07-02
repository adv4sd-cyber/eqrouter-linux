import Foundation

/// The self-hosted control panel. Since SwiftUI does not exist on Linux and
/// the static-Linux SDK cannot link a native toolkit like GTK, the GUI is a
/// single-page web app served by the binary itself and driven entirely by
/// the `/api` endpoints in `ControlServer`. It mirrors the macOS app's HUD
/// aesthetic: translucent glass panels, a glowing log-frequency response
/// curve over ten band sliders, genre presets, headphone correction, and a
/// live engine section with VU metering.
public enum WebUI {
    public static let page: String = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>EQ Router — Linux</title>
<style>
  :root {
    --bg0:#0a0e12; --bg1:#111820; --card:rgba(255,255,255,.045);
    --stroke:rgba(255,255,255,.09); --stroke2:rgba(255,255,255,.14);
    --ink:#e8eef4; --ink-dim:#8fa1b3; --accent:#38e1c6; --accent2:#2fb8ff;
    --warn:#ffb454; --danger:#ff5e6c;
  }
  * { box-sizing:border-box; }
  body {
    margin:0; font:14px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Ubuntu,sans-serif;
    color:var(--ink);
    background:radial-gradient(1200px 700px at 20% -10%, #16303a 0%, transparent 60%),
               radial-gradient(1000px 800px at 110% 10%, #1a2038 0%, transparent 55%),
               linear-gradient(160deg,var(--bg0),var(--bg1));
    min-height:100vh; padding:22px;
  }
  .wrap { max-width:980px; margin:0 auto; }
  header { display:flex; align-items:center; gap:14px; margin-bottom:18px; }
  .mark { font-weight:800; letter-spacing:.14em; font-size:20px; }
  .mark .r { color:var(--accent); }
  .tag { font-size:11px; letter-spacing:.18em; color:var(--ink-dim);
         border:1px solid var(--stroke2); padding:3px 8px; border-radius:20px; text-transform:uppercase; }
  .pill { margin-left:auto; font-size:12px; padding:6px 12px; border-radius:20px;
          border:1px solid var(--stroke2); color:var(--ink-dim); display:flex; align-items:center; gap:7px; }
  .dot { width:8px; height:8px; border-radius:50%; background:var(--ink-dim); }
  .pill.on .dot { background:var(--accent); box-shadow:0 0 10px var(--accent); }
  .pill.on { color:var(--accent); border-color:rgba(56,225,198,.4); }
  .card { background:var(--card); border:1px solid var(--stroke); border-radius:16px;
          padding:18px; margin-bottom:16px; backdrop-filter:blur(14px); -webkit-backdrop-filter:blur(14px); }
  .card h2 { margin:0 0 14px; font-size:12px; letter-spacing:.14em; text-transform:uppercase; color:var(--ink-dim); font-weight:700; }
  .row { display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
  .spread { justify-content:space-between; }

  /* EQ curve + sliders */
  .eqstage { position:relative; }
  #curve { width:100%; height:180px; display:block; border-radius:12px;
           background:linear-gradient(180deg, rgba(56,225,198,.04), rgba(0,0,0,.12)); border:1px solid var(--stroke); }
  .bands { display:flex; justify-content:space-between; gap:6px; margin-top:12px; }
  .band { flex:1; display:flex; flex-direction:column; align-items:center; gap:6px; }
  .band .val { font-size:11px; color:var(--accent); min-height:14px; font-variant-numeric:tabular-nums; }
  .band input[type=range] {
    writing-mode:vertical-lr; direction:rtl; width:26px; height:120px; accent-color:var(--accent); cursor:pointer;
  }
  .band .freq { font-size:10px; color:var(--ink-dim); }

  /* chips */
  .chips { display:flex; flex-wrap:wrap; gap:8px; }
  .chip { padding:7px 13px; border-radius:20px; border:1px solid var(--stroke2);
          background:transparent; color:var(--ink-dim); cursor:pointer; font-size:12.5px; transition:.15s; }
  .chip:hover { color:var(--ink); border-color:var(--accent); }
  .chip.active { background:rgba(56,225,198,.14); border-color:var(--accent); color:var(--accent); }

  label.field { display:flex; flex-direction:column; gap:6px; font-size:11px; color:var(--ink-dim);
                text-transform:uppercase; letter-spacing:.1em; flex:1; min-width:180px; }
  select, textarea, input.txt {
    background:rgba(0,0,0,.25); color:var(--ink); border:1px solid var(--stroke2);
    border-radius:10px; padding:9px 11px; font-size:13px; outline:none; }
  select:focus, textarea:focus, input.txt:focus { border-color:var(--accent); }
  textarea { width:100%; min-height:90px; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:12px; resize:vertical; }

  .slider-row { display:flex; align-items:center; gap:12px; margin:8px 0; }
  .slider-row .name { width:110px; font-size:12px; color:var(--ink-dim); }
  .slider-row input[type=range] { flex:1; accent-color:var(--accent2); }
  .slider-row .num { width:64px; text-align:right; font-variant-numeric:tabular-nums; color:var(--ink); font-size:12.5px; }

  button.btn { padding:9px 15px; border-radius:10px; border:1px solid var(--stroke2);
               background:rgba(255,255,255,.04); color:var(--ink); cursor:pointer; font-size:13px; transition:.15s; }
  button.btn:hover { border-color:var(--accent); color:var(--accent); }
  button.btn.primary { background:linear-gradient(120deg,var(--accent),var(--accent2)); color:#05201c; border:none; font-weight:700; }
  button.btn.danger:hover { border-color:var(--danger); color:var(--danger); }

  .toggle { display:inline-flex; align-items:center; gap:8px; cursor:pointer; font-size:12.5px; color:var(--ink-dim); user-select:none; }
  .toggle input { display:none; }
  .toggle .sw { width:38px; height:22px; border-radius:20px; background:rgba(255,255,255,.1); position:relative; transition:.15s; }
  .toggle .sw::after { content:""; position:absolute; top:2px; left:2px; width:18px; height:18px; border-radius:50%; background:#fff; transition:.15s; }
  .toggle input:checked + .sw { background:var(--accent); }
  .toggle input:checked + .sw::after { transform:translateX(16px); }

  .meters { display:flex; flex-direction:column; gap:10px; margin-top:6px; }
  .meter { display:flex; align-items:center; gap:10px; }
  .meter .lbl { width:52px; font-size:11px; color:var(--ink-dim); }
  .meter .track { flex:1; height:12px; border-radius:8px; background:rgba(0,0,0,.35); overflow:hidden; border:1px solid var(--stroke); }
  .meter .fill { height:100%; width:0%; background:linear-gradient(90deg,var(--accent),var(--warn) 82%,var(--danger)); transition:width .08s linear; }
  .hint { font-size:12px; color:var(--ink-dim); line-height:1.6; }
  .hint code { background:rgba(0,0,0,.35); padding:2px 6px; border-radius:5px; color:var(--accent); }
  .banner { border:1px solid rgba(255,180,84,.4); background:rgba(255,180,84,.08);
            border-radius:12px; padding:12px 14px; margin-bottom:14px; font-size:13px; color:var(--ink); }
  .banner.ok { border-color:rgba(56,225,198,.4); background:rgba(56,225,198,.08); }
  .banner b { color:var(--warn); } .banner.ok b { color:var(--accent); }
  .banner .cmd { display:block; margin-top:8px; font-family:ui-monospace,Menlo,monospace; font-size:12px;
                 background:rgba(0,0,0,.35); padding:8px 10px; border-radius:6px; color:var(--accent); overflow-x:auto; }
  .banner .row { margin-top:10px; }
  .grid2 { display:grid; grid-template-columns:1fr 1fr; gap:12px; }
  @media (max-width:640px){ .grid2{grid-template-columns:1fr;} .slider-row .name{width:80px;} }
  #toast { position:fixed; bottom:20px; left:50%; transform:translateX(-50%);
           background:#12202a; border:1px solid var(--stroke2); color:var(--ink);
           padding:10px 16px; border-radius:10px; opacity:0; transition:.2s; pointer-events:none; font-size:13px; }
  #toast.show { opacity:1; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="mark">EQ<span class="r">ROUTER</span></div>
    <div class="tag">Linux Edition</div>
    <div id="enginePill" class="pill"><span class="dot"></span><span id="engineLabel">idle</span></div>
  </header>

  <div class="card">
    <div class="row spread" style="margin-bottom:12px">
      <h2 style="margin:0">Custom EQ</h2>
      <div class="row">
        <label class="toggle"><input type="checkbox" id="customBypass"><span class="sw"></span>Bypass</label>
        <button class="btn" id="resetBtn">Reset</button>
      </div>
    </div>
    <div class="eqstage">
      <canvas id="curve"></canvas>
      <div class="bands" id="bands"></div>
    </div>
  </div>

  <div class="card">
    <h2>Genre character</h2>
    <div class="chips" id="genres"></div>
  </div>

  <div class="card">
    <div class="row spread" style="margin-bottom:12px">
      <h2 style="margin:0">Headphone correction</h2>
      <label class="toggle"><input type="checkbox" id="correctionBypass"><span class="sw"></span>Bypass</label>
    </div>
    <div class="row">
      <label class="field" style="min-width:280px">Profile
        <select id="correction"></select>
      </label>
    </div>
  </div>

  <div class="card">
    <h2>Output</h2>
    <div class="slider-row"><span class="name">Route gain</span><input type="range" id="gain" min="-24" max="24" step="0.5" value="0"><span class="num" id="gainNum">0.0 dB</span></div>
    <div class="slider-row"><span class="name">Output trim</span><input type="range" id="trim" min="-24" max="24" step="0.5" value="0"><span class="num" id="trimNum">0.0 dB</span></div>
    <div class="row" style="margin-top:10px; gap:20px">
      <label class="toggle"><input type="checkbox" id="mute"><span class="sw"></span>Mute</label>
      <label class="toggle"><input type="checkbox" id="ceiling"><span class="sw"></span>Safety ceiling</label>
    </div>
  </div>

  <div class="card">
    <h2>Import AutoEq / EqualizerAPO preset</h2>
    <div class="row" style="margin-bottom:10px">
      <label class="field" style="min-width:220px">Name
        <input class="txt" id="importName" placeholder="e.g. HD650 Harman">
      </label>
    </div>
    <textarea id="importText" placeholder="Preamp: -6.7 dB&#10;Filter 1: ON LSC Fc 105 Hz Gain 12.2 dB Q 0.70&#10;Filter 2: ON PK Fc 61 Hz Gain -10.1 dB Q 0.34"></textarea>
    <div class="row" style="margin-top:10px">
      <button class="btn primary" id="importBtn">Import</button>
      <button class="btn" id="importClear">Clear imported</button>
      <span class="hint" id="importStatus"></span>
    </div>
  </div>

  <div class="card">
    <h2>Live engine — system audio routing</h2>
    <div id="depsBanner" class="banner" style="display:none"></div>
    <div id="engineHint" class="hint" style="margin-bottom:14px"></div>
    <div class="grid2">
      <label class="field">Capture source
        <select id="source"></select>
      </label>
      <label class="field">Output sink
        <select id="sink"></select>
      </label>
    </div>
    <div class="row" style="margin:14px 0">
      <button class="btn primary" id="startBtn">Start routing</button>
      <button class="btn danger" id="stopBtn">Stop</button>
      <button class="btn" id="setupSink">Create EQRouter sink</button>
      <button class="btn" id="refreshDev">Refresh devices</button>
    </div>
    <div class="meters">
      <div class="meter"><span class="lbl">Input</span><div class="track"><div class="fill" id="mIn"></div></div></div>
      <div class="meter"><span class="lbl">Output</span><div class="track"><div class="fill" id="mOut"></div></div></div>
    </div>
  </div>

  <div class="hint" style="text-align:center; margin-top:8px; opacity:.7">
    EQRouter Linux · DSP core shared with the macOS app · configuration saved to ~/.config/eqrouter/config.json
  </div>
</div>
<div id="toast"></div>

<script>
const api = async (method, path) => {
  const r = await fetch(path, { method });
  const t = await r.text();
  try { return { ok:r.ok, data: t ? JSON.parse(t) : {} }; }
  catch { return { ok:r.ok, data:{} }; }
};
const post = (path) => api('POST', path);
const toast = (msg) => {
  const el = document.getElementById('toast');
  el.textContent = msg; el.classList.add('show');
  clearTimeout(el._t); el._t = setTimeout(()=>el.classList.remove('show'), 2200);
};
const fmtFreq = (hz) => hz >= 1000 ? (hz/1000).toString().replace('.0','') + 'k' : Math.round(hz).toString();

let S = null;             // last full state
let centerFreqs = [];
const DB_RANGE = 18;

function draw(curve) {
  const c = document.getElementById('curve');
  const ratio = window.devicePixelRatio || 1;
  const w = c.clientWidth, h = c.clientHeight;
  c.width = w*ratio; c.height = h*ratio;
  const ctx = c.getContext('2d'); ctx.setTransform(ratio,0,0,ratio,0,0);
  ctx.clearRect(0,0,w,h);

  const lowLog = Math.log10(20), highLog = Math.log10(20000);
  const xOf = (hz) => w * (Math.log10(hz)-lowLog)/(highLog-lowLog);
  const yOf = (db) => { const cl = Math.max(-DB_RANGE, Math.min(DB_RANGE, db)); return h*(DB_RANGE-cl)/(2*DB_RANGE); };

  // grid: vertical freq lines
  ctx.strokeStyle = 'rgba(255,255,255,.06)'; ctx.lineWidth = 1;
  [31,62,125,250,500,1000,2000,4000,8000,16000].forEach(f=>{
    const x = xOf(f); ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,h); ctx.stroke();
  });
  // 0 dB reference
  ctx.strokeStyle = 'rgba(255,255,255,.16)'; ctx.setLineDash([2,4]);
  ctx.beginPath(); ctx.moveTo(0,yOf(0)); ctx.lineTo(w,yOf(0)); ctx.stroke(); ctx.setLineDash([]);

  if (!curve || !curve.length) return;
  const path = new Path2D();
  curve.forEach((p,i)=>{ const x=xOf(p[0]), y=yOf(p[1]); if(i===0) path.moveTo(x,y); else path.lineTo(x,y); });
  // glow then crisp
  ctx.strokeStyle = 'rgba(56,225,198,.28)'; ctx.lineWidth = 5; ctx.stroke(path);
  ctx.strokeStyle = 'rgba(56,225,198,.95)'; ctx.lineWidth = 1.8; ctx.stroke(path);
}

function buildBands() {
  const host = document.getElementById('bands'); host.innerHTML = '';
  centerFreqs.forEach((f,i)=>{
    const band = document.createElement('div'); band.className='band';
    const val = document.createElement('div'); val.className='val'; val.id='v'+i;
    const inp = document.createElement('input'); inp.type='range'; inp.min='-12'; inp.max='12'; inp.step='0.5'; inp.value='0'; inp.id='b'+i;
    const freq = document.createElement('div'); freq.className='freq'; freq.textContent=fmtFreq(f);
    inp.addEventListener('input', ()=>{ val.textContent=(+inp.value).toFixed(1); });
    inp.addEventListener('change', async ()=>{
      const res = await post('/api/band?index='+i+'&db='+inp.value);
      if (res.data.curve) draw(res.data.curve);
    });
    band.append(val,inp,freq); host.appendChild(band);
  });
}

function applyConfig(cfg) {
  cfg.bandGains.forEach((g,i)=>{
    const inp=document.getElementById('b'+i), val=document.getElementById('v'+i);
    if(inp){ inp.value=g; val.textContent=(+g).toFixed(1); }
  });
  document.getElementById('customBypass').checked = cfg.customEQBypassed;
  document.getElementById('correctionBypass').checked = cfg.correctionBypassed;
  document.getElementById('mute').checked = cfg.isMuted;
  document.getElementById('ceiling').checked = cfg.safetyCeilingEnabled;
  const gain=document.getElementById('gain'); gain.value=cfg.routeGainDb;
  document.getElementById('gainNum').textContent=(+cfg.routeGainDb).toFixed(1)+' dB';
  const trim=document.getElementById('trim'); trim.value=cfg.outputTrimDb;
  document.getElementById('trimNum').textContent=(+cfg.outputTrimDb).toFixed(1)+' dB';
  [...document.querySelectorAll('#genres .chip')].forEach(ch=>ch.classList.toggle('active', ch.dataset.id===cfg.genre));
  const corr=document.getElementById('correction'); if(corr) corr.value = cfg.correctionProfileID || '';
  const st=document.getElementById('importStatus');
  st.textContent = cfg.importedProfileName ? ('Imported: '+cfg.importedProfileName) : '';
}

function buildGenres(genres, active) {
  const host=document.getElementById('genres'); host.innerHTML='';
  genres.forEach(g=>{
    const b=document.createElement('button'); b.className='chip'+(g.id===active?' active':''); b.textContent=g.name; b.dataset.id=g.id;
    b.addEventListener('click', async ()=>{
      [...host.children].forEach(c=>c.classList.remove('active')); b.classList.add('active');
      const res=await post('/api/genre?value='+g.id); if(res.data.curve) draw(res.data.curve);
    });
    host.appendChild(b);
  });
}

function buildCorrection(profiles, active) {
  const sel=document.getElementById('correction'); sel.innerHTML='';
  const none=document.createElement('option'); none.value=''; none.textContent='None'; sel.appendChild(none);
  profiles.forEach(p=>{
    const o=document.createElement('option'); o.value=p.id;
    o.textContent = p.modelName + (p.wearStyle? ' · '+p.wearStyle : '') + (p.isFeatured? ' ★':'');
    sel.appendChild(o);
  });
  sel.value = active || '';
  sel.onchange = async ()=>{ const res=await post('/api/correction?id='+encodeURIComponent(sel.value)); if(res.data.curve) draw(res.data.curve); };
}

function fillDeviceSelect(sel, devices, chosen) {
  sel.innerHTML='';
  const auto=document.createElement('option'); auto.value=''; auto.textContent='Server default'; sel.appendChild(auto);
  devices.forEach(d=>{ const o=document.createElement('option'); o.value=d.name; o.textContent=d.name; sel.appendChild(o); });
  if(chosen) sel.value=chosen;
}

async function loadDevices() {
  const res=await api('GET','/api/devices'); const d=res.data;
  const hint=document.getElementById('engineHint');
  if(!d.serverAvailable){
    hint.innerHTML='No PulseAudio/PipeWire server detected. On Linux, install <code>pulseaudio-utils</code> or <code>pipewire-pulse</code>. '+
      'The EQ and file processing still work without it.';
    return;
  }
  hint.innerHTML='Route apps through the EQ: click <b>Create EQRouter sink</b>, set it as your system output, '+
    'then choose <code>EQRouter.monitor</code> as capture source and your real device as output sink, and press Start. '+
    'Or just capture an existing sink&#39;s <code>.monitor</code> to EQ everything you hear.';
  fillDeviceSelect(document.getElementById('source'), d.sources, null);
  fillDeviceSelect(document.getElementById('sink'), d.sinks.filter(x=>!x.isMonitor), d.defaultSink);
}

async function loadDeps() {
  const banner=document.getElementById('depsBanner');
  const res=await api('GET','/api/deps'); const d=res.data;
  if(!d.isLinux){ banner.style.display='none'; return; }
  if(d.satisfied){
    banner.className='banner ok'; banner.style.display='block';
    banner.innerHTML='<b>Audio tools ready.</b> parec / pacat / pactl are installed.';
    return;
  }
  banner.className='banner'; banner.style.display='block';
  let html='<b>Missing audio tools:</b> '+d.missing.join(', ')+'. These are needed for live routing.';
  if(d.command){
    html += '<span class="cmd">'+d.command+'</span>';
    html += '<div class="row">';
    if(d.canAutoInstall) html += '<button class="btn primary" id="installDeps">Install now'+(d.packageManager? ' ('+d.packageManager+')':'')+'</button> ';
    html += '<button class="btn" id="copyDeps">Copy command</button></div>';
  } else {
    html += '<div class="cmd">No supported package manager detected — install pulseaudio-utils (or your distro equivalent) manually.</div>';
  }
  banner.innerHTML=html;
  const inst=document.getElementById('installDeps');
  if(inst) inst.onclick=async()=>{
    inst.disabled=true; inst.textContent='Installing…';
    const r=await post('/api/deps/install');
    if(r.ok){ toast('Audio tools installed'); await loadDeps(); await loadDevices(); }
    else { toast(r.data.needsTerminal ? 'Run the command in a terminal' : (r.data.error||'Install failed')); inst.disabled=false; inst.textContent='Install now'; }
  };
  const cp=document.getElementById('copyDeps');
  if(cp) cp.onclick=()=>{ navigator.clipboard && navigator.clipboard.writeText(d.command); toast('Command copied'); };
}

function setEnginePill(running, error) {
  const pill=document.getElementById('enginePill'), lbl=document.getElementById('engineLabel');
  pill.classList.toggle('on', running);
  lbl.textContent = running ? 'routing' : (error ? 'stopped' : 'idle');
}

async function poll() {
  const res=await api('GET','/api/meters'); const m=res.data;
  const map=(db)=>Math.max(0,Math.min(100,(db+60)/60*100));
  document.getElementById('mIn').style.width = map(m.input)+'%';
  document.getElementById('mOut').style.width = map(m.output)+'%';
  setEnginePill(m.running, m.engineError);
}

async function boot() {
  const res=await api('GET','/api/state'); S=res.data;
  centerFreqs=S.centerFrequencies;
  buildBands();
  buildGenres(S.genres, S.config.genre);
  buildCorrection(S.profiles, S.config.correctionProfileID);
  applyConfig(S.config);
  draw(S.curve);
  setEnginePill(S.engine.running, S.engine.error);
  await loadDeps();
  await loadDevices();
  window.addEventListener('resize', ()=>draw(S && S.curve ? lastCurve : null));
  setInterval(poll, 250);
}
let lastCurve=null;
const origDraw=draw; draw=function(c){ if(c) lastCurve=c; origDraw(c); };

// wiring for output + toggles
const bindSlider=(id, path, numId, unit)=>{
  const s=document.getElementById(id), n=document.getElementById(numId);
  s.addEventListener('input', ()=>{ n.textContent=(+s.value).toFixed(1)+unit; });
  s.addEventListener('change', async ()=>{ const r=await post(path+'?db='+s.value); if(r.data.curve) draw(r.data.curve); });
};
const bindToggle=(id, path)=>{
  document.getElementById(id).addEventListener('change', async (e)=>{
    const r=await post(path+'?on='+(e.target.checked?'1':'0')); if(r.data.curve) draw(r.data.curve);
  });
};

document.getElementById('resetBtn').onclick=async()=>{ const r=await post('/api/reset'); if(r.data.curve) draw(r.data.curve); applyConfig((await api('GET','/api/state')).data.config); };
bindToggle('customBypass','/api/bypass/custom');
bindToggle('correctionBypass','/api/bypass/correction');
bindToggle('mute','/api/mute');
bindToggle('ceiling','/api/ceiling');
bindSlider('gain','/api/gain','gainNum',' dB');
bindSlider('trim','/api/trim','trimNum',' dB');

document.getElementById('importBtn').onclick=async()=>{
  const name=encodeURIComponent(document.getElementById('importName').value || 'Imported');
  const text=document.getElementById('importText').value;
  const r=await fetch('/api/import?name='+name,{method:'POST',body:text});
  if(r.ok){ const d=await r.json(); S=d; applyConfig(d.config); draw(d.curve); buildCorrection(d.profiles, d.config.correctionProfileID); toast('Imported preset applied'); }
  else { toast('Import failed — no valid filters'); }
};
document.getElementById('importClear').onclick=async()=>{ const r=await post('/api/import/clear'); S=r.data; applyConfig(r.data.config); draw(r.data.curve); toast('Imported preset cleared'); };

document.getElementById('startBtn').onclick=async()=>{
  const source=encodeURIComponent(document.getElementById('source').value);
  const sink=encodeURIComponent(document.getElementById('sink').value);
  const r=await post('/api/engine/start?source='+source+'&sink='+sink);
  if(r.ok) toast('Routing started'); else toast(r.data.error || 'Start failed');
  poll();
};
document.getElementById('stopBtn').onclick=async()=>{ await post('/api/engine/stop'); toast('Routing stopped'); poll(); };
document.getElementById('setupSink').onclick=async()=>{
  const r=await post('/api/engine/setup-sink');
  if(r.ok){ toast('EQRouter sink created — set it as system output'); await loadDevices();
            document.getElementById('source').value='EQRouter.monitor'; }
  else toast(r.data.error||'Failed to create sink');
};
document.getElementById('refreshDev').onclick=loadDevices;

boot();
</script>
</body>
</html>
"""
}
