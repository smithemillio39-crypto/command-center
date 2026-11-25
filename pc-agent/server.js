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
const { execFile } = require('node:child_process');

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

/* ------------------------------------------------------------------ server */

const config = loadConfig();

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');

  try {
    if (req.method === 'GET' && url.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(
        '<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">' +
          '<body style="font:16px -apple-system,system-ui;background:#0b0c10;color:#eee;padding:24px">' +
          '<h1 style="font-size:20px">Command Center agent</h1>' +
          `<p>Running on <b>${os.hostname()}</b> - port ${config.port}</p>` +
          '<p style="color:#9aa">Waiting for the iPhone app. Pair with the token in agent.config.json.</p>' +
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
      });
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
});

process.on('SIGINT', () => server.close(() => process.exit(0)));
