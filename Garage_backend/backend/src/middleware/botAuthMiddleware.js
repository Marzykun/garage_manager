// Shared-secret auth for machine-to-machine calls from the WhatsApp bot.
const botAuth = (req, res, next) => {
  const key = req.headers['x-api-key'];

  if (!key || key !== process.env.BOT_API_KEY) {
    return res.status(401).json({ success: false, message: 'Invalid or missing bot API key' });
  }

  next();
};

module.exports = botAuth;
