#!/bin/sh
# cmd-stats.sh (interactive + secure state)
# Monitoring CPU %, Memory (RSS), Network I/O, dan Block I/O container Docker
# langsung dari host via /proc - tidak bergantung cgroup.
#
# Requirement: procps (ps; watch for --watch), coreutils (nproc), util-linux (nsenter)
#   Debian/Ubuntu: apt install procps coreutils util-linux
#   Alpine:        apk add procps coreutils util-linux
#
# Pemakaian:
#   ./cmd-stats.sh                 -> mode pilih interaktif
#   ./cmd-stats.sh all             -> semua container, sekali jalan
#   ./cmd-stats.sh all --watch     -> semua container, live refresh 2s
#   ./cmd-stats.sh all --watch 5   -> semua container, live refresh 5s
#   ./cmd-stats.sh <nama>          -> container tertentu, sekali jalan
#   ./cmd-stats.sh <nama> --watch  -> container tertentu, live refresh

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RED='\033[1;31m'
DIM='\033[2m'
NC='\033[0m'

# state file per-user, permission ketat (fix security issue sourcing dari /tmp)
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE_FILE="${STATE_DIR}/.dockerhost_stats_state.$(id -u)"
umask 077

if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  :
else
  GREEN='' YELLOW='' CYAN='' WHITE='' RED='' DIM='' NC=''
fi

state_value() {
  [ -r "$STATE_FILE" ] || return 0
  awk -F= -v key="$1" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE"
}

human_bytes() {
  b=$1
  if [ "$b" -ge 1073741824 ] 2>/dev/null; then
    awk -v n="$b" 'BEGIN{printf "%.2fGB", n/1073741824}'
  elif [ "$b" -ge 1048576 ] 2>/dev/null; then
    awk -v n="$b" 'BEGIN{printf "%.2fMB", n/1048576}'
  elif [ "$b" -ge 1024 ] 2>/dev/null; then
    awk -v n="$b" 'BEGIN{printf "%.2fKB", n/1024}'
  else
    echo "${b:-0}B"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  ./cmd-stats.sh                    (mode pilih interaktif)
  ./cmd-stats.sh all [--watch [N]]
  ./cmd-stats.sh <container> [--watch [N]]

Examples:
  ./cmd-stats.sh all
  ./cmd-stats.sh all --watch 5
  ./cmd-stats.sh myapp-container --watch
EOF
}

# pilih_container -> isi variabel global TARGET ("all" atau nama container spesifik)
pilih_container() {
  names=$(docker ps --format '{{.Names}}' 2>/dev/null)

  if [ -z "$names" ]; then
    printf "${RED}✘ Tidak ada container yang jalan.${NC}\n"
    exit 1
  fi

  printf "${CYAN}Pilih container untuk dimonitor:${NC}\n"
  printf "  ${GREEN} 0)${NC} ${WHITE}all${NC}      ${DIM}— monitor semua container${NC}\n"

  i=1
  for name in $names; do
    printf "  ${GREEN}%2d)${NC} %s\n" "$i" "$name"
    i=$((i + 1))
  done

  total=$((i - 1))
  keluar=$((total + 1))
  printf "  ${YELLOW}%2d)${NC} Keluar\n" "$keluar"

  printf "${DIM}#? ${NC}"
  read -r pilihan

  case "$pilihan" in
    0) TARGET="all" ;;
    "$keluar"|"")
      printf "${YELLOW}Dibatalkan.${NC}\n"
      exit 0
      ;;
    *[!0-9]*)
      printf "${RED}Input tidak valid.${NC}\n"
      exit 1
      ;;
    *)
      TARGET=$(echo "$names" | sed -n "${pilihan}p")
      if [ -z "$TARGET" ]; then
        printf "${RED}Pilihan tidak valid.${NC}\n"
        exit 1
      fi
      ;;
  esac

  printf "${DIM}Watch mode? interval detik (kosong = sekali jalan):${NC} "
  read -r WATCH_SEC
}

# ---- Argumen ----
if [ "${1:-}" = "info" ] || [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

command -v docker >/dev/null 2>&1 || { printf "${RED}✘ docker tidak ditemukan di PATH.${NC}\n" >&2; exit 1; }
command -v nproc >/dev/null 2>&1 || { printf "${RED}✘ nproc tidak ditemukan (install coreutils).${NC}\n" >&2; exit 1; }
command -v nsenter >/dev/null 2>&1 || { printf "${RED}✘ nsenter tidak ditemukan (install util-linux).${NC}" >&2; exit 1; }
ps --ppid "$$" -o rss= >/dev/null 2>&1 || {
  printf "${RED}✘ ps tidak mendukung --ppid; install procps (Debian/Ubuntu: apt install procps; Alpine: apk add procps).${NC}\n" >&2
  exit 1
}

require_watch() {
  command -v watch >/dev/null 2>&1 || {
    printf "${RED}✘ watch tidak ditemukan; install procps (Debian/Ubuntu: apt install procps; Alpine: apk add procps).${NC}\n" >&2
    exit 1
  }
}

TARGET="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

# ---- Mode interaktif kalau tanpa argumen ----
if [ -z "$TARGET" ]; then
  pilih_container
  if [ -n "$WATCH_SEC" ]; then
    case "$WATCH_SEC" in
      *[!0-9]*|'') printf "${RED}Interval harus berupa angka positif.${NC}\n"; exit 1 ;;
      0) printf "${RED}Interval harus lebih besar dari 0.${NC}\n"; exit 1 ;;
    esac
    require_watch
    exec watch -n "$WATCH_SEC" -t "$0" "$TARGET"
  fi
else
  # ---- Mode manual: cek --watch ----
  if [ "${1:-}" = "--watch" ]; then
    WATCH_INTERVAL="${2:-2}"
    case "$WATCH_INTERVAL" in
      *[!0-9]*|'') printf "${RED}Interval harus berupa angka positif.${NC}\n"; exit 1 ;;
      0) printf "${RED}Interval harus lebih besar dari 0.${NC}\n"; exit 1 ;;
    esac
    [ "$#" -le 2 ] || { printf "${RED}Penggunaan: $0 <container|all> --watch [detik]${NC}\n"; exit 1; }
    require_watch
    exec watch -n "$WATCH_INTERVAL" -t "$0" "$TARGET"
  elif [ "$#" -gt 0 ]; then
    printf "${RED}Argumen tidak dikenal: %s${NC}\n" "$1"
    usage >&2
    exit 1
  fi
fi

ncpu=$(nproc)

# --- Ambil Name + PID, filter berdasarkan TARGET ---
if [ "$TARGET" = "all" ]; then
  pairs=$(docker inspect -f '{{.Name}}:{{.State.Pid}}' $(docker ps -q) 2>/dev/null | sed 's#^/##')
else
  container_id=$(docker ps -q -f "name=^${TARGET}\$")
  if [ -z "$container_id" ]; then
    printf "${RED}✘ Container '%s' tidak ditemukan atau tidak jalan.${NC}\n" "$TARGET"
    exit 1
  fi
  pairs=$(docker inspect -f '{{.Name}}:{{.State.Pid}}' "$container_id" 2>/dev/null | sed 's#^/##')
fi

if [ -z "$pairs" ]; then
  printf "${YELLOW}Tidak ada container yang jalan.${NC}\n"
  exit 0
fi

now_ts=$(date +%s)
total_now=$(awk '/^cpu /{for(i=2;i<=8;i++)sum+=$i; print sum}' /proc/stat)

prev_total=$(state_value prev_total_cpu)
prev_ts=$(state_value prev_ts)
case "$prev_total" in ''|*[!0-9]*) prev_total=$total_now ;; esac
case "$prev_ts" in ''|*[!0-9]*) prev_ts=$now_ts ;; esac
elapsed=$((now_ts - prev_ts))
[ "$elapsed" -le 0 ] && elapsed=1
total_delta=$((total_now - prev_total))

printf "\n${WHITE}%-22s %-8s %-14s %-18s %-18s${NC}\n" "CONTAINER" "CPU %" "MEM (RSS)" "NET I/O (rx/tx)" "BLOCK I/O (r/w /${elapsed}s)"
printf "${DIM}%-22s %-8s %-14s %-18s %-18s${NC}\n" "----------------------" "--------" "--------------" "------------------" "------------------"

if [ ! -d "$STATE_DIR" ]; then
  printf "${RED}✘ Direktori state tidak tersedia: %s${NC}\n" "$STATE_DIR" >&2
  exit 1
fi

TMP_STATE=$(mktemp "${STATE_DIR}/.dhs_state.XXXXXX") || {
  printf "${RED}✘ Tidak dapat membuat file state sementara di %s.${NC}\n" "$STATE_DIR" >&2
  exit 1
}
TMP_NEXT=""
cleanup() {
  rm -f "$TMP_STATE"
  if [ -n "$TMP_NEXT" ]; then
    rm -f "$TMP_NEXT"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

echo "$pairs" | while IFS=':' read -r name pid; do
  [ -z "$pid" ] && continue

  if [ ! -f "/proc/$pid/stat" ]; then
    printf "%-22s %-8s %-14s %-18s %-18s\n" "$name" "N/A" "N/A" "N/A" "N/A"
    continue
  fi

  cpu_now=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null)
  cpu_now=${cpu_now:-0}
  cpu_prev=$(state_value "prev_cpu_$pid")
  case "$cpu_prev" in ''|*[!0-9]*) cpu_prev=$cpu_now ;; esac
  cpu_delta=$((cpu_now - cpu_prev))
  [ "$cpu_delta" -lt 0 ] && cpu_delta=0

  if [ "$total_delta" -gt 0 ]; then
    cpu_pct=$(awk -v cd="$cpu_delta" -v td="$total_delta" -v n="$ncpu" \
      'BEGIN{printf "%.2f", (cd/td)*n*100}')
  else
    cpu_pct="0.00"
  fi

  main_rss=$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null)
  main_rss=${main_rss:-0}
  children_rss=$(ps --ppid "$pid" -o rss= 2>/dev/null | awk '{sum+=$1} END{print sum+0}')
  total_rss=$((main_rss + children_rss))

  if [ "$total_rss" -ge 1048576 ]; then
    mem_display=$(awk -v k="$total_rss" 'BEGIN{printf "%.2fGiB", k/1048576}')
  else
    mem_display=$(awk -v k="$total_rss" 'BEGIN{printf "%.2fMiB", k/1024}')
  fi

  net_line=$(nsenter -t "$pid" -n cat /proc/net/dev 2>/dev/null | grep -v "lo:" | grep ":" | head -1)
  rx_now=0; tx_now=0
  if [ -n "$net_line" ]; then
    rx_now=$(echo "$net_line" | awk -F':' '{print $2}' | awk '{print $1}')
    tx_now=$(echo "$net_line" | awk -F':' '{print $2}' | awk '{print $9}')
  fi
  rx_now=${rx_now:-0}; tx_now=${tx_now:-0}

  rx_prev=$(state_value "prev_rx_$pid")
  tx_prev=$(state_value "prev_tx_$pid")
  case "$rx_prev" in ''|*[!0-9]*) rx_prev=$rx_now ;; esac
  case "$tx_prev" in ''|*[!0-9]*) tx_prev=$tx_now ;; esac
  rx_delta=$((rx_now - rx_prev))
  tx_delta=$((tx_now - tx_prev))
  [ "$rx_delta" -lt 0 ] && rx_delta=0
  [ "$tx_delta" -lt 0 ] && tx_delta=0
  net_display="$(human_bytes $rx_delta) / $(human_bytes $tx_delta)"

  rb_now=0; wb_now=0
  if [ -f "/proc/$pid/io" ]; then
    rb_now=$(awk -F': ' '/^read_bytes/{print $2}' "/proc/$pid/io" 2>/dev/null)
    wb_now=$(awk -F': ' '/^write_bytes/{print $2}' "/proc/$pid/io" 2>/dev/null)
  fi
  for cpid in $(ps --ppid "$pid" -o pid= 2>/dev/null); do
    [ -f "/proc/$cpid/io" ] || continue
    crb=$(awk -F': ' '/^read_bytes/{print $2}' "/proc/$cpid/io" 2>/dev/null)
    cwb=$(awk -F': ' '/^write_bytes/{print $2}' "/proc/$cpid/io" 2>/dev/null)
    rb_now=$((rb_now + ${crb:-0}))
    wb_now=$((wb_now + ${cwb:-0}))
  done
  rb_now=${rb_now:-0}; wb_now=${wb_now:-0}

  rb_prev=$(state_value "prev_rb_$pid")
  wb_prev=$(state_value "prev_wb_$pid")
  case "$rb_prev" in ''|*[!0-9]*) rb_prev=$rb_now ;; esac
  case "$wb_prev" in ''|*[!0-9]*) wb_prev=$wb_now ;; esac
  rb_delta=$((rb_now - rb_prev))
  wb_delta=$((wb_now - wb_prev))
  [ "$rb_delta" -lt 0 ] && rb_delta=0
  [ "$wb_delta" -lt 0 ] && wb_delta=0
  io_display="$(human_bytes $rb_delta) / $(human_bytes $wb_delta)"

  printf "%-22s %-8s %-14s %-18s %-18s\n" "$name" "${cpu_pct}%" "$mem_display" "$net_display" "$io_display"

  echo "prev_cpu_$pid=$cpu_now
prev_rb_$pid=$rb_now
prev_wb_$pid=$wb_now
prev_rx_$pid=$rx_now
prev_tx_$pid=$tx_now" >> "$TMP_STATE"
done

# rebuild state file dari nol tiap run -> mencegah numpuk pid lama (fix cleanup issue)
TMP_NEXT=$(mktemp "${STATE_DIR}/.dhs_state_next.XXXXXX") || {
  printf "${RED}✘ Tidak dapat membuat file state sementara di %s.${NC}\n" "$STATE_DIR" >&2
  exit 1
}
{
  echo "prev_ts=$now_ts"
  echo "prev_total_cpu=$total_now"
  cat "$TMP_STATE"
} > "$TMP_NEXT"
mv -f "$TMP_NEXT" "$STATE_FILE"