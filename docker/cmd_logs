#!/usr/bin/env sh
# logs — tail logs dari container service (auto-detect dari folder aktif/pwd)
set -e

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

# ---- Deteksi folder aktif saat script dijalankan ----
CURRENT_DIR="$(pwd)"

# ---- Deteksi nama project dari folder aktif ----
if [ -n "${COMPOSE_PROJECT_OVERRIDE:-}" ]; then
  PROJECT="$COMPOSE_PROJECT_OVERRIDE"
else
  RAW_NAME="$(basename "$CURRENT_DIR")"
  PROJECT="$(printf '%s' "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g')"
fi

# ---- Deteksi file compose: cari .yml di folder aktif ----
if [ -n "${COMPOSE_FILE_OVERRIDE:-}" ]; then
  FILE="$COMPOSE_FILE_OVERRIDE"
else
  FILE="$(find "$CURRENT_DIR" -maxdepth 1 -name "*.yml" | sed "s|^$CURRENT_DIR/||" | sort | head -n 1)"

  if [ -z "$FILE" ]; then
    printf "${RED}✘ Tidak ditemukan file .yml di ${CURRENT_DIR}${NC}\n" >&2
    exit 1
  fi
fi

COMPOSE="docker compose -f ${FILE} -p ${PROJECT}"

load_services() {
  SERVICES=$($COMPOSE config --services 2>/dev/null)
  if [ -z "$SERVICES" ]; then
    printf "${RED}✘ Tidak ada service ditemukan. Cek %s${NC}\n" "$FILE" >&2
    exit 1
  fi
}

usage() {
  load_services
  cat <<EOF
Usage:
  ./cmd_logs [info|help|-h|--help]
  ./cmd_logs <service> [args...]
  ./cmd_logs                    (mode pilih interaktif)

Terdeteksi otomatis:
  Project : ${PROJECT}
  File    : ${FILE}
  Dir     : ${CURRENT_DIR}

Override manual (opsional):
  COMPOSE_PROJECT_OVERRIDE=nama ./cmd_logs
  COMPOSE_FILE_OVERRIDE=file.yml ./cmd_logs

Services:
$(echo "$SERVICES" | sed 's/^/  /')

Examples:
  ./cmd_logs nginx
  ./cmd_logs app --tail 50
  ./cmd_logs db -f
EOF
}

pilih_service() {
  load_services

  printf "${CYAN}Project: ${WHITE}${PROJECT}${NC} ${DIM}(${FILE})${NC}\n"
  printf "${CYAN}Pilih service (logs):${NC}\n"

  i=1
  for svc in $SERVICES; do
    printf "  ${GREEN}%2d)${NC} %s\n" "$i" "$svc"
    i=$((i+1))
  done
  total=$i
  printf "  ${YELLOW}%2d)${NC} Keluar\n" "$total"

  printf "${DIM}#? ${NC}"
  read -r pilihan

  if [ -z "$pilihan" ] || [ "$pilihan" = "$total" ]; then
    printf "${YELLOW}Dibatalkan.${NC}\n"
    exit 1
  fi

  case "$pilihan" in
    ''|*[!0-9]*)
      printf "${RED}Input tidak valid.${NC}\n"
      exit 1
      ;;
  esac

  i=1
  for svc in $SERVICES; do
    [ "$i" = "$pilihan" ] && SERVICE="$svc" && break
    i=$((i+1))
  done

  if [ -z "$SERVICE" ]; then
    printf "${RED}Pilihan tidak valid.${NC}\n"
    exit 1
  fi

  printf "${DIM}Tail berapa baris (kosong = follow -f):${NC} "
  read -r TAIL_N

  printf "${GREEN}✔${NC} Menampilkan log ${WHITE}%s${NC}\n" "$SERVICE"
}

# ---- Argumen info/help ----
if [ "${1:-}" = "info" ] || [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

SERVICE="${1:-}"
shift || true

# ---- Mode interaktif kalau tanpa argumen ----
if [ -z "$SERVICE" ]; then
  pilih_service
  if [ -n "$TAIL_N" ]; then
    set -- --tail "$TAIL_N"
  else
    set -- -f
  fi
fi

# ---- Parsing argumen (mode manual) ----
ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -n)
      ARGS="${ARGS} --tail ${2}"
      shift 2
      ;;
    *)
      ARGS="${ARGS} $1"
      shift
      ;;
  esac
done

# shellcheck disable=SC2086
$COMPOSE logs $ARGS "$SERVICE"