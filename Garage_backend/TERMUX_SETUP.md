# Garage Manager — On-Device Deployment (Termux)

Runs the **entire stack on one dedicated Android phone** — no cloud, no PC:

- **PostgreSQL** (database) — inside Termux
- **Node.js backend** (`server.js`) — inside Termux, listening on `localhost:3000`
- **Flutter app** — installed as a normal APK, talks to `http://127.0.0.1:3000`

WhatsApp bot and Razorpay are **not** part of this install (on hold).

---

## 1. Install the apps (use F-Droid, NOT the Play Store)

The Play Store versions of Termux are outdated and **Termux:Boot won't work** from them.
Install [F-Droid](https://f-droid.org), then from F-Droid install:

- **Termux**
- **Termux:Boot**  (needed for auto-start on power-on)

Open **Termux:Boot once** after installing so Android grants it boot permission.

## 2. Install packages (in Termux)

```sh
pkg update -y && pkg upgrade -y
pkg install -y nodejs postgresql git termux-api
```

## 3. Get the project onto the phone

```sh
cd ~
git clone https://github.com/Marzykun/garage_manager.git
cd garage_manager/Garage_backend/backend
npm install
```

## 4. Initialize PostgreSQL

```sh
# Create the database cluster (first time only)
initdb $PREFIX/var/lib/postgresql

# Start Postgres
pg_ctl -D $PREFIX/var/lib/postgresql -l $PREFIX/var/lib/postgresql/postgres.log start

# Create the 'postgres' role the app expects, plus the database
createuser --superuser postgres
createdb garage_db

# Load the full schema (tables + seed logins)
psql -U postgres -d garage_db -f ~/garage_manager/Garage_backend/backend/schema.sql
```

> Termux Postgres uses `trust` auth on localhost by default, so the password in
> `.env` isn't actually checked — but the `postgres` role must exist (created above).

## 5. Confirm `.env`

`Garage_backend/backend/.env` is already set for local Postgres — no cloud values:

```
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=garage_db
DB_USER=postgres
DB_PASSWORD=garage123
JWT_SECRET=garage_secret_key_2025
```

> 🔐 On the customer's phone, set `JWT_SECRET` to a unique random string
> (e.g. output of `openssl rand -hex 32` in Termux) instead of the dev value.
> The Razorpay/bot keys can be omitted entirely — payments are disabled unless
> keys are present.

> ⚠️ `.env` is git-ignored, so `git clone` will **not** create it. Copy it onto
> the phone manually (or recreate it with the values above) before first run.

## 6. Test run

```sh
cd ~/garage_manager/Garage_backend/backend
node server.js
```

Expected output:

```
Garage server running on port 3000
Database connected successfully!
```

Leave it running and open the **Garage Manager app** on the same phone — it should
log in and load. Then `Ctrl+C` to stop; step 7 makes it start automatically.

**Logins:** Mechanic → leave username blank, password `garage123`.
Owner → username `owner`, password `owner123`. (Change these in Settings after install.)

## 7. Auto-start on power-on (Termux:Boot)

```sh
mkdir -p ~/.termux/boot
cp ~/garage_manager/Garage_backend/deploy/start-garage.sh ~/.termux/boot/
chmod +x ~/.termux/boot/start-garage.sh
```

The script (`deploy/start-garage.sh`) grabs a wake-lock, starts Postgres, waits
for it, then starts the backend — writing logs to `~/garage-backend.log`.

## 8. Stop Android from killing it (important on a real phone)

In Android **Settings**:

- Battery → disable **battery optimization** for **Termux** and **Termux:Boot**
- If the phone is Xiaomi/Oppo/Vivo/Realme/Samsung: enable **Autostart** for Termux
  and lock it in the recent-apps view so the OS won't swipe-kill it.

## 9. Reboot to verify

Restart the phone. Wait ~30s, then open the app — it should work with nothing
started by hand. If not, check `cat ~/garage-backend.log`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| App shows connection error | Is the server up? `cat ~/garage-backend.log`. Restart: `sh ~/.termux/boot/start-garage.sh` |
| `Database connection FAILED` | Postgres not running → `pg_ctl -D $PREFIX/var/lib/postgresql start` |
| `role "postgres" does not exist` | Re-run `createuser --superuser postgres` |
| Server dies when screen turns off | Battery optimization still on (step 8) |
| Nothing starts after reboot | Open the **Termux:Boot** app once; confirm the script is in `~/.termux/boot/` and is executable |
