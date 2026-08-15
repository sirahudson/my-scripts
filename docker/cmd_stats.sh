#!/bin/sh
# dockerhost-stats.sh (v4 - interactive + secure state)
# Monitoring CPU %, Memory (RSS), Network I/O, dan Block I/O container Docker
# langsung dari host via /proc - tidak bergantung cgroup.
#
# Requirement: procps (ps), util-linux (nsenter)
#   apk add procps util-linux
#
# Pemakaian:
#   ./dockerhost-stats.sh                 -> mode pilih interaktif
#   ./dockerhost-stats.sh all             -> semua container, sekali jalan
#   ./dockerhost-stats.sh all --watch     -> semua container, live refresh 2s
#   ./dockerhost-stats.sh all --watch 5   -> semua container, live refresh 5s
#   ./dockerhost-stats.sh <nama>          -> container tertentu, sekali jalan
#   ./dockerhost-stats.sh <nama> --watch  -> container tertentu, live refresh

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
  ./dockerhost-stats.sh                    (mode pilih interaktif)
  ./dockerhost-stats.sh all [--watch [N]]
  ./dockerhost-stats.sh <container> [--watch [N]]

Examples:
  ./dockerhost-stats.sh all
  ./dockerhost-stats.sh all --watch 5
  ./dockerhost-stats.sh myapp-container --watch
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
  echo "$names" | while IFS= read -r name; do
    printf "  ${GREEN}%2d)${NC} %s\n" "$i" "$name"
    i=$((i+1))
  done > /tmp/.dhs_menu.$$ 2>/dev/null
  cat /tmp/.dhs_menu.$$
  rm -f /tmp/.dhs_menu.$$

  total=$(echo "$names" | wc -l)
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

TARGET="${1:-}"
shift || true

# ---- Mode interaktif kalau tanpa argumen ----
if [ -z "$TARGET" ]; then
  pilih_container
  if [ -n "$WATCH_SEC" ]; then
    exec watch -n "$WATCH_SEC" -t "$0" "$TARGET"
  fi
else
  # ---- Mode manual: cek --watch ----
  if [ "${1:-}" = "--watch" ]; then
    WATCH_INTERVAL="${2:-2}"
    exec watch -n "$WATCH_INTERVAL" -t "$0" "$TARGET"
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

if [ -f "$STATE_FILE" ]; then
  . "$STATE_FILE" 2>/dev/null
fi

prev_total=${prev_total_cpu:-$total_now}
elapsed=$((now_ts - ${prev_ts:-now_ts}))
[ "$elapsed" -le 0 ] && elapsed=1
total_delta=$((total_now - prev_total))

printf "\n${WHITE}%-22s %-8s %-14s %-18s %-18s${NC}\n" "CONTAINER" "CPU %" "MEM (RSS)" "NET I/O (rx/tx)" "BLOCK I/O (r/w /${elapsed}s)"
printf "${DIM}%-22s %-8s %-14s %-18s %-18s${NC}\n" "----------------------" "--------" "--------------" "------------------" "------------------"

TMP_STATE="/tmp/.dhs_state.$$"
: > "$TMP_STATE"

echo "$pairs" | while IFS=':' read -r name pid; do
  [ -z "$pid" ] && continue

  if [ ! -f "/proc/$pid/stat" ]; then
    printf "%-22s %-8s %-14s %-18s %-18s\n" "$name" "N/A" "N/A" "N/A" "N/A"
    continue
  fi

  cpu_now=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null)
  cpu_now=${cpu_now:-0}
  varname="prev_cpu_$pid"
  eval "cpu_prev=\${$varname:-$cpu_now}"
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

  rxvar="prev_rx_$pid"; txvar="prev_tx_$pid"
  eval "rx_prev=\${$rxvar:-$rx_now}"
  eval "tx_prev=\${$txvar:-$tx_now}"
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

  rbvar="prev_rb_$pid"; wbvar="prev_wb_$pid"
  eval "rb_prev=\${$rbvar:-$rb_now}"
  eval "wb_prev=\${$wbvar:-$wb_now}"
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
{
  echo "prev_ts=$now_ts"
  echo "prev_total_cpu=$total_now"
  cat "$TMP_STATE"
} > "$STATE_FILE"
rm -f "$TMP_STATE"