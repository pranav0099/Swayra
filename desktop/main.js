// Swayra desktop app — ONE program, ONE icon.
//
// A single launch opens BOTH the full app window AND the small desktop
// countdown widget that sits on your wallpaper. It is single-instance: clicking
// the icon again (or the auto-start at login) never opens a second copy — it
// just brings the existing one back / makes sure the widget is showing.
//
// Serves the Flutter web build from an INTERNAL localhost server (part of this
// process — no separate server to run) and shows it in a Chromium window.
// Hardware acceleration is disabled so it works on machines without a usable
// GPU (pure software rendering, same fallback your browser uses).
//
//   electron .            -> app window + desktop widget (the normal icon)
//   electron . --widget   -> just the desktop widget (used by login auto-start)

const { app, BrowserWindow, screen, shell, session } = require('electron');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

// Redirect console logs to widget-log.txt for debugging
const logFilePath = path.join(__dirname, 'widget-log.txt');
const logStream = fs.createWriteStream(logFilePath, { flags: 'a' });
const originalLog = console.log;
const originalError = console.error;
console.log = (...args) => {
  const msg = `[${new Date().toISOString()}] ` + args.map(a => typeof a === 'object' ? JSON.stringify(a) : a).join(' ');
  logStream.write(msg + '\n');
  originalLog(...args);
};
console.error = (...args) => {
  const msg = `[${new Date().toISOString()}] ERROR: ` + args.map(a => typeof a === 'object' ? JSON.stringify(a) : a).join(' ');
  logStream.write(msg + '\n');
  originalError(...args);
};

// No GPU on this machine — force software rendering so we never touch the
// graphics driver (that's what crashed the Android emulator).
app.disableHardwareAcceleration();
app.commandLine.appendSwitch('disable-gpu');
app.commandLine.appendSwitch('disable-gpu-compositing');
// KEY FIX for "widget shows 1 second then disappears": once a window is covered,
// Chromium's occlusion detection marks it hidden and STOPS drawing it — which
// makes a wallpaper-pinned widget vanish. Turn that off so it keeps painting.
app.commandLine.appendSwitch('disable-features', 'CalculateNativeWinOcclusion');

// FIXED port so the app's origin (and therefore its saved data in localStorage)
// stays the same across launches, and so the widget shares the same data.
const PORT = 47821;
const WEB_DIR = path.join(__dirname, '..', 'study_desk', 'build', 'web');

// The two windows. We keep references so a second launch reuses them instead of
// opening duplicates, and so closing the app window leaves the widget alone.
let mainWin = null;
let widgetWin = null;
let serverStarted = false;
// Wallpaper mode is ON by default — the widget lives on the desktop wallpaper at
// every boot. If the wallpaper layer ever misbehaves on this machine, launch
// with SD_NO_WALLPAPER=1 to fall back to a hidden/non-pinned widget.
let pinToWallpaperEnabled = process.env.SD_NO_WALLPAPER !== '1';

// Habit taps made on the desktop widget, waiting for the app to pick them up.
const pendingWidgetActions = [];

function localDateStr(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

// Mirror of AppState.toggleHabit for the widget's own copy of the data, so the
// card ticks instantly. The app remains the source of truth — its next mirror
// pass overwrites this file.
function applyHabitToggleToStateFile(habitId) {
  const file = path.join(__dirname, 'state.json');
  let state = {};
  try {
    state = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    return;
  }
  const today = localDateStr();
  const logs = state.dayLogs || {};
  const day = logs[today] || { habits: [], focus: 0, topics: 0, goals: 0 };
  const done = new Set(day.habits || []);
  if (done.has(habitId)) done.delete(habitId);
  else done.add(habitId);
  day.habits = [...done];

  if (!day.habits.length && !day.focus && !day.topics && !day.goals) delete logs[today];
  else logs[today] = day;

  state.dayLogs = logs;
  try {
    fs.writeFileSync(file, JSON.stringify(state));
  } catch (e) {
    console.error('[widget] could not update state.json', e);
  }
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream', '.map': 'application/json', '.symbols': 'text/plain',
};

function handler(req, res) {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  console.log(`[server] ${req.method} ${urlPath}`);
  // Never let the shell cache the app files, so rebuilds (new theme/code) show
  // up immediately instead of serving a stale copy.
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');

  // --- CORS & OPTIONS handling for API endpoints ---
  if (urlPath.startsWith('/api/')) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      return res.end();
    }
  }

  // --- Widget control API (called by the Flutter app's widget toggle button) ---
  if (urlPath === '/api/widget/toggle') {
    if (widgetWin && widgetWin.isVisible()) {
      widgetWin.hide();
    } else {
      ensureWidgetWindow();
    }
    const visible = !!(widgetWin && widgetWin.isVisible());
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, visible }));
  }
  if (urlPath === '/api/widget/pin-wallpaper') {
    const parsed = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const enabled = parsed.searchParams.get('enabled') === 'true';
    pinToWallpaperEnabled = enabled;

    if (widgetWin) {
      const b = screen.getPrimaryDisplay().bounds;
      const W = 240, H = 268;
      const px = b.x + b.width - W - 24;
      const py = b.y + 24;
      if (enabled) {
        widgetWin.setAlwaysOnTop(false);
        widgetWin.showInactive();
        pinToWallpaper(widgetWin, px, py, W, H);
      } else {
        unpinFromWallpaper(widgetWin, px, py, W, H);
      }
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, pinToWallpaperEnabled }));
  }
  if (urlPath === '/api/widget/show') {
    ensureWidgetWindow();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end('{"ok":true,"visible":true}');
  }
  if (urlPath === '/api/widget/hide') {
    if (widgetWin) widgetWin.hide();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end('{"ok":true,"visible":false}');
  }
  // --- Tap-to-tick from the desktop widget ---------------------------------
  // The widget can't reach into the Flutter app's memory, so a tap is queued
  // here and the app drains the queue on its next poll (see drainWidgetActions
  // in lib/models.dart). state.json is also updated optimistically so the
  // widget repaints immediately instead of waiting for the round trip.
  if (urlPath === '/api/widget/toggle-habit') {
    const parsed = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const habitId = parsed.searchParams.get('id');
    if (!habitId) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      return res.end('{"error":"id required"}');
    }
    pendingWidgetActions.push({ type: 'toggleHabit', id: habitId, date: localDateStr() });
    applyHabitToggleToStateFile(habitId);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, queued: pendingWidgetActions.length }));
  }
  // The app polls this and applies whatever it finds; reading drains the queue.
  if (urlPath === '/api/widget/actions') {
    const actions = pendingWidgetActions.splice(0, pendingWidgetActions.length);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ actions }));
  }

  if (urlPath === '/api/widget/status') {
    const visible = !!(widgetWin && widgetWin.isVisible());
    const pinned = pinToWallpaperEnabled;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ visible, pinned }));
  }

  // The widget page lives next to this file (so `flutter build web` can't
  // overwrite it) but is served from the SAME origin as the app, so it shares
  // the app's saved data in localStorage.
  if (urlPath === '/widget' || urlPath === '/widget.html') {
    return fs.readFile(path.join(__dirname, 'widget.html'), (e, d) => {
      if (e) { res.writeHead(404); return res.end('no widget'); }
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(d);
    });
  }
  // The app mirrors its data here so the (separate window) widget can read it.
  if (urlPath === '/state.json') {
    return fs.readFile(path.join(__dirname, 'state.json'), (e, d) => {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(e ? '{}' : d);
    });
  }
  if (urlPath === '/') urlPath = '/index.html';
  const filePath = path.normalize(path.join(WEB_DIR, urlPath));
  if (!filePath.startsWith(WEB_DIR)) { res.writeHead(403); return res.end('Forbidden'); }
  fs.readFile(filePath, (err, data) => {
    if (err) {
      return fs.readFile(path.join(WEB_DIR, 'index.html'), (e2, d2) => {
        if (e2) { res.writeHead(404); return res.end('Not found'); }
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(d2);
      });
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
}

// Start the internal server once. If somehow already bound, just reuse it.
function startServer() {
  return new Promise((resolve) => {
    if (serverStarted) return resolve(PORT);
    const server = http.createServer(handler);
    server.on('error', () => { serverStarted = true; resolve(PORT); });
    server.listen(PORT, '127.0.0.1', () => { serverStarted = true; resolve(PORT); });
  });
}

function maybeCapture(win, isMain) {
  if (!process.env.SD_CAPTURE || !isMain) return;
  win.webContents.once('did-finish-load', () => {
    setTimeout(async () => {
      try {
        win.show();
        win.focus();
        await new Promise((r) => setTimeout(r, 800));
        const img = await win.webContents.capturePage();
        const png = img.toPNG();
        fs.writeFileSync(process.env.SD_CAPTURE, png);
        console.log('CAPTURED ' + process.env.SD_CAPTURE + ' bytes=' + png.length);
      } catch (e) { console.error('capture failed', e); }
      app.quit();
    }, 11000);
  });
}

async function ensureMainWindow() {
  if (mainWin) { // already open — just bring it forward
    if (mainWin.isMinimized()) mainWin.restore();
    mainWin.show();
    mainWin.focus();
    return mainWin;
  }
  const port = await startServer();
  mainWin = new BrowserWindow({
    width: 960, height: 820, minWidth: 380, minHeight: 600,
    title: 'Swayra', backgroundColor: '#FBFCFE', autoHideMenuBar: true,
    webPreferences: { contextIsolation: true },
  });
  mainWin.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });

  // Mirror the app's saved data to state.json so the desktop widget always has
  // the latest exam/countdown to show.
  const mirror = () => {
    if (!mainWin) return;
    mainWin.webContents.executeJavaScript(
      "(function(){let r=localStorage.getItem('flutter.Swayra:v1');" +
      "if(!r){for(let i=0;i<localStorage.length;i++){let k=localStorage.key(i);" +
      "if(k&&k.indexOf('Swayra:v1')>=0){r=localStorage.getItem(k);break;}}}return r;})()",
      true
    ).then((v) => {
      if (!v) return;
      try {
        // shared_preferences stores the string JSON-encoded, so it may be
        // wrapped once ("\"{...}\"") — unwrap until we get the real object.
        let obj = JSON.parse(v);
        if (typeof obj === 'string') obj = JSON.parse(obj);
        fs.writeFileSync(path.join(__dirname, 'state.json'), JSON.stringify(obj));
        // Nudge the widget to repaint with the fresh data right away.
        if (widgetWin) widgetWin.webContents.executeJavaScript('window.render&&window.render()').catch(() => {});
      } catch (e) {}
    }).catch(() => {});
  };
  mainWin.webContents.on('did-finish-load', () => {
    setTimeout(mirror, 4000);   // after Flutter boots + seeds
    setInterval(mirror, 5000);  // keep it fresh while the app is open
  });
  mainWin.on('closed', () => { mainWin = null; });

  // Drop the old cached build + Flutter service worker so theme/code changes
  // actually appear. We clear ONLY caches — never 'localstorage'/'indexdb',
  // which hold the user's Swayra data.
  try {
    await session.defaultSession.clearCache();
    await session.defaultSession.clearStorageData(
        { storages: ['serviceworkers', 'cachestorage', 'shadercache'] });
  } catch (e) { console.error('cache clear failed', e); }

  maybeCapture(mainWin, true);
  mainWin.loadURL(`http://127.0.0.1:${port}/`);
  return mainWin;
}

// Reparent the widget window INTO the desktop wallpaper layer (Windows WorkerW)
// so the countdown lives on your wallpaper: visible whenever you're at the
// desktop, and always behind your apps (never covering your work). Uses a tiny
// PowerShell helper (no GPU, no extra packages). Falls back silently if it
// can't find the wallpaper window.
function pinToWallpaper(win, x, y, w, h) {
  if (process.platform !== 'win32') return;
  try {
    const buf = win.getNativeWindowHandle();
    const hwnd = buf.length >= 8
      ? buf.readBigUInt64LE(0).toString()
      : BigInt(buf.readUInt32LE(0)).toString();
    const script = path.join(__dirname, 'pin-to-wallpaper.ps1');
    execFile(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script,
        '-Hwnd', hwnd, '-X', String(x), '-Y', String(y), '-W', String(w), '-H', String(h)],
      { windowsHide: true },
      (err, stdout, stderr) => {
        if (err) {
          console.error('[widget] wallpaper pin failed:', err.message, (stderr || '').trim());
        } else {
          console.log('[widget] wallpaper pin:', (stdout || '').trim());
          // Force a repaint in Electron by slightly changing size and restoring it
          setTimeout(() => {
            if (widgetWin) {
              widgetWin.showInactive();
              const bounds = widgetWin.getBounds();
              widgetWin.setBounds({ ...bounds, width: bounds.width + 1 });
              setTimeout(() => {
                if (widgetWin) widgetWin.setBounds(bounds);
              }, 50);
            }
          }, 100);
        }
      }
    );
  } catch (e) {
    console.error('[widget] wallpaper pin error:', e);
  }
}

function unpinFromWallpaper(win, x, y, w, h) {
  if (process.platform !== 'win32') return;
  try {
    const buf = win.getNativeWindowHandle();
    const hwnd = buf.length >= 8
      ? buf.readBigUInt64LE(0).toString()
      : BigInt(buf.readUInt32LE(0)).toString();
    const script = path.join(__dirname, 'pin-to-wallpaper.ps1');
    execFile(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script,
        '-Hwnd', hwnd, '-X', String(x), '-Y', String(y), '-W', String(w), '-H', String(h), '-Unpin'],
      { windowsHide: true },
      (err, stdout, stderr) => {
        if (err) {
          console.error('[widget] wallpaper unpin failed:', err.message, (stderr || '').trim());
        } else {
          console.log('[widget] wallpaper unpin:', (stdout || '').trim());
          if (widgetWin) {
            widgetWin.setAlwaysOnTop(true);
            widgetWin.hide(); // Hide the widget completely when unpinned
          }
        }
      }
    );
  } catch (e) {
    console.error('[widget] wallpaper unpin error:', e);
  }
}

async function ensureWidgetWindow() {
  if (widgetWin) {
    if (pinToWallpaperEnabled || process.env.SD_WALLPAPER === '1') {
      widgetWin.showInactive();
    } else {
      widgetWin.hide();
    }
    return widgetWin;
  }
  const port = await startServer();
  const b = screen.getPrimaryDisplay().bounds; // full screen incl. wallpaper area
  const wa = screen.getPrimaryDisplay().workArea;
  const W = 240, H = 268;
  // Where it sits on the wallpaper (top-right corner, WorkerW coordinates).
  const px = b.x + b.width - W - 24;
  const py = b.y + 24;
  widgetWin = new BrowserWindow({
    width: W, height: H,
    x: wa.x + wa.width - W - 24,
    y: wa.y + 24,
    frame: false, resizable: false, movable: true,
    // Wallpaper widget: NOT topmost and NOT focusable — it lives on the desktop
    // behind your apps, like part of the wallpaper.
    alwaysOnTop: false,
    focusable: false,
    skipTaskbar: true,          // no taskbar button / alt-tab clutter
    fullscreenable: false, maximizable: false, minimizable: false,
    show: false,
    paintWhenInitiallyHidden: true, // render even before/while hidden
    backgroundColor: '#FFFFFF', // opaque — software rendering, no transparency
    title: 'Swayra Widget',
    // backgroundThrottling:false keeps it drawing/updating while it sits on the
    // wallpaper behind other windows.
    webPreferences: { contextIsolation: true, backgroundThrottling: false },
  });

  // Show it in the corner without stealing focus from your work.
  widgetWin.once('ready-to-show', () => {
    // Only show if wallpaper pinning is enabled (meaning it is on the wallpaper),
    // otherwise keep it hidden to avoid floating on top of other apps.
    if (pinToWallpaperEnabled || process.env.SD_WALLPAPER === '1') {
      widgetWin.setAlwaysOnTop(false);
      widgetWin.showInactive();
      setTimeout(() => pinToWallpaper(widgetWin, px, py, W, H), 600);
    } else {
      widgetWin.hide();
    }
  });
  widgetWin.on('closed', () => { widgetWin = null; });

  maybeCapture(widgetWin, false);
  widgetWin.loadURL(`http://127.0.0.1:${port}/widget.html`);
  return widgetWin;
}

// Open the right set of windows for a given launch (argv from this or a second
// instance). The plain icon opens the app + widget together; the login
// auto-start passes --widget to show only the small countdown card.
function openFor(argv) {
  const widgetOnly = (argv || []).includes('--widget');
  if (widgetOnly) {
    ensureWidgetWindow();
  } else {
    ensureMainWindow();
    ensureWidgetWindow();
  }
}

// ---- single instance: never open a second copy ----
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', (_e, argv) => {
    // Someone launched Swayra again — reuse this running copy.
    openFor(argv);
  });

  app.whenReady().then(() => openFor(process.argv));

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) openFor(process.argv);
  });

  // Quit only when EVERYTHING (app + widget) is closed, so closing the app
  // window leaves the wallpaper widget running, and vice-versa.
  app.on('window-all-closed', () => app.quit());
}
