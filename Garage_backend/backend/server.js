require('dotenv').config();
const app = require('./src/app');

const PORT = process.env.PORT || 3000;
// Loopback-only by default: the app runs on the same phone, so nothing on the
// Wi-Fi network should be able to reach the API. Set HOST=0.0.0.0 in .env for
// LAN dev (PC backend + phone app).
const HOST = process.env.HOST || '127.0.0.1';

app.listen(PORT, HOST, () => {
  console.log(`Garage server running on ${HOST}:${PORT}`);
});

// Prevent random crashes from unhandled errors
process.on('uncaughtException', (err) => {
  console.error('[uncaughtException]', err.message, err.stack);
});

process.on('unhandledRejection', (reason) => {
  console.error('[unhandledRejection]', reason);
});