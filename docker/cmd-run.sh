#!/usr/bin/env sh
# run — wrapper Docker Compose modular dengan flag dinamis & smart bake
set -e

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RED='\033[1;31m'
DIM='\033[2m'
NC='\033[0m'

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

# Cek apakah folder ini menggunakan Docker Bake
HAS_BAKE=false
if [ -f "${CURRENT_DIR}/docker-bake.hcl" ] || [ -f "${CURRENT_DIR}/docker-bake.json" ]; then
  HAS_BAKE=true
fi

usage() {
  cat <<EOF
Usage:
  ./cmd_run [info|help|-h|--help]
  ./cmd_run <command> [flags / args...]
  ./cmd_run                    (mode pilih interaktif)

Terdeteksi otomatis:
  Project : ${PROJECT}
  File    : ${FILE}
  Dir     : ${CURRENT_DIR}
  Bake    : ${HAS_BAKE}

Commands:
  up [flags...]   start containers (contoh: ./cmd_run up, ./cmd_run up --build, ./cmd_run up --no-build)
  down            stop & hapus containers
  restart         restart containers
  logs            tail logs (follow)
  ps              list containers
  build           build images (otomatis pakai Bake jika ada docker-bake.hcl)
  stop            stop containers
  start           start containers
  exec <svc> cmd  jalankan command di dalam service
  run <svc> cmd   jalankan one-off command
  <lainnya>       diteruskan langsung ke docker compose

Examples:
  ./cmd_run up                     # Start containers instan (background)
  ./cmd_run up --build             # Rebuild dulu (otomatis Bake jika ada), lalu start
  ./cmd_run up --no-build          # Start hanya image yang sudah ada
  ./cmd_run up cloudflare-manager  # Start 1 service spesifik
  ./cmd_run build                  # Build images (otomatis Bake jika ada)
  ./cmd_run logs nginx             # Lihat streaming log service nginx
  ./cmd_run exec app sh            # Masuk ke dalam terminal container
  ./cmd_run down                   # Stop & bersihkan container
EOF
}

do_run() {
  cmd="$1"
  shift || true

  printf "${CYAN}➜ %s${NC} ${DIM}(project: ${PROJECT}, file: ${FILE})${NC}\n" "$cmd"

  case "$cmd" in
    up)
      # Analisis argumen secara dinamis
      FORCE_BUILD=false
      PASSED_ARGS=""

      for arg in "$@"; do
        if [ "$arg" = "--build" ]; then
          FORCE_BUILD=true
        else
          PASSED_ARGS="${PASSED_ARGS} ${arg}"
        fi
      done

      # Jika user minta --build
      if [ "$FORCE_BUILD" = "true" ]; then
        if [ "$HAS_BAKE" = "true" ]; then
          printf "${CYAN}🛠️  Mendeteksi docker-bake.hcl. Memasak image via Bake (--allow network.host)...${NC}\n"
          docker buildx bake --allow network.host --load
          $COMPOSE up -d ${PASSED_ARGS}
        else
          $COMPOSE up -d --build ${PASSED_ARGS}
        fi
      else
        # Jika up biasa atau membawa flag lain (seperti --no-build atau nama service)
        $COMPOSE up -d "$@"
      fi
      ;;
    build)
      if [ "$HAS_BAKE" = "true" ]; then
        printf "${CYAN}🛠️  Mengeksekusi Docker Buildx Bake (--allow network.host)...${NC}\n"
        docker buildx bake --allow network.host --load "$@"
      else
        $COMPOSE build "$@"
      fi
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
  printf "${CYAN}Project: ${WHITE}${PROJECT}${NC} ${DIM}(${FILE})${NC}"
  [ "$HAS_BAKE" = "true" ] && printf " ${YELLOW}[Bake Enabled]${NC}"
  printf "\n${CYAN}Pilih perintah:${NC}\n"
  printf "  ${GREEN} 1)${NC} up                ${DIM}— start containers (instant)${NC}\n"
  printf "  ${GREEN} 2)${NC} up --build        ${DIM}— rebuild dulu lalu start${NC}\n"
  printf "  ${GREEN} 3)${NC} down              ${DIM}— stop & hapus containers${NC}\n"
  printf "  ${GREEN} 4)${NC} restart           ${DIM}— restart containers${NC}\n"
  printf "  ${GREEN} 5)${NC} logs              ${DIM}— tail logs (follow)${NC}\n"
  printf "  ${GREEN} 6)${NC} ps                ${DIM}— list containers${NC}\n"
  printf "  ${GREEN} 7)${NC} build             ${DIM}— build images${NC}\n"
  printf "  ${GREEN} 8)${NC} stop              ${DIM}— stop containers${NC}\n"
  printf "  ${GREEN} 9)${NC} start             ${DIM}— start containers${NC}\n"
  printf "  ${YELLOW}10)${NC} Keluar\n"

  printf "${DIM}#? ${NC}"
  read -r pilihan

  case "$pilihan" in
    1) CMD="up" ;;
    2) CMD="up"; set -- "--build" ;;
    3) CMD="down" ;;
    4) CMD="restart" ;;
    5) CMD="logs" ;;
    6) CMD="ps" ;;
    7) CMD="build" ;;
    8) CMD="stop" ;;
    9) CMD="start" ;;
    10|"")
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
