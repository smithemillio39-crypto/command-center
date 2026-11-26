'use strict';

/*
 * End-to-end check of the file bridge. Boots the real agent against a throwaway
 * shared root and exercises upload, download, traversal rejection and trash.
 *
 *   node test-files.js
 */

const { spawn } = require('node:child_process');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 8910;
const TOKEN = 'filetest';
const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-files-'));
const BASE = `http://127.0.0.1:${PORT}`;
const results = [];

function check(name, ok, detail = '') {
  results.push({ name, ok: Boolean(ok), detail });
}

async function call(pathname, options = {}) {
  const response = await fetch(BASE + pathname, options);
  const type = response.headers.get('content-type') || '';
  if (type.includes('application/json')) {
    return { status: response.status, body: await response.json() };
  }
  return { status: response.status, body: Buffer.from(await response.arrayBuffer()) };
}

async function main() {
  fs.writeFileSync(path.join(ROOT, 'hello.txt'), 'first file\n');

  const server = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
    env: {
      ...process.env,
      AGENT_PORT: String(PORT),
      AGENT_TOKEN: TOKEN,
      AGENT_FILE_ROOTS: `share=${ROOT}`,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let log = '';
  server.stdout.on('data', (chunk) => { log += chunk; });
  server.stderr.on('data', (chunk) => { log += chunk; });

  try {
    let ready = false;
    for (let attempt = 0; attempt < 60 && !ready; attempt += 1) {
      try {
        const probe = await fetch(`${BASE}/status?token=${TOKEN}`);
        ready = probe.ok;
      } catch {
        /* not listening yet */
      }
      if (!ready) await new Promise((resolve) => setTimeout(resolve, 100));
    }
    check('agent started', ready);
    if (!ready) return;

    const status = await call(`/status?token=${TOKEN}`);
    check('status advertises files', status.body.files === true);
    check('status lists the share root',
      Array.isArray(status.body.fileRoots) && status.body.fileRoots.includes('share'));

    check('missing token is refused',
      (await call('/files')).status === 401);

    const listing = await call(`/files?token=${TOKEN}`);
    check('listing shows the seeded file',
      listing.status === 200 && listing.body.entries.some((entry) => entry.name === 'hello.txt'),
      JSON.stringify(listing.body.entries || listing.body));

    const payload = crypto.randomBytes(96 * 1024);
    const upload = await call(`/files/upload?token=${TOKEN}&path=inbox&name=from-phone.jpg`, {
      method: 'POST',
      body: payload,
    });
    check('upload accepted', upload.status === 200 && upload.body.size === payload.length,
      JSON.stringify(upload.body));

    const download = await call(`/files/raw?token=${TOKEN}&path=inbox/from-phone.jpg`);
    check('download is byte identical',
      download.status === 200 && Buffer.compare(download.body, payload) === 0);

    check('download round trip hash',
      crypto.createHash('sha256').update(download.body).digest('hex') ===
      crypto.createHash('sha256').update(payload).digest('hex'));

    const traversal = await call(`/files?token=${TOKEN}&path=${encodeURIComponent('../../Windows')}`);
    check('traversal rejected', traversal.status === 400, JSON.stringify(traversal.body));

    const absolute = await call(`/files?token=${TOKEN}&path=${encodeURIComponent('C:/Windows/win.ini')}`);
    check('absolute path rejected instead of escaping', absolute.status === 400,
      JSON.stringify(absolute.body));

    const unknownRoot = await call(`/files?token=${TOKEN}&root=nope`);
    check('unknown root rejected', unknownRoot.status === 400);

    const badName = await call(`/files/upload?token=${TOKEN}&path=inbox&name=${encodeURIComponent('../evil.txt')}`, {
      method: 'POST',
      body: Buffer.from('nope'),
    });
    check('path-like upload name rejected', badName.status === 400, JSON.stringify(badName.body));

    const folder = await call(`/files/folder?token=${TOKEN}&path=archive/2026`, { method: 'POST' });
    check('folder created',
      folder.status === 200 && fs.existsSync(path.join(ROOT, 'archive', '2026')));

    // --- rename ------------------------------------------------------------
    const renamed = await call(
      `/files/rename?token=${TOKEN}&path=inbox/from-phone.jpg&name=${encodeURIComponent('phone-photo.jpg')}`,
      { method: 'POST' });
    check('file renamed',
      renamed.status === 200 && fs.existsSync(path.join(ROOT, 'inbox', 'phone-photo.jpg')),
      JSON.stringify(renamed.body));
    check('old name is gone', !fs.existsSync(path.join(ROOT, 'inbox', 'from-phone.jpg')));

    fs.writeFileSync(path.join(ROOT, 'inbox', 'keep.bin'), 'other');
    const clash = await call(
      `/files/rename?token=${TOKEN}&path=inbox/phone-photo.jpg&name=keep.bin`,
      { method: 'POST' });
    check('rename refuses to overwrite', clash.status === 409, JSON.stringify(clash.body));
    check('both files survive a refused rename',
      fs.existsSync(path.join(ROOT, 'inbox', 'phone-photo.jpg')) &&
      fs.existsSync(path.join(ROOT, 'inbox', 'keep.bin')));

    const folderRenamed = await call(
      `/files/rename?token=${TOKEN}&path=archive/2026&name=2027`, { method: 'POST' });
    check('folder renamed',
      folderRenamed.status === 200 && fs.existsSync(path.join(ROOT, 'archive', '2027')),
      JSON.stringify(folderRenamed.body));

    const rootRename = await call(`/files/rename?token=${TOKEN}&path=&name=nope`, { method: 'POST' });
    check('renaming the root is refused', rootRename.status === 400, JSON.stringify(rootRename.body));

    const escapingRename = await call(
      `/files/rename?token=${TOKEN}&path=${encodeURIComponent('../outside')}&name=x.txt`, { method: 'POST' });
    check('rename cannot climb out of the root', escapingRename.status === 400,
      JSON.stringify(escapingRename.body));

    const slashName = await call(
      `/files/rename?token=${TOKEN}&path=inbox/phone-photo.jpg&name=${encodeURIComponent('../evil.txt')}`,
      { method: 'POST' });
    check('path-like rename target rejected', slashName.status === 400, JSON.stringify(slashName.body));

    const trashed = await call(`/files/trash?token=${TOKEN}&path=inbox/phone-photo.jpg`, { method: 'POST' });
    check('file moved to trash', trashed.status === 200 && !fs.existsSync(path.join(ROOT, 'inbox', 'phone-photo.jpg')),
      JSON.stringify(trashed.body));
    check('trash keeps the file',
      trashed.status === 200 && fs.existsSync(path.join(ROOT, trashed.body.moved)));

    const after = await call(`/files?token=${TOKEN}&path=inbox`);
    check('trashed file is gone from the listing',
      after.status === 200 && !after.body.entries.some((entry) => entry.name === 'phone-photo.jpg'));

    check('no partial files left behind',
      !fs.readdirSync(path.join(ROOT, 'inbox'), { withFileTypes: true }).some((entry) => entry.name.endsWith('.part')));
  } finally {
    server.kill();
    await new Promise((resolve) => setTimeout(resolve, 300));
    fs.rmSync(ROOT, { recursive: true, force: true });
  }
}

main()
  .catch((error) => check('unexpected failure', false, error.message))
  .finally(() => {
    const passed = results.filter((result) => result.ok).length;
    for (const result of results) {
      console.log(`${result.ok ? 'PASS' : 'FAIL'}  ${result.name}${result.detail && !result.ok ? '  -> ' + result.detail : ''}`);
    }
    console.log(`\n${passed}/${results.length} checks passed`);
    process.exitCode = passed === results.length ? 0 : 1;
  });
