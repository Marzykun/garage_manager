#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot startup script — launches PostgreSQL + the Garage backend
# automatically when the phone powers on.
#
# Install:
#   mkdir -p ~/.termux/boot
#   cp ~/garage_manager/Garage_backend/deploy/start-garage.sh ~/.termux/boot/
#   chmod +x ~/.termux/boot/start-garage.sh
# (and open the "Termux:Boot" app once so Android allows boot execution)

# Keep the CPU awake so Android doesn't sleep/kill the server when the screen is off.
termux-wake-lock

# Adjust this if you placed the project somewhere other than ~/garage_manager
BACKEND_DIR="$HOME/garage_manager/Garage_backend/backend"
PGDATA="$PREFIX/var/lib/postgresql"

# Start PostgreSQL (no-op if already running)
pg_ctl -D "$PGDATA" -l "$PGDATA/postgres.log" -w start

# Wait until Postgres is actually accepting connections (up to ~30s)
for i in $(seq 1 30); do
  pg_isready -q && break
  sleep 1
done

# Start the backend in the foreground (this holds the wake-lock).
# Logs go to a file so you can inspect them after an unattended reboot.
cd "$BACKEND_DIR" || exit 1
node server.js >> "$HOME/garage-backend.log" 2>&1
