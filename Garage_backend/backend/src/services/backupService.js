const { execFile } = require('child_process');
const fs   = require('fs');
const os   = require('os');
const path = require('path');

// Database backups: compressed pg_dump files (-Fc), typically a few hundred KB
// for a garage's data. One is made automatically every BACKUP_INTERVAL_DAYS
// (default 30) and the newest BACKUP_KEEP (default 12) are kept — a year of
// monthly backups in a few MB.
//
// Location: the phone's shared storage when Termux has storage permission
// (`termux-setup-storage`), so backups survive Termux being uninstalled or its
// data cleared. Otherwise falls back to ~/garage-backups inside Termux, which
// still protects against a corrupted/deleted database but not a Termux wipe.

const INTERVAL_DAYS = Number(process.env.BACKUP_INTERVAL_DAYS) || 30;
const KEEP          = Number(process.env.BACKUP_KEEP) || 12;
const CHECK_EVERY_MS = 6 * 60 * 60 * 1000; // re-check whether one is due every 6h

const SHARED_DIR   = '/storage/emulated/0/GarageManager/backups';
const INTERNAL_DIR = path.join(os.homedir(), 'garage-backups');

const NAME_RE = /^garage-backup-\d{4}-\d{2}-\d{2}-\d{6}(-auto|-manual|-pre-restore|-uploaded)?\.dump$/;

// pg_dump/pg_restore are on PATH in Termux; PG_BIN lets a dev machine point at them.
const bin = (name) => (process.env.PG_BIN ? path.join(process.env.PG_BIN, name) : name);

const pgEnv = () => ({
  ...process.env,
  PGHOST:     process.env.DB_HOST || 'localhost',
  PGPORT:     String(process.env.DB_PORT || 5432),
  PGDATABASE: process.env.DB_NAME,
  PGUSER:     process.env.DB_USER,
  PGPASSWORD: process.env.DB_PASSWORD || '',
});

const run = (cmd, args) =>
  new Promise((resolve, reject) => {
    execFile(bin(cmd), args, { env: pgEnv(), maxBuffer: 16 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        err.message = `${cmd} failed: ${(stderr || err.message).toString().trim()}`;
        return reject(err);
      }
      resolve(stdout);
    });
  });

const isWritable = (dir) => {
  try {
    fs.mkdirSync(dir, { recursive: true });
    const probe = path.join(dir, '.write-test');
    fs.writeFileSync(probe, 'ok');
    fs.unlinkSync(probe);
    return true;
  } catch (_) {
    return false;
  }
};

// Re-evaluated each time so granting storage permission later takes effect
// without a restart.
const backupDir = () => {
  if (process.env.BACKUP_DIR) {
    fs.mkdirSync(process.env.BACKUP_DIR, { recursive: true });
    return { dir: process.env.BACKUP_DIR, shared: false };
  }
  // Only on Android (the storage root must already exist — never create it).
  if (fs.existsSync('/storage/emulated/0') && isWritable(SHARED_DIR)) {
    return { dir: SHARED_DIR, shared: true };
  }
  fs.mkdirSync(INTERNAL_DIR, { recursive: true });
  return { dir: INTERNAL_DIR, shared: false };
};

const stamp = (d = new Date()) => {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
};

const listBackups = () => {
  const { dir, shared } = backupDir();
  const files = fs.readdirSync(dir)
    .filter((f) => NAME_RE.test(f))
    .map((name) => {
      const st = fs.statSync(path.join(dir, name));
      const kind = (name.match(/-(auto|manual|pre-restore|uploaded)\.dump$/) || [])[1] || 'manual';
      return { name, size: st.size, created_at: st.mtime.toISOString(), kind };
    })
    .sort((a, b) => b.created_at.localeCompare(a.created_at));
  return { dir, shared, backups: files };
};

const prune = () => {
  const { dir, backups } = listBackups();
  // Safety copies taken before a restore don't count against the limit for
  // regular backups, but only the 3 newest of them are kept.
  const regular = backups.filter((b) => b.kind !== 'pre-restore');
  const safety  = backups.filter((b) => b.kind === 'pre-restore');
  [...regular.slice(KEEP), ...safety.slice(3)].forEach((b) => {
    try { fs.unlinkSync(path.join(dir, b.name)); } catch (_) { /* already gone */ }
  });
};

const createBackup = async (kind = 'manual') => {
  const { dir } = backupDir();
  const name = `garage-backup-${stamp()}-${kind}.dump`;
  const file = path.join(dir, name);
  const tmp  = `${file}.part`;
  try {
    // Write to a temp name first so a crash mid-dump never leaves a
    // half-written file that looks like a valid backup.
    await run('pg_dump', ['-Fc', '-Z', '9', '--no-owner', '-f', tmp]);
    fs.renameSync(tmp, file);
  } catch (err) {
    try { fs.unlinkSync(tmp); } catch (_) { /* nothing to clean */ }
    throw err;
  }
  prune();
  const st = fs.statSync(file);
  console.log(`[backup] ${name} (${Math.round(st.size / 1024)} KB) → ${dir}`);
  return { name, size: st.size, created_at: st.mtime.toISOString(), kind };
};

const backupPath = (name) => {
  if (!NAME_RE.test(name)) return null; // also blocks path traversal
  const file = path.join(backupDir().dir, name);
  return fs.existsSync(file) ? file : null;
};

// Replaces the current database with the backup's contents. A safety backup of
// the current data is taken first, and the restore runs in one transaction so
// a failure leaves the database untouched.
const restoreFile = async (file, label) => {
  const safety = await createBackup('pre-restore');
  await run('pg_restore', ['--clean', '--if-exists', '--no-owner', '--single-transaction', '-d', pgEnv().PGDATABASE, file]);
  console.log(`[backup] restored ${label} (safety copy: ${safety.name})`);
  return { restored: label, safety_backup: safety.name };
};

const restoreBackup = async (name) => {
  const file = backupPath(name);
  if (!file) {
    const err = new Error('Backup not found');
    err.status = 404;
    throw err;
  }
  return restoreFile(file, name);
};

// Restore from a dump uploaded by the app (e.g. received over WhatsApp).
const restoreUploaded = async (buf) => {
  if (!Buffer.isBuffer(buf) || buf.length < 5 || buf.toString('latin1', 0, 5) !== 'PGDMP') {
    const err = new Error('This is not a Garage Manager backup file.');
    err.status = 400;
    throw err;
  }
  const name = `garage-backup-${stamp()}-uploaded.dump`;
  const file = path.join(backupDir().dir, name);
  fs.writeFileSync(file, buf);
  try {
    return await restoreFile(file, name);
  } catch (err) {
    try { fs.unlinkSync(file); } catch (_) { /* nothing to clean */ }
    throw err;
  }
};

const status = () => {
  const { dir, shared, backups } = listBackups();
  const last = backups.find((b) => b.kind !== 'pre-restore' && b.kind !== 'uploaded');
  const next = last
    ? new Date(new Date(last.created_at).getTime() + INTERVAL_DAYS * 86400000).toISOString()
    : null;
  return { dir, shared, interval_days: INTERVAL_DAYS, keep: KEEP, last_backup: last || null, next_due: next, backups };
};

const runIfDue = async () => {
  try {
    const { last_backup } = status();
    const age = last_backup ? Date.now() - new Date(last_backup.created_at).getTime() : Infinity;
    if (age >= INTERVAL_DAYS * 86400000) await createBackup('auto');
  } catch (err) {
    console.error('[backup] automatic backup FAILED:', err.message);
  }
};

const startScheduler = () => {
  runIfDue();
  setInterval(runIfDue, CHECK_EVERY_MS).unref();
};

module.exports = { createBackup, listBackups, restoreBackup, restoreUploaded, backupPath, status, startScheduler };
