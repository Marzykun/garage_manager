require('dotenv').config();
const app = require('./src/app');

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Garage server running on port ${PORT}`);
});

// Prevent random crashes from unhandled errors
process.on('uncaughtException', (err) => {
  console.error('[uncaughtException]', err.message, err.stack);
});

process.on('unhandledRejection', (reason) => {
  console.error('[unhandledRejection]', reason);
});