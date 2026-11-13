#!/usr/bin/env bash
# ============================================================
#  JAZZ SPAIN  -  VPS SHARED BOT installer (proot edition)
#
#  Put install.sh and vps_bot_proot.py in the same folder, then:
#     bash install.sh                          # menu -> asks token + admin id
#     bash install.sh <BOT_TOKEN> <ADMIN_ID>   # token/admin pre-filled
#     bash install.sh <BOT_TOKEN> <ID1,ID2>    # multiple admins
#
#  Optional env vars: PREFIX, BRAND, EXPIRY_DAYS
# ============================================================
set -uo pipefail

INSTALL_DIR="/opt/vpsbot"
SERVICE="vpsbot"
LOG="/tmp/jazz_install.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEBIAN_FRONTEND=noninteractive

ESC=$'\033'
RST="${ESC}[0m"
RB=(196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 21 57 93 129 165 201)
NRB=${#RB[@]}

hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
trap show_cursor EXIT
trap 'show_cursor; printf "\n"; exit 130' INT TERM

# ---------------- big letters ----------------
J=('      _ ' '     | |' '     | |' ' _   | |' '| |__| |' ' \____/ ')
A=('          ' '    /\    ' '   /  \   ' '  / /\ \  ' ' / ____ \ ' '/_/    \_\')
Z=(' ______ ' '|___  / ' '   / /  ' '  / /   ' ' / /__  ' '/_____| ')
S=('  _____ ' ' / ____|' '| (___  ' ' \___ \ ' ' ____) |' '|_____/ ')
P=(' _____  ' '|  __ \ ' '| |__) |' '|  ___/ ' '| |     ' '|_|     ')
I=(' _____ ' '|_   _|' '  | |  ' '  | |  ' ' _| |_ ' '|_____|')
N=(' _   _ ' '| \ | |' '|  \| |' '| . ` |' '| |\  |' '|_| \_|')

ROWS=()
compose() {
  local r L ref line
  for r in 0 1 2 3 4 5; do
    line=""
    for L in "$@"; do ref="${L}[$r]"; line+="${!ref}"; done
    ROWS+=("$line")
  done
}
compose J A Z Z
compose S P A I N
NROWS=${#ROWS[@]}

term_cols() { local c; c=$(tput cols 2>/dev/null || echo 80); echo "${c:-80}"; }
PAD=$(( ($(term_cols) - 40) / 2 )); [ "$PAD" -lt 0 ] && PAD=0
PADSTR="$(printf '%*s' "$PAD" '')"

# one rainbow frame of the banner (colour sweeps across the letters)
draw_banner() { # $1 = frame   $2 = delay between rows
  local f=$1 d=${2:-0} i c line out ch
  for ((i = 0; i < NROWS; i++)); do
    line="${ROWS[$i]}"; out=""
    for ((c = 0; c < ${#line}; c++)); do
      ch="${line:c:1}"
      out+="${ESC}[1;38;5;${RB[$(((f + c + i * 2) % NRB))]}m${ch}"
    done
    printf '%s%s%s\n' "$PADSTR" "$out" "$RST"
    [ "$d" != "0" ] && sleep "$d"
  done
}

header() { # $1 = animation frames   $2 = first-frame row delay
  local f frames=${1:-20}
  printf '\033[2J\033[H'
  for ((f = 0; f < frames; f++)); do
    ((f > 0)) && printf '\033[%dA' "$NROWS"
    if ((f == 0)); then draw_banner 0 "${2:-0}"; else draw_banner "$f" 0; fi
    sleep 0.045
  done
}

typewriter() { # text, colour
  local t="$1" col="${2:-51}" i
  printf '%s' "${PADSTR}${ESC}[1;38;5;${col}m"
  for ((i = 0; i < ${#t}; i++)); do printf '%s' "${t:i:1}"; sleep 0.012; done
  printf '%s\n' "$RST"
}

subtitle() {
  printf '\n'
  typewriter "      ✦  V P S   S H A R E D   B O T   I N S T A L L E R  ✦" 51
  typewriter "                 Powered by JAZZ SPAIN" 213
  printf '\n'
}

menu_box() {
  local c1="${ESC}[1;38;5;45m" c2="${ESC}[1;38;5;46m" c3="${ESC}[1;38;5;196m" cw="${ESC}[1;97m"
  printf '%s%s╔════════════════════════════════════════╗%s\n' "$PADSTR" "$c1" "$RST"
  printf '%s%s║%s  %s[1]%s  VPS SHARED BOT                      %s║%s\n' "$PADSTR" "$c1" "$RST" "$c2" "$cw" "$c1" "$RST"
  printf '%s%s║%s  %s[0]%s  EXIT                                %s║%s\n' "$PADSTR" "$c1" "$RST" "$c3" "$cw" "$c1" "$RST"
  printf '%s%s╚════════════════════════════════════════╝%s\n\n' "$PADSTR" "$c1" "$RST"
}

# ---------------- helpers ----------------
info() { printf '  \033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m[!]\033[0m %s\n' "$*"; }
die()  { show_cursor; printf '\n  \033[31m[x]\033[0m %s\n' "$*" >&2; [ -f "$LOG" ] && { printf '  --- last log lines ---\n' >&2; tail -n 15 "$LOG" >&2; }; exit 1; }

ask_yn() { # returns 0 for yes, 1 for no
  local a
  while true; do
    read -rp "  $1 (Y/N): " a || return 1
    case "$a" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo])     return 1 ;;
      *) warn "Type Y for yes or N for no." ;;
    esac
  done
}

goodbye() {
  local f
  printf '\n'
  hide_cursor
  for ((f = 0; f < 25; f++)); do
    printf '\r%s%s' "$PADSTR" "${ESC}[1;38;5;${RB[$((f % NRB))]}m   ✦ Goodbye from JAZZ SPAIN ✦   ${RST}"
    sleep 0.05
  done
  printf '\n\n'
  show_cursor
}

# ---------------- progress / spinner ----------------
TOTAL=10
DONE=0
progress() {
  local w=34 filled=$((DONE * 34 / TOTAL)) pct=$((DONE * 100 / TOTAL)) bar="" i
  for ((i = 0; i < w; i++)); do
    if ((i < filled)); then bar+="█"; else bar+="░"; fi
  done
  printf '  \033[38;5;%sm[%s]\033[0m %3d%%\n' "${RB[$((DONE * 2 % NRB))]}" "$bar" "$pct"
}

spin() { # pid msg
  local pid=$1 msg=$2 i=0 fr=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  \033[38;5;%sm%s\033[0m %s ' "${RB[$(((i * 2) % NRB))]}" "${fr[$((i % 10))]}" "$msg"
    i=$((i + 1)); sleep 0.1
  done
}

step() { # msg cmd...
  local msg="$1" rc; shift
  "$@" >>"$LOG" 2>&1 &
  local pid=$!
  spin "$pid" "$msg"
  wait "$pid"; rc=$?
  DONE=$((DONE + 1))
  printf '\r\033[K'
  if [ "$rc" -eq 0 ]; then
    printf '  \033[32m✔\033[0m %s\n' "$msg"
  else
    printf '  \033[31m✘\033[0m %s\n' "$msg"
  fi
  progress
  return "$rc"
}

# ---------------- install steps ----------------
s_update()  { apt-get update -qq; }
s_pkgs()    { apt-get install -y -qq python3 python3-venv python3-pip curl ca-certificates tar gzip procps >/dev/null; }
s_proot() {
  if ! command -v proot >/dev/null 2>&1; then
    if ! apt-get install -y -qq proot >/dev/null 2>&1; then
      local arch
      case "$(uname -m)" in
        x86_64) arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) echo "unsupported CPU: $(uname -m)"; return 1 ;;
      esac
      curl -fsSL -o /usr/local/bin/proot \
        "https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-${arch}-static" || return 1
      chmod +x /usr/local/bin/proot
    fi
  fi
  proot --version
}
s_files() {
  mkdir -p "$INSTALL_DIR" /var/lib/vpsbot
  cp "$BOT_SRC" "$INSTALL_DIR/vps_bot.py"
}
s_venv()    { python3 -m venv "$INSTALL_DIR/venv" && "$INSTALL_DIR/venv/bin/pip" install -q --upgrade pip; }
s_pip()     { "$INSTALL_DIR/venv/bin/pip" install -q "discord.py>=2.3" python-dotenv; }
s_env() {
  cat > "$INSTALL_DIR/.env" <<EOF
DISCORD_TOKEN=${TOKEN}
ADMIN_IDS=${ADMINS}
PREFIX=${PREFIX:-2}
BRAND="${BRAND:-JAZZ SPAIN}"
EXPIRY_DAYS=${EXPIRY_DAYS:-30}
DISK_DIR=/var/lib/vpsbot
DB_PATH=${INSTALL_DIR}/vpsbot.db
EOF
  chmod 600 "$INSTALL_DIR/.env"
}
s_runner() {
  cat > "$INSTALL_DIR/run.sh" <<EOF
#!/usr/bin/env bash
cd ${INSTALL_DIR}
while true; do
  ${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/vps_bot.py
  echo "[run.sh] bot exited, restarting in 5s"
  sleep 5
done
EOF
  chmod +x "$INSTALL_DIR/run.sh"

  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    echo systemd > "$INSTALL_DIR/mode"
    cat > "/etc/systemd/system/${SERVICE}.service" <<EOF
[Unit]
Description=JAZZ SPAIN VPS Shared Bot (proot)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/vps_bot.py
Restart=always
RestartSec=5
# keep the VPS processes alive when the bot is restarted
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE"
  else
    echo nohup > "$INSTALL_DIR/mode"
  fi
}
s_helper() {
  cat > /usr/local/bin/vpsbot <<'EOF'
#!/usr/bin/env bash
D=/opt/vpsbot
MODE=$(cat "$D/mode" 2>/dev/null || echo nohup)
running() { pgrep -f "$D/vps_bot.py" >/dev/null 2>&1; }
case "${1:-status}" in
  start)
    if [ "$MODE" = systemd ]; then systemctl start vpsbot
    elif running; then echo "already running"
    else setsid nohup bash "$D/run.sh" >>"$D/bot.log" 2>&1 < /dev/null & echo $! > "$D/bot.pid"; fi ;;
  stop)
    if [ "$MODE" = systemd ]; then systemctl stop vpsbot
    else pkill -f "$D/run.sh" 2>/dev/null; pkill -f "$D/vps_bot.py" 2>/dev/null; rm -f "$D/bot.pid"; fi ;;
  restart) "$0" stop; sleep 2; "$0" start ;;
  status)
    if [ "$MODE" = systemd ]; then systemctl status vpsbot --no-pager
    elif running; then echo "bot is RUNNING"; else echo "bot is STOPPED"; exit 1; fi ;;
  logs)
    if [ "$MODE" = systemd ]; then journalctl -u vpsbot -f
    else tail -n 50 -f "$D/bot.log"; fi ;;
  *) echo "usage: vpsbot start|stop|restart|status|logs" ;;
esac
EOF
  chmod +x /usr/local/bin/vpsbot
}
s_start() { /usr/local/bin/vpsbot start; }

# ---------------- main installer ----------------
run_install() {
  [ "$(id -u)" -eq 0 ] || die "Run as root:  sudo bash install.sh"
  command -v apt-get >/dev/null 2>&1 || die "This installer supports Debian/Ubuntu (apt) only."

  BOT_SRC=""
  for f in "$SCRIPT_DIR/vps_bot_proot.py" "$SCRIPT_DIR/vps_bot.py"; do
    [ -f "$f" ] && { BOT_SRC="$f"; break; }
  done
  [ -n "$BOT_SRC" ] || die "vps_bot_proot.py not found next to install.sh ($SCRIPT_DIR)"

  printf '\n'
  if [ -z "$TOKEN" ]; then
    read -rsp "  Discord bot token (hidden): " TOKEN; printf '\n'
  fi
  if [ -z "$ADMINS" ]; then
    read -rp "  Admin Discord user ID (comma-separated for many): " ADMINS
  fi
  ADMINS="${ADMINS// /}"
  [ -n "$TOKEN" ] || die "Bot token cannot be empty."
  [[ "$ADMINS" =~ ^[0-9]+(,[0-9]+)*$ ]] || die "Admin ID must be numbers only (e.g. 123456789012345678)."

  : > "$LOG"
  printf '\n'
  hide_cursor
  DONE=0
  step "Updating package lists"        s_update  || die "apt update failed"
  step "Installing Python & tools"     s_pkgs    || die "package install failed"
  step "Installing proot"              s_proot   || die "could not install proot"
  step "Copying bot files"             s_files   || die "copy failed"
  step "Creating Python environment"   s_venv    || die "venv failed"
  step "Installing discord.py"         s_pip     || die "pip install failed"
  step "Writing configuration (.env)"  s_env     || die ".env failed"
  step "Creating service & runner"     s_runner  || die "service setup failed"
  step "Installing 'vpsbot' command"   s_helper  || die "helper install failed"
  step "Starting the bot"              s_start   || die "could not start the bot"
  show_cursor

  sleep 4
  printf '\n'
  if /usr/local/bin/vpsbot status >/dev/null 2>&1; then
    local f
    for ((f = 0; f < 30; f++)); do
      printf '\r%s%s' "$PADSTR" "${ESC}[1;38;5;${RB[$((f % NRB))]}m   ★ JAZZ SPAIN VPS SHARED BOT IS RUNNING! ★   ${RST}"
      sleep 0.05
    done
    printf '\n'
  else
    warn "Bot did not stay running. Check logs:  vpsbot logs   (or tail -n 50 $INSTALL_DIR/bot.log)"
  fi

  cat <<EOF

  Done.  Useful commands:
    vpsbot status        # is it running?
    vpsbot logs          # live logs
    vpsbot restart       # restart the bot
    vpsbot stop|start
    nano ${INSTALL_DIR}/.env   # edit config, then: vpsbot restart

  In Discord, type:  ${PREFIX:-2}help
  Note: if this container itself restarts, run  vpsbot start  once.

EOF
}

# ---------------- entry ----------------
TOKEN="${1:-${DISCORD_TOKEN:-}}"
ADMINS="${2:-${ADMIN_IDS:-}}"

hide_cursor
header 50 0.04
subtitle
show_cursor
menu_box

while true; do
  read -rp "  Select option » " CH || { goodbye; exit 0; }
  case "$CH" in
    1)
      if ask_yn "Start VPS SHARED BOT installation?"; then
        run_install
        exit 0
      else
        warn "Cancelled - back to the menu."
        printf '\n'
        menu_box
      fi
      ;;
    0)
      goodbye
      exit 0
      ;;
    *)
      warn "Press 1 to install or 0 to exit."
      ;;
  esac
done
