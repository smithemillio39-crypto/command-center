'use strict';

/*
 * Command Center agent - runs on the Windows PC.
 * The iPhone app talks to this over your home network with a shared token.
 *
 *   node server.js
 *
 * No dependencies. Config lives in agent.config.json (created on first run).
 */

const http = require('node:http');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFile, spawn } = require('node:child_process');
const { createFileService } = require('./files');

const CONFIG_PATH = path.join(__dirname, 'agent.config.json');
const AGENT_VERSION = '1.0.0';
const MAX_BODY = 8 * 1024;
const IS_WINDOWS = process.platform === 'win32';

/* ------------------------------------------------------------------ config */

function writeConfig(cfg) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2) + '\n');
}

function loadConfig() {
  const cfg = { port: 8765, token: '' };

  if (fs.existsSync(CONFIG_PATH)) {
    try {
      Object.assign(cfg, JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')));
    } catch (err) {
      console.error('agent.config.json is not valid JSON: ' + err.message);
      console.error('Fix or delete it and start again.');
      process.exit(1);
    }
  }

  if (!cfg.token) {
    cfg.token = crypto.randomBytes(16).toString('hex');
    writeConfig(cfg);
    console.log('Created agent.config.json with a new pairing token.');
  }

  if (process.env.AGENT_PORT) cfg.port = Number(process.env.AGENT_PORT);
  if (process.env.AGENT_TOKEN) cfg.token = process.env.AGENT_TOKEN;

  return cfg;
}

/* ------------------------------------------------------------- pc commands */

const state = { volume: 50, muted: false };

function run(exe, args) {
  return new Promise((resolve, reject) => {
    execFile(
      exe,
      args,
      { timeout: 15000, windowsHide: true },
      (err, stdout, stderr) => {
        if (err) reject(new Error((stderr || err.message || '').toString().trim()));
        else resolve((stdout || '').toString().trim());
      }
    );
  });
}

function ps(script) {
  return run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    script,
  ]);
}

const psString = (value) => "'" + String(value).replace(/'/g, "''") + "'";

// Windows virtual-key codes for the media/volume keys.
const VK = { mute: 173, down: 174, up: 175, next: 176, prev: 177, stop: 178, playPause: 179 };

function tapKey(code, times = 1) {
  const n = Math.max(1, Math.min(60, Math.round(Number(times) || 1)));
  return ps(
    '$w = New-Object -ComObject WScript.Shell; ' +
      `1..${n} | ForEach-Object { $w.SendKeys([char]${code}) }`
  );
}

/*
 * LYRA Homecoming is a PySide6 desktop app, so it cannot be compiled for iOS.
 * The phone can still start it on the PC and drive it through the existing
 * screen stream; these defaults mirror the desktop shortcut.
 */
const LYRA = {
  root: process.env.LYRA_ROOT || path.join(os.homedir(), 'source', 'LYRA-Homecoming'),
  data: process.env.LYRA_DATA || 'C:\\LyraHomecoming\\checkpoints\\W005-MAIN-profile',
  state: process.env.LYRA_STATE || path.join(
    os.homedir(), 'Documents', 'Codex', '2026-11-22',
    'files-pasted-by-the-user-codex', 'outputs', 'Aether Five-Brain', 'data'
  ),
};

function lyraLaunch() {
  const python = path.join(LYRA.root, '.venv', 'Scripts', 'pythonw.exe');
  const main = path.join(LYRA.root, 'main.py');
  for (const file of [python, main]) {
    if (!fs.existsSync(file)) throw new Error(`LYRA Homecoming is not installed at ${LYRA.root}`);
  }
  return {
    file: python,
    args: ['-EB', main, '--live-profile', '--data', LYRA.data, '--aether-state', LYRA.state],
    cwd: LYRA.root,
  };
}

const ALIASES = {
  steam: 'steam://open/main',
  'steam-bigpicture': 'steam://open/bigpicture',
  'steam big picture': 'steam://open/bigpicture',
  chrome: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  edge: 'msedge.exe',
  discord: 'discord://',
  spotify: 'spotify://',
  explorer: 'explorer.exe',
  taskmgr: 'taskmgr.exe',
  settings: 'ms-settings:',
  terminal: 'wt.exe',
};

const ACTIONS = {
  'volume.up': async (value) => {
    const presses = Number(value) || 2;
    await tapKey(VK.up, presses);
    state.volume = Math.min(100, state.volume + presses * 2);
    state.muted = false;
    return `volume ${state.volume}%`;
  },

  'volume.down': async (value) => {
    const presses = Number(value) || 2;
    await tapKey(VK.down, presses);
    state.volume = Math.max(0, state.volume - presses * 2);
    return `volume ${state.volume}%`;
  },

  'volume.mute': async () => {
    await tapKey(VK.mute, 1);
    state.muted = !state.muted;
    return state.muted ? 'muted' : 'unmuted';
  },

  // Absolute volume: Windows has no dependency-free "set level" call, so drop to
  // zero and step back up. Each volume key press is 2%.
  'volume.set': async (value) => {
    const target = Math.max(0, Math.min(100, Math.round(Number(value))));
    await tapKey(VK.down, 50);
    const up = Math.round(target / 2);
    if (up > 0) await tapKey(VK.up, up);
    state.volume = target;
    state.muted = false;
    return `volume ${target}%`;
  },

  'media.playpause': async () => {
    await tapKey(VK.playPause, 1);
    return 'play/pause';
  },

  'media.next': async () => {
    await tapKey(VK.next, 1);
    return 'next track';
  },

  'media.prev': async () => {
    await tapKey(VK.prev, 1);
    return 'previous track';
  },

  'media.stop': async () => {
    await tapKey(VK.stop, 1);
    return 'stop';
  },

  'system.lock': async () => {
    await run('rundll32.exe', ['user32.dll,LockWorkStation']);
    return 'locked';
  },

  'system.sleep': async () => {
    // Sleep, unless hibernation is enabled (then this hibernates instead).
    await run('rundll32.exe', ['powrprof.dll,SetSuspendState', '0,1,0']);
    return 'sleeping';
  },

  'system.displayOff': async () => {
    const sig =
      '[DllImport("user32.dll")] public static extern int SendMessage(int hWnd, int hMsg, int wParam, int lParam);';
    await ps(
      `$t = Add-Type -MemberDefinition '${sig}' -Name U32 -Namespace Win -PassThru; ` +
        '$t::SendMessage(-1, 0x0112, 0xF170, 2) | Out-Null'
    );
    return 'display off';
  },

  // 60 second delay so it can be cancelled from the app.
  'system.shutdown': async () => {
    await run('shutdown.exe', ['/s', '/t', '60']);
    return 'shutting down in 60s';
  },

  'system.restart': async () => {
    await run('shutdown.exe', ['/r', '/t', '60']);
    return 'restarting in 60s';
  },

  'system.cancelShutdown': async () => {
    await run('shutdown.exe', ['/a']);
    return 'shutdown cancelled';
  },

  'app.launch': async (value) => {
    const raw = String(value || '').trim();
    if (!raw) throw new Error('app.launch needs a target');

    if (raw.toLowerCase() === 'lyra') {
      const spec = lyraLaunch();
      const args = spec.args.map(psString).join(',');
      await ps(
        `Start-Process -FilePath ${psString(spec.file)} -ArgumentList @(${args}) ` +
        `-WorkingDirectory ${psString(spec.cwd)}`
      );
      return 'started LYRA Homecoming';
    }

    const target = ALIASES[raw.toLowerCase()] || raw;
    await ps(`Start-Process ${psString(target)}`);
    return `launched ${target}`;
  },
};

/* ---------------------------------------------------------------- pairing */

function tokenMatches(given) {
  const a = Buffer.from(String(given || ''));
  const b = Buffer.from(config.token);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

function readToken(req) {
  const header = req.headers['x-agent-token'];
  if (typeof header === 'string' && header) return header;
  const url = new URL(req.url, 'http://localhost');
  return url.searchParams.get('token') || '';
}

function send(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(new Error('request body too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

/* ------------------------------------------------------- screen streaming */

/*
 * GET /stream?token=..&width=1280&fps=20&q=7
 *
 * ffmpeg captures the desktop and emits MJPEG on its stdout; this process
 * re-frames it as 4-byte big-endian length + one JPEG per frame, so the iPhone
 * can parse the stream without a container format or an HLS player. One ffmpeg
 * per connected client, killed when the client disconnects.
 */

// q is ffmpeg's -q:v: lower is sharper and heavier. 10 measured ~2.4 MB/s at
// 1280x720/20 fps, which leaves headroom on Wi-Fi; 7 cost 3.5 MB/s.
const STREAM_LIMITS = { width: [480, 1920, 1280], fps: [5, 30, 20], q: [2, 20, 10] };

function clampParam(value, key) {
  const [min, max, fallback] = STREAM_LIMITS[key];
  // Number(null) and Number('') are 0, which would clamp to the minimum
  // instead of falling back, so reject absent values explicitly.
  if (value === null || value === undefined || value === '') return fallback;
  const n = Math.round(Number(value));
  return Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : fallback;
}

function streamScreen(req, res, url) {
  const width = clampParam(url.searchParams.get('width'), 'width');
  const fps = clampParam(url.searchParams.get('fps'), 'fps');
  const quality = clampParam(url.searchParams.get('q'), 'q');

  console.log(`paddle: opening ${width}px @ ${fps} fps (q${quality})`);

  const ff = spawn(
    'ffmpeg',
    [
      '-hide_banner', '-loglevel', 'error', '-nostdin',
      '-f', 'gdigrab', '-framerate', String(fps), '-i', 'desktop',
      '-vf', `scale=${width}:-2:flags=bilinear`,
      '-f', 'mjpeg', '-q:v', String(quality),
      '-flush_packets', '1', 'pipe:1',
    ],
    { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] }
  );

  let opened = false;
  const begin = () => {
    if (opened) return;
    opened = true;
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Cache-Control': 'no-store',
      'X-Stream-Format': 'jpeg-length-prefixed',
    });
  };

  const SOI = Buffer.from([0xff, 0xd8]);
  const EOI = Buffer.from([0xff, 0xd9]);
  let pending = Buffer.alloc(0);

  ff.stdout.on('data', (chunk) => {
    pending = Buffer.concat([pending, chunk]);
    for (;;) {
      const start = pending.indexOf(SOI);
      if (start < 0) {
        pending = Buffer.alloc(0);
        break;
      }
      const end = pending.indexOf(EOI, start + 2);
      if (end < 0) {
        pending = pending.subarray(start);
        break;
      }
      const frame = pending.subarray(start, end + 2);
      pending = pending.subarray(end + 2);
      begin();
      const header = Buffer.alloc(4);
      header.writeUInt32BE(frame.length);
      res.write(header);
      res.write(frame);
    }
  });

  ff.stderr.on('data', (data) => process.stderr.write('[ffmpeg] ' + data));

  const stop = () => {
    if (!ff.killed) ff.kill('SIGKILL');
    try { res.end(); } catch {}
  };

  ff.on('error', (err) => {
    console.error('ffmpeg failed to start: ' + err.message);
    if (!opened) {
      opened = true;
      send(res, 503, { ok: false, error: 'ffmpeg is not available on this PC' });
    } else {
      stop();
    }
  });
  ff.on('exit', () => { try { res.end(); } catch {} });
  req.on('close', stop);
  res.on('close', stop);
}

/* -------------------------------------------------------------- input pipe */

let inputProcess = null;
const INPUT_TYPES = new Set(['move', 'down', 'up', 'click', 'scroll', 'key', 'type']);
const MAX_TYPED_CHARS = 4000;

function inputHelper() {
  if (inputProcess && !inputProcess.killed) return inputProcess;
  inputProcess = spawn(
    'powershell.exe',
    ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, 'input.ps1')],
    { windowsHide: true, stdio: ['pipe', 'ignore', 'pipe'] }
  );
  inputProcess.stderr.on('data', (data) => process.stderr.write('[input] ' + data));
  inputProcess.on('exit', () => { inputProcess = null; });
  inputProcess.on('error', () => { inputProcess = null; });
  return inputProcess;
}

function applyInput(body) {
  const type = String(body.t || '');
  if (!INPUT_TYPES.has(type)) throw new Error(`unknown input type "${type}"`);

  if (type === 'move' || (type === 'click' && body.x !== undefined)) {
    const x = Number(body.x);
    const y = Number(body.y);
    if (!(x >= 0 && x <= 1 && y >= 0 && y <= 1)) throw new Error('x and y must be between 0 and 1');
  }
  if (type === 'scroll') {
    const d = Number(body.d);
    if (!Number.isInteger(d) || Math.abs(d) > 2000) throw new Error('scroll needs an integer d');
  }
  if (type === 'key') {
    const vk = Number(body.vk);
    if (!Number.isInteger(vk) || vk < 1 || vk > 254) throw new Error('key needs a virtual-key code 1..254');
  }
  if (type === 'type') {
    if (typeof body.text !== 'string' || body.text.length === 0) {
      throw new Error('type needs a non-empty text string');
    }
    if (body.text.length > MAX_TYPED_CHARS) {
      throw new Error(`type is limited to ${MAX_TYPED_CHARS} characters per call`);
    }
  }
  if (body.b !== undefined && ![1, 2].includes(Number(body.b))) throw new Error('b must be 1 or 2');

  const helper = inputHelper();
  if (!helper.stdin.writable) throw new Error('input helper is not running');
  helper.stdin.write(JSON.stringify(body) + '\n');
  return type;
}

/* ------------------------------------------------------------ file bridge */

let fileServiceCache = null;

function fileService() {
  if (fileServiceCache) return fileServiceCache;

  const configured = process.env.AGENT_FILE_ROOTS
    ? process.env.AGENT_FILE_ROOTS.split(';')
        .filter(Boolean)
        .map((item) => {
          const split = item.indexOf('=');
          if (split < 1) throw new Error('AGENT_FILE_ROOTS entries look like label=D:\\path');
          return { label: item.slice(0, split).trim(), path: item.slice(split + 1).trim() };
        })
    : [{ label: 'share', path: path.join(os.homedir(), 'CommandCenter', 'Files') }];

  fileServiceCache = createFileService(configured);
  for (const root of fileServiceCache.roots()) {
    try {
      fs.mkdirSync(root.path, { recursive: true });
    } catch (err) {
      console.error(`could not create the shared folder ${root.path}: ${err.message}`);
    }
  }
  return fileServiceCache;
}

async function handleFiles(req, res, url) {
  try {
    const service = fileService();
    const root = url.searchParams.get('root');
    const target = url.searchParams.get('path') || '';

    if (req.method === 'GET' && url.pathname === '/files') {
      send(res, 200, { ok: true, roots: service.roots(), ...service.list(root, target) });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/files/raw') {
      const file = service.open(root, target);
      res.writeHead(200, {
        'Content-Type': file.type,
        'Content-Length': file.size,
        'Content-Disposition': `attachment; filename="${encodeURIComponent(file.name)}"`,
        'Cache-Control': 'no-store',
      });
      fs.createReadStream(file.absolute).pipe(res);
      return;
    }

    if (req.method === 'POST' && url.pathname === '/files/upload') {
      const result = await service.upload(root, target, url.searchParams.get('name'), req);
      console.log(`uploaded ${result.name} (${result.size} bytes)`);
      send(res, 200, { ok: true, ...result });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/files/folder') {
      send(res, 200, { ok: true, ...service.folder(root, target) });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/files/rename') {
      const result = service.rename(root, target, url.searchParams.get('name'));
      console.log(`renamed to ${result.path}`);
      send(res, 200, { ok: true, ...result });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/files/trash') {
      const result = service.trash(root, target);
      console.log(`moved to trash: ${result.moved}`);
      send(res, 200, { ok: true, ...result });
      return;
    }

    send(res, 404, { ok: false, error: 'not found' });
  } catch (err) {
    send(res, err.status || 500, { ok: false, error: err.message });
  }
}

/* ------------------------------------------------------------------ server */

const config = loadConfig();

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');

  try {
    if (req.method === 'GET' && (url.pathname === '/remote' || url.pathname === '/remote/')) {
      fs.readFile(path.join(__dirname, 'public', 'remote.html'), (error, page) => {
        if (error) {
          send(res, 500, { ok: false, error: 'the remote page is missing from public/remote.html' });
          return;
        }
        res.writeHead(200, {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
        });
        res.end(page);
      });
      return;
    }

    // The remote page paints this behind its glass, so it has to load without
    // the token the page itself already carries.
    if (req.method === 'GET' && url.pathname === '/backdrop.jpg') {
      fs.readFile(path.join(__dirname, 'public', 'backdrop.jpg'), (error, image) => {
        if (error) {
          send(res, 404, { ok: false, error: 'backdrop.jpg is missing from public/' });
          return;
        }
        res.writeHead(200, {
          'Content-Type': 'image/jpeg',
          'Cache-Control': 'public, max-age=86400',
        });
        res.end(image);
      });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(
        '<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">' +
          '<body style="font:16px -apple-system,system-ui;background:#0b0c10;color:#eee;padding:24px">' +
          '<h1 style="font-size:20px">Command Center agent</h1>' +
          `<p>Running on <b>${os.hostname()}</b> - port ${config.port}</p>` +
          '<p style="color:#9aa">Waiting for the iPhone app. Pair with the token in agent.config.json.</p>' +
          '<p><a style="color:#8b5cf6" href="/remote">Open the phone-style remote</a></p>' +
          '</body>'
      );
      return;
    }

    if (!tokenMatches(readToken(req))) {
      send(res, 401, { ok: false, error: 'bad token' });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/status') {
      send(res, 200, {
        ok: true,
        host: os.hostname(),
        platform: process.platform,
        agentVersion: AGENT_VERSION,
        volume: state.volume,
        muted: state.muted,
        commands: Object.keys(ACTIONS),
        stream: true,
        input: true,
        files: true,
        fileRoots: fileService().roots().map((root) => root.label),
      });
      return;
    }

    // Paddle is the stream; /stream stays as the original alias.
    if (req.method === 'GET' && (url.pathname === '/paddle' || url.pathname === '/stream')) {
      if (!IS_WINDOWS) {
        send(res, 501, { ok: false, error: 'screen capture needs a Windows PC' });
        return;
      }
      streamScreen(req, res, url);
      return;
    }

    if (url.pathname === '/files' || url.pathname.startsWith('/files/')) {
      await handleFiles(req, res, url);
      return;
    }

    if (req.method === 'POST' && url.pathname === '/input') {
      const raw = await readBody(req);
      let body;
      try {
        body = raw ? JSON.parse(raw) : {};
      } catch {
        send(res, 400, { ok: false, error: 'body must be JSON' });
        return;
      }
      if (!IS_WINDOWS) {
        send(res, 501, { ok: false, error: 'this agent only drives Windows PCs' });
        return;
      }
      try {
        const applied = applyInput(body);
        send(res, 200, { ok: true, applied });
      } catch (err) {
        send(res, 400, { ok: false, error: err.message });
      }
      return;
    }

    if (req.method === 'GET' && url.pathname === '/windows') {
      try {
        const output = await run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          path.join(__dirname, 'windows.ps1'),
          '-List',
        ]);
        const text = output.replace(/^\uFEFF/, '').trim() || '[]';
        const windows = JSON.parse(text);
        send(res, 200, { ok: true, windows: Array.isArray(windows) ? windows : [windows] });
      } catch (error) {
        send(res, 500, { ok: false, error: 'could not read the window list: ' + error.message });
      }
      return;
    }

    if (req.method === 'POST' && url.pathname === '/windows/activate') {
      const raw = await readBody(req);
      let body;
      try {
        body = raw ? JSON.parse(raw) : {};
      } catch {
        send(res, 400, { ok: false, error: 'body must be JSON' });
        return;
      }

      const hwnd = Math.trunc(Number(body.hwnd));
      if (!Number.isFinite(hwnd) || hwnd <= 0) {
        send(res, 400, { ok: false, error: 'hwnd is required' });
        return;
      }

      try {
        await run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          path.join(__dirname, 'windows.ps1'),
          '-Activate',
          String(hwnd),
        ]);
        send(res, 200, { ok: true, hwnd });
      } catch (error) {
        send(res, 500, { ok: false, error: 'could not switch windows: ' + error.message });
      }
      return;
    }

    if (req.method === 'POST' && url.pathname === '/command') {
      const raw = await readBody(req);
      let body;
      try {
        body = raw ? JSON.parse(raw) : {};
      } catch {
        send(res, 400, { ok: false, error: 'body must be JSON' });
        return;
      }

      const action = String(body.action || '');
      const handler = ACTIONS[action];
      if (!handler) {
        send(res, 400, { ok: false, error: `unknown action "${action}"` });
        return;
      }
      if (!IS_WINDOWS) {
        send(res, 501, { ok: false, error: 'this agent only drives Windows PCs' });
        return;
      }

      const started = Date.now();
      try {
        const result = await handler(body.value);
        console.log(`${action} -> ${result} (${Date.now() - started}ms)`);
        send(res, 200, { ok: true, action, result, volume: state.volume, muted: state.muted });
      } catch (err) {
        console.error(`${action} failed: ${err.message}`);
        send(res, 500, { ok: false, action, error: err.message });
      }
      return;
    }

    send(res, 404, { ok: false, error: 'not found' });
  } catch (err) {
    send(res, 500, { ok: false, error: err.message });
  }
});

function lanAddresses() {
  const out = [];
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === 'IPv4' && !net.internal) out.push(net.address);
    }
  }
  return out;
}

server.listen(config.port, '0.0.0.0', () => {
  const ips = lanAddresses();
  console.log('');
  console.log('  Command Center agent v' + AGENT_VERSION);
  console.log('  PC:     ' + os.hostname());
  console.log('  Listen: 0.0.0.0:' + config.port);
  console.log('  Address for the iPhone app:');
  if (ips.length === 0) console.log('    (no LAN address found - are you online?)');
  for (const ip of ips) console.log('    ' + ip + ' : port ' + config.port);
  console.log('');
  console.log('  Pairing token: ' + config.token);
  console.log('  (also stored in agent.config.json)');
  console.log('');
  console.log('  First time only: allow Node.js through Windows Firewall, or');
  console.log('  the phone will not be able to reach this port.');
  console.log('');

  // Warm the input helper: PowerShell plus its native bindings take a couple
  // of seconds to start, and that delay would otherwise land on the first tap.
  if (IS_WINDOWS) {
    try {
      inputHelper();
    } catch (err) {
      console.warn('  input helper did not start: ' + err.message);
    }
  }
});

process.on('SIGINT', () => server.close(() => process.exit(0)));
