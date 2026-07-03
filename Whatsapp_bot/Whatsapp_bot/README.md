# Garage WhatsApp Bot — Twilio Sandbox Version
### Sundar Auto Care, Musiri

---

## File Structure
```
garage_bot/
├── index.js           ← START HERE — runs everything
├── messageHandler.js  ← all conversation logic
├── flowManager.js     ← tracks customer chat state
├── apiClient.js       ← calls backend API
├── twilioClient.js    ← sends WhatsApp via Twilio
├── notifier.js        ← receives admin updates, notifies customer
├── mockApi.js         ← fake backend (no real backend needed yet)
├── .env               ← YOUR CREDENTIALS GO HERE
└── README.md
```

---

## One-Time Setup (do this once)

### 1. Install Node.js
Download from https://nodejs.org (LTS version) → install → restart laptop

### 2. Create Free Twilio Account
- Go to https://twilio.com → Sign up free
- No credit card needed

### 3. Get Twilio Sandbox Credentials
- Login to Twilio → Console → Messaging → Try it out → Send a WhatsApp message
- You'll see:
  - Account SID  (starts with AC...)
  - Auth Token
  - Sandbox number: +1 415 523 8886
  - Your join code: e.g. "join silver-tiger"

### 4. Fill in .env file
Open `.env` in VS Code and replace:
```
TWILIO_ACCOUNT_SID=ACxxxxxxx   ← paste your Account SID
TWILIO_AUTH_TOKEN=your_token   ← paste your Auth Token
```
Leave everything else as is.

### 5. Activate Sandbox on Your Phone
- Open WhatsApp on your phone
- Message this number: +1 415 523 8886
- Send: join <your-code>   (Twilio gives you the word)
- You'll get: "You are connected to the sandbox ✅"

### 6. Install Dependencies
Open VS Code terminal (Ctrl + `) and run:
```bash
npm install
```

---

## Every Time You Want to Test

### Step 1 — Start the bot
```bash
node index.js
```
You'll see all 3 servers start up.

### Step 2 — Expose your localhost using ngrok
Open a SECOND terminal (click + in VS Code terminal):
```bash
npx ngrok http 3001
```
You'll see something like:
```
Forwarding  https://abc123.ngrok.io → http://localhost:3001
```
Copy that https URL.

### Step 3 — Set Webhook in Twilio
- Go to Twilio Console → Messaging → Try it out → WhatsApp Sandbox
- Find "When a message comes in" field
- Paste: https://abc123.ngrok.io/webhook
- Make sure method is set to HTTP POST
- Click Save

### Step 4 — Test It!
From your phone, WhatsApp the Twilio sandbox number (+1 415 523 8886):
- Send: Hi
- You get the service menu back!

Try full flow:
1. Send Hi → get menu
2. Send 1 → bot asks for vehicle number
3. Send TN45AB1234 → booking confirmed!

---

## Test Notifications (simulate admin pressing buttons)

Open a third terminal and run:

### Simulate "Booking Confirmed":
```bash
curl -X POST http://localhost:3003/notify \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"919876543210\",\"vehicleNumber\":\"TN45AB1234\",\"service\":\"Car Washing\",\"type\":\"confirmed\"}"
```

### Simulate "Work Started":
```bash
curl -X POST http://localhost:3003/notify \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"919876543210\",\"vehicleNumber\":\"TN45AB1234\",\"service\":\"Car Washing\",\"type\":\"in_progress\"}"
```

### Simulate "Vehicle Ready":
```bash
curl -X POST http://localhost:3003/notify \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"919876543210\",\"vehicleNumber\":\"TN45AB1234\",\"service\":\"Car Washing\",\"type\":\"completed\"}"
```
Replace 919876543210 with your actual number (91 + your 10 digit number, no spaces).

---

## Check what's stored (fake database)
Open browser → http://localhost:3002/mock/all
You'll see all bookings in JSON format.

---

## Ports Summary
| What | Port |
|---|---|
| Webhook (Twilio sends messages here) | 3001 |
| Notifier (admin app calls this) | 3003 |
| Mock Backend API | 3002 |

---

## When Real Backend is Ready
Open `.env` → change:
```
BACKEND_URL=http://localhost:3002
```
to the real backend URL. Nothing else changes.

---

## Troubleshooting
| Problem | Fix |
|---|---|
| Bot not replying | Check ngrok is running and webhook URL is set in Twilio |
| "Invalid credentials" error | Double check TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN in .env |
| ngrok URL expired | ngrok free tier gives new URL each restart — update webhook URL in Twilio again |
| Phone not receiving | Make sure you sent the join code to activate sandbox |
| Port already in use | Change BOT_PORT in .env |
