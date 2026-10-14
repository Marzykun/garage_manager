const backupService = require('../services/backupService');

// GET /api/backups — schedule info + list of backups on the phone
const getBackups = async (req, res, next) => {
  try {
    res.status(200).json({ success: true, data: backupService.status() });
  } catch (err) {
    next(err);
  }
};

// POST /api/backups — back up now
const createBackup = async (req, res, next) => {
  try {
    const backup = await backupService.createBackup('manual');
    res.status(201).json({ success: true, message: 'Backup created', data: backup });
  } catch (err) {
    next(err);
  }
};

// GET /api/backups/:name/download — the .dump file, to share off the phone
const downloadBackup = async (req, res, next) => {
  try {
    const file = backupService.backupPath(req.params.name);
    if (!file) return res.status(404).json({ success: false, message: 'Backup not found' });
    res.download(file, req.params.name);
  } catch (err) {
    next(err);
  }
};

// POST /api/backups/:name/restore — replace current data with this backup
const restoreBackup = async (req, res, next) => {
  try {
    const result = await backupService.restoreBackup(req.params.name);
    res.status(200).json({ success: true, message: 'Backup restored', data: result });
  } catch (err) {
    next(err);
  }
};

// POST /api/backups/restore-upload � raw .dump bytes in the body
const restoreUpload = async (req, res, next) => {
  try {
    const result = await backupService.restoreUploaded(req.body);
    res.status(200).json({ success: true, message: 'Backup restored', data: result });
  } catch (err) {
    next(err);
  }
};

module.exports = { getBackups, createBackup, downloadBackup, restoreBackup, restoreUpload };
