#!/usr/bin/env sh
# run — wrapper Docker Compose modular (auto-detect dari folder aktif/pwd)
set -e

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RED='\033[1;31m'
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

usage() {
  cat <<EOF
Usage:
  ./cmd_run [info|help|-h|--help]
  ./cmd_run <command> [args...]
  ./cmd_run                    (mode pilih interaktif)

Terdeteksi otomatis:
  Project : ${PROJECT}
  File    : ${FILE}
  Dir     : ${CURRENT_DIR}

Override manual (opsional):
  COMPOSE_PROJECT_OVERRIDE=nama ./cmd_run up
  COMPOSE_FILE_OVERRIDE=file.yml ./cmd_run up

Commands:
  up              start containers (dengan --build)
  down            stop & hapus containers
  restart         restart containers
  logs            tail logs (follow)
  ps              list containers
  build           build images
  stop            stop containers
  start           start containers
  exec <svc> cmd  jalankan command di dalam service
  run <svc> cmd   jalankan one-off command
  <lainnya>       diteruskan langsung ke docker compose

Examples:
  ./cmd_run up
  ./cmd_run down
  ./cmd_run logs nginx
  ./cmd_run exec app sh
EOF
}

# do_run <command> [args...]
do_run() {
  cmd="$1"
  shift || true

  printf "${CYAN}➜ %s${NC} ${DIM}(project: ${PROJECT}, file: ${FILE})${NC}\n" "$cmd"

  case "$cmd" in
    up)
      $COMPOSE up -d --build "$@"
      ;;
    down)
      $COMPOSE down "$@"
      ;;
    restart)
      $COMPOSE restart "$@"
      ;;
    logs)
      $COMPOSE logs -f "$@"
      ;;
    ps)
      $COMPOSE ps "$@"
      ;;
    build)
      $COMPOSE build "$@"
      ;;
    stop)
      $COMPOSE stop "$@"
      ;;
    start)
      $COMPOSE start "$@"
      ;;
    exec)
      if [ $# -lt 1 ]; then
        printf "${RED}Usage: ./cmd_run exec <service> [command]${NC}\n" >&2
        exit 1
      fi
      $COMPOSE exec "$@"
      ;;
    run)
      if [ $# -lt 1 ]; then
        printf "${RED}Usage: ./cmd_run run <service> [command]${NC}\n" >&2
        exit 1
      fi
      $COMPOSE run "$@"
      ;;
    *)
      $COMPOSE "$cmd" "$@"
      ;;
  esac

  printf "${GREEN}✔ Selesai${NC}\n"
}

pilih_command() {
  printf "${CYAN}Project: ${WHITE}${PROJECT}${NC} ${DIM}(${FILE})${NC}\n"
  printf "${CYAN}Pilih perintah:${NC}\n"
  printf "  ${GREEN} 1)${NC} up        ${DIM}— start containers (build)${NC}\n"
  printf "  ${GREEN} 2)${NC} down      ${DIM}— stop & hapus containers${NC}\n"
  printf "  ${GREEN} 3)${NC} restart   ${DIM}— restart containers${NC}\n"
  printf "  ${GREEN} 4)${NC} logs      ${DIM}— tail logs (follow)${NC}\n"
  printf "  ${GREEN} 5)${NC} ps        ${DIM}— list containers${NC}\n"
  printf "  ${GREEN} 6)${NC} build     ${DIM}— build images${NC}\n"
  printf "  ${GREEN} 7)${NC} stop      ${DIM}— stop containers${NC}\n"
  printf "  ${GREEN} 8)${NC} start     ${DIM}— start containers${NC}\n"
  printf "  ${YELLOW} 9)${NC} Keluar\n"

  printf "${DIM}#? ${NC}"
  read -r pilihan

  case "$pilihan" in
    1) CMD="up" ;;
    2) CMD="down" ;;
    3) CMD="restart" ;;
    4) CMD="logs" ;;
    5) CMD="ps" ;;
    6) CMD="build" ;;
    7) CMD="stop" ;;
    8) CMD="start" ;;
    9|"")
      printf "${YELLOW}Dibatalkan.${NC}\n"
      exit 0
      ;;
    *)
      printf "${RED}Pilihan tidak valid.${NC}\n"
      exit 1
      ;;
  esac
}

# ---- Argumen info/help ----
if [ "${1:-}" = "info" ] || [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

CMD="${1:-}"
[ $# -gt 0 ] && shift

# ---- Mode interaktif kalau tanpa argumen ----
if [ -z "$CMD" ]; then
  pilih_command
fi

do_run "$CMD" "$@"