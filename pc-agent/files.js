'use strict';

/*
 * File bridge.
 *
 * The iPhone app lists, downloads and uploads files inside a small set of
 * shared roots. Nothing outside those roots is reachable: a request names a
 * root label plus a relative path, and every resolved path is checked against
 * its root after normalisation. Deletes move into `<root>/_trash/` instead of
 * destroying anything.
 */

const fs = require('node:fs');
const path = require('node:path');

const MAX_UPLOAD = 512 * 1024 * 1024;
const MAX_LIST = 500;
const TRASH = '_trash';

const MIME = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.heic': 'image/heic',
  '.mp4': 'video/mp4',
  '.mov': 'video/quicktime',
  '.txt': 'text/plain; charset=utf-8',
  '.json': 'application/json',
  '.pdf': 'application/pdf',
  '.zip': 'application/zip',
};

class FileError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function sanitiseName(name) {
  const value = String(name || '');
  if (!value || value.length > 128) throw new FileError(400, 'a file name is required');
  if (/[\\/:*?"<>|]/.test(value) || /[\u0000-\u001f]/.test(value)) {
    throw new FileError(400, 'that file name is not allowed');
  }
  if (value === '.' || value === '..') throw new FileError(400, 'that file name is not allowed');
  return value;
}

function createFileService(roots) {
  if (!Array.isArray(roots) || roots.length === 0) throw new Error('at least one shared root is required');

  const table = new Map();
  for (const entry of roots) {
    if (!entry || typeof entry.label !== 'string' || typeof entry.path !== 'string') {
      throw new Error('each root needs a label and a path');
    }
    table.set(entry.label, path.resolve(entry.path));
  }

  const defaultLabel = [...table.keys()][0];

  function rootFor(label) {
    const key = label ? String(label) : defaultLabel;
    const root = table.get(key);
    if (!root) throw new FileError(400, `unknown shared root "${key}"`);
    return { label: key, root };
  }

  function resolveInside(label, requested) {
    const { label: name, root } = rootFor(label);
    const raw = String(requested || '').replace(/\\/g, '/');
    if (raw.includes('\u0000')) throw new FileError(400, 'invalid path');
    if (raw.split('/').some((segment) => segment === '..')) {
      throw new FileError(400, 'paths may not climb out of the shared root');
    }
    const relative = path.posix.normalize(raw).replace(/^\/+/, '');
    const absolute = path.resolve(root, relative);
    if (absolute !== root && !absolute.startsWith(root + path.sep)) {
      throw new FileError(400, 'path escapes the shared root');
    }
    return { root, absolute };
  }

  function listRoots() {
    return [...table.entries()].map(([label, root]) => ({
      label,
      path: root,
      exists: fs.existsSync(root),
    }));
  }

  function list(label, requested) {
    const { absolute } = resolveInside(label, requested);
    let stat;
    try {
      stat = fs.statSync(absolute);
    } catch {
      throw new FileError(404, 'no such folder');
    }
    if (!stat.isDirectory()) throw new FileError(400, 'not a folder');

    const entries = [];
    for (const item of fs.readdirSync(absolute, { withFileTypes: true })) {
      if (entries.length >= MAX_LIST) break;
      let size = 0;
      let modified = null;
      try {
        const detail = fs.statSync(path.join(absolute, item.name));
        size = detail.size;
        modified = detail.mtime.toISOString();
      } catch {
        continue;
      }
      entries.push({
        name: item.name,
        directory: item.isDirectory(),
        size,
        modified,
      });
    }
    entries.sort((a, b) => {
      if (a.directory !== b.directory) return a.directory ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    const relative = path.relative(rootFor(label).root, absolute).replace(/\\/g, '/');
    return {
      root: label || defaultLabel,
      path: relative,
      truncated: entries.length >= MAX_LIST,
      entries,
    };
  }

  function open(label, requested) {
    const { absolute } = resolveInside(label, requested);
    let stat;
    try {
      stat = fs.statSync(absolute);
    } catch {
      throw new FileError(404, 'no such file');
    }
    if (!stat.isFile()) throw new FileError(400, 'not a file');
    return {
      absolute,
      name: path.basename(absolute),
      size: stat.size,
      type: MIME[path.extname(absolute).toLowerCase()] || 'application/octet-stream',
    };
  }

  function folder(label, requested) {
    const { root, absolute } = resolveInside(label, requested);
    if (absolute === root) throw new FileError(400, 'that folder already exists');
    fs.mkdirSync(absolute, { recursive: true });
    return { path: path.relative(root, absolute).replace(/\\/g, '/') };
  }

  function rename(label, requested, name) {
    const { root, absolute } = resolveInside(label, requested);
    if (absolute === root) throw new FileError(400, 'cannot rename the shared root itself');
    let stat;
    try {
      stat = fs.statSync(absolute);
    } catch {
      throw new FileError(404, 'no such file');
    }
    const safe = sanitiseName(name);
    const target = path.join(path.dirname(absolute), safe);
    const relative = path.relative(root, absolute).replace(/\\/g, '/');
    if (target === absolute) return { name: safe, path: relative, directory: stat.isDirectory() };
    if (!target.startsWith(root + path.sep)) throw new FileError(400, 'path escapes the shared root');
    if (fs.existsSync(target)) throw new FileError(409, 'something with that name already exists');
    fs.renameSync(absolute, target);
    return {
      name: safe,
      path: path.relative(root, target).replace(/\\/g, '/'),
      directory: stat.isDirectory(),
    };
  }

  function upload(label, requested, name, stream) {
    const { root, absolute: directory } = resolveInside(label, requested);
    const safe = sanitiseName(name);
    fs.mkdirSync(directory, { recursive: true });
    const target = path.join(directory, safe);
    if (!target.startsWith(root + path.sep)) throw new FileError(400, 'path escapes the shared root');

    return new Promise((resolve, reject) => {
      const partial = target + '.part';
      const out = fs.createWriteStream(partial);
      let written = 0;
      let settled = false;

      const fail = (error) => {
        if (settled) return;
        settled = true;
        out.destroy();
        fs.rm(partial, { force: true }, () => reject(error));
        stream.destroy();
      };

      stream.on('data', (chunk) => {
        written += chunk.length;
        if (written > MAX_UPLOAD) fail(new FileError(413, 'file is larger than the 512 MB limit'));
      });
      stream.on('aborted', () => fail(new FileError(400, 'upload was interrupted')));
      stream.on('error', fail);
      out.on('error', fail);
      out.on('finish', () => {
        if (settled) return;
        settled = true;
        fs.rename(partial, target, (error) => {
          if (error) reject(error);
          else resolve({ name: safe, size: written });
        });
      });
      stream.pipe(out);
    });
  }

  function trash(label, requested) {
    const { root, absolute } = resolveInside(label, requested);
    if (absolute === root) throw new FileError(400, 'cannot remove the shared root itself');
    let stat;
    try {
      stat = fs.statSync(absolute);
    } catch {
      throw new FileError(404, 'no such file');
    }
    if (!stat.isFile() && !stat.isDirectory()) throw new FileError(400, 'not a file or folder');

    const bin = path.join(root, TRASH);
    fs.mkdirSync(bin, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const destination = path.join(bin, `${stamp}-${path.basename(absolute)}`);
    fs.renameSync(absolute, destination);
    return { moved: path.relative(root, destination).replace(/\\/g, '/') };
  }

  return { roots: listRoots, list, open, folder, rename, upload, trash, defaultLabel, MAX_UPLOAD };
}

module.exports = { createFileService, FileError, MAX_UPLOAD, sanitiseName };
