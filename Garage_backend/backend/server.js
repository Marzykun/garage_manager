require('dotenv').config();
const app = require('./src/app');
const migrate = require('./src/config/migrate');
const backupService = require('./src/services/backupService');

const PORT = process.env.PORT || 3000;
// Loopback-only by default: the app runs on the same phone, so nothing on the
// Wi-Fi network should be able to reach the API. Set HOST=0.0.0.0 in .env for
// LAN dev (PC backend + phone app).
const HOST = process.env.HOST || '127.0.0.1';

// Apply schema upgrades before serving; a failure is logged but doesn't stop
// the server, so older features keep working even if a migration can't run.
migrate()
  .then(() => console.log('Schema up to date.'))
  .catch((err) => console.error('Schema migration FAILED:', err.message))
  .finally(() => {
    app.listen(PORT, HOST, () => {
      console.log(`Garage server running on ${HOST}:${PORT}`);
    });
    // Monthly automatic database backup (checks on start, then every 6h)
    backupService.startScheduler();
  });

// Prevent random crashes from unhandled errors
process.on('uncaughtException', (err) => {
  console.error('[uncaughtException]', err.message, err.stack);
});

process.on('unhandledRejection', (reason) => {
  console.error('[unhandledRejection]', reason);
});