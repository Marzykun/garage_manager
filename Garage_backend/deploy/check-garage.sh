#!/bin/sh
# READ-ONLY health check for the Garage Manager phone setup (Termux).
# Run:  sh ~/garage_manager/Garage_backend/deploy/check-garage.sh
# Changes nothing: no start/stop/delete/write anywhere.

REPO="$HOME/garage_manager"
BE="$REPO/Garage_backend/backend"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PGDATA="$PREFIX/var/lib/postgresql"
LOG="$HOME/garage-backend.log"
SHARED=/storage/emulated/0/GarageManager/backups
INTERNAL="$HOME/garage-backups"
BAD=0

if [ -t 1 ]; then G=$(printf '\033[32m'); Y=$(printf '\033[33m'); R=$(printf '\033[31m'); N=$(printf '\033[0m'); else G=; Y=; R=; N=; fi
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 5"

ok()   { printf '%s[ OK ]%s %s\n' "$G" "$N" "$1"; }
info() { printf '[INFO] %s\n' "$1"; }
warn() { printf '%s[WARN]%s %s\n       FIX: %s\n' "$Y" "$N" "$1" "$2"; BAD=$((BAD+1)); }
fail() { printf '%s[FAIL]%s %s\n       FIX: %s\n' "$R" "$N" "$1" "$2"; BAD=$((BAD+1)); }
have() { command -v "$1" >/dev/null 2>&1; }
psqlq() { PGCONNECT_TIMEOUT=4 $TO psql -h 127.0.0.1 -U postgres -d "${1}" -tAc "$2" 2>/dev/null; }

echo "== GARAGE CHECK  $(date '+%d-%b %H:%M') =="

# 1. packages
miss=""
for c in node npm psql pg_ctl git curl; do have $c || miss="$miss $c"; done
if [ -z "$miss" ]; then ok "Programs installed"; else fail "Missing:$miss" "run: pkg install nodejs postgresql git curl"; fi

# 2. repo
if [ -d "$REPO/.git" ]; then
  c=$(git -C "$REPO" log -1 --format=%h 2>/dev/null)
  ok "App code found (version $c)"
  # no fetch: only compares with what was last downloaded
  b=$(git -C "$REPO" rev-list HEAD..origin/main --count 2>/dev/null)
  if [ -n "$b" ] && [ "$b" -gt 0 ] 2>/dev/null; then info "$b newer update(s) known - see UPDATE_INSTRUCTIONS.txt"; fi
else fail "App folder ~/garage_manager missing" "re-do SETUP_INSTRUCTIONS.txt (git clone)"; fi
if [ -d "$BE/node_modules" ]; then ok "Backend libraries installed"; else fail "Backend node_modules missing" "cd ~/garage_manager/Garage_backend/backend && npm install"; fi

# 3. .env (values of secrets are never printed)
E="$BE/.env"
if [ -f "$E" ]; then
  miss=""; for k in PORT DB_HOST DB_NAME DB_USER; do grep -q "^$k=" "$E" || miss="$miss $k"; done
  if [ -n "$miss" ]; then fail ".env lacks:$miss" "copy the .env from the setup instructions and fill the missing lines"
  elif grep -q '^DB_HOST=localhost' "$E"; then warn ".env has DB_HOST=localhost" "change it to DB_HOST=127.0.0.1 (fixes ENOTFOUND errors)"
  else ok ".env settings present"; fi
else fail ".env file missing in backend folder" "create it as in SETUP_INSTRUCTIONS.txt"; fi

# 4. Postgres
if have pg_isready && pg_isready -h 127.0.0.1 -q 2>/dev/null; then ok "Postgres is running"; else fail "Postgres not running" "restart the phone, wait 1 min, run this check again"; fi
if [ "$(psqlq postgres 'select 1')" = 1 ]; then
  ok "Can log in to Postgres"
  [ "$(psqlq postgres "select 1 from pg_roles where rolname='postgres'")" = 1 ] || fail "Role postgres missing" "follow RESET_DATABASE_INSTRUCTIONS.txt"
  if [ "$(psqlq postgres "select 1 from pg_database where datname='garage_db'")" = 1 ]; then
    t=$(psqlq garage_db "select count(*) from information_schema.tables where table_schema='public'")
    ok "Database garage_db has $t tables"
    jc=$(psqlq garage_db "select count(*) from job_cards"); cu=$(psqlq garage_db "select count(*) from customers"); iv=$(psqlq garage_db "select count(*) from invoices")
    if [ -n "$jc" ]; then info "Data: jobs=$jc customers=$cu invoices=$iv"; else warn "Tables empty/not created" "start the server once (it builds tables) then re-check"; fi
  else fail "Database garage_db missing" "follow RESET_DATABASE_INSTRUCTIONS.txt"; fi
else fail "Cannot log in to Postgres (user postgres)" "if role/password error: RESET_DATABASE_INSTRUCTIONS.txt"; fi
[ -d "$PGDATA-old" ] && info "Old folder postgresql-old exists (from a reset, keep)"

# 5. server
if have curl; then
  code=$($TO curl -s -o /dev/null -m 4 -w '%{http_code}' http://127.0.0.1:3000/ 2>/dev/null)
  case "$code" in ""|000) fail "Server not answering on port 3000" "open Termux, run: sh ~/.termux/boot/start-garage.sh";; *) ok "Server answers (HTTP $code)";; esac
fi
if have pgrep && pgrep -f 'node server.js' >/dev/null 2>&1; then ok "Server process running"; else fail "Server process not running" "restart the phone, wait 1 min"; fi
if [ -f "$LOG" ]; then
  e=$(grep -E 'ENOTFOUND|FATAL|Error' "$LOG" | tail -3 | cut -c1-60)
  [ -n "$e" ] && warn "Log has errors (old ones stay in log):" "check lines below" && echo "$e" | sed 's/^/       > /'
fi

# 6. Termux setup
grep -q '^allow-external-apps *= *true' "$HOME/.termux/termux.properties" 2>/dev/null && ok "allow-external-apps=true" || fail "allow-external-apps not set" "add that line to ~/.termux/termux.properties, then restart Termux"
B="$HOME/.termux/boot/start-garage.sh"
if [ -x "$B" ]; then ok "Boot script installed"; elif [ -f "$B" ]; then fail "Boot script not executable" "chmod +x ~/.termux/boot/start-garage.sh"; else fail "Boot script missing" "see SETUP_INSTRUCTIONS.txt (copy start-garage.sh to ~/.termux/boot)"; fi
if have pm; then
  if pm list packages 2>/dev/null | grep -q com.termux.boot; then ok "Termux:Boot app installed"; else info "Termux:Boot app not seen (install it, open once)"; fi
else info "Termux:Boot check not possible"; fi
if ls /storage/emulated/0 >/dev/null 2>&1 || [ -d "$HOME/storage" ]; then ok "Storage permission OK"; else fail "No storage permission" "run: termux-setup-storage and tap Allow"; fi
BD=""; [ -d "$SHARED" ] && BD="$SHARED"; [ -z "$BD" ] && [ -d "$INTERNAL" ] && BD="$INTERNAL"
if [ -n "$BD" ]; then
  f=$(ls -t "$BD" 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    m=$(stat -c %Y "$BD/$f" 2>/dev/null); now=$(date +%s)
    d=$(( (now - ${m:-$now}) / 86400 ))
    if [ "$d" -gt 35 ]; then warn "Last backup is $d days old ($f)" "open the app > Backup now, or check server is running"; else ok "Backup $f ($d d old)"; fi
  else warn "Backup folder is empty" "open the app and make a backup"; fi
else warn "No backup folder yet" "run termux-setup-storage, restart the server"; fi
kb=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$kb" ]; then mb=$((kb/1024)); if [ "$mb" -lt 500 ]; then warn "Only $mb MB free" "free up phone storage"; else ok "Free space $mb MB"; fi; fi
info "Reminder: set Termux battery to Unrestricted (Android settings)"

echo "-------------------------------"
if [ "$BAD" -eq 0 ]; then echo "SUMMARY: All good"; else echo "SUMMARY: $BAD problems - send a photo of this screen"; fi
exit 0
