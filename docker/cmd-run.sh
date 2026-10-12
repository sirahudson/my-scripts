#!/usr/bin/env sh
# run — wrapper Docker Compose modular dengan flag dinamis & smart bake
#
# Variabel opsional:
#   COMPOSE_PROJECT_OVERRIDE  nama project (default: nama folder aktif)
#   COMPOSE_FILE_OVERRIDE     file compose (default: deteksi otomatis)
#   BAKE_NO_NETWORK_HOST=1    jangan pakai --allow network.host saat bake
#   NO_COLOR=1                matikan warna
set -eu

# ---- Warna (dimatikan otomatis jika output bukan terminal) ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  GREEN='\033[1;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[1;36m'
  WHITE='\033[1;37m'
  RED='\033[1;31m'
  DIM='\033[2m'
  NC='\033[0m'
else
  GREEN='' YELLOW='' CYAN='' WHITE='' RED='' DIM='' NC=''
fi

SCRIPT_NAME="$(basename "$0")"
CURRENT_DIR="$(pwd)"

die() {
  printf "${RED}✘ %s${NC}\n" "$*" >&2
  exit 1
}

# ---- Deteksi nama project dari folder aktif ----
if [ -n "${COMPOSE_PROJECT_OVERRIDE:-}" ]; then
  PROJECT="$COMPOSE_PROJECT_OVERRIDE"
else
  RAW_NAME="$(basename "$CURRENT_DIR")"
  PROJECT="$(printf '%s' "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g')"
fi

# ---- Deteksi file compose (nama standar saja) ----
FILE=""
if [ -n "${COMPOSE_FILE_OVERRIDE:-}" ]; then
  FILE="$COMPOSE_FILE_OVERRIDE"
else
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [ -f "${CURRENT_DIR}/${f}" ]; then
      FILE="$f"
      break
    fi
  done
fi

# ---- Cek apakah folder ini menggunakan Docker Bake ----
HAS_BAKE=false
if [ -f "${CURRENT_DIR}/docker-bake.hcl" ] || [ -f "${CURRENT_DIR}/docker-bake.json" ]; then
  HAS_BAKE=true
fi

usage() {
  cat <<EOF
Usage:
  ./${SCRIPT_NAME} [info|help|-h|--help]
  ./${SCRIPT_NAME} <command> [flags / args...]
  ./${SCRIPT_NAME}                    (mode pilih interaktif)

Terdeteksi otomatis:
  Project : ${PROJECT}
  File    : ${FILE:-"(tidak ditemukan)"}
  Dir     : ${CURRENT_DIR}
  Bake    : ${HAS_BAKE}

Akses Docker:
  Jika user tidak bisa mengakses Docker langsung, skrip meminta password sudo
  satu kali di awal lalu menjalankan semua perintah dengan 'sudo docker'.
  Jalankan skrip sebagai user biasa, jangan dengan 'sudo ./${SCRIPT_NAME}'.

Commands:
  up [flags...]   start containers (contoh: up, up --build, up --no-build)
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
  ./${SCRIPT_NAME} up                     # Start containers (background)
  ./${SCRIPT_NAME} up --build             # Rebuild dulu (otomatis Bake jika ada), lalu start
  ./${SCRIPT_NAME} up --no-build          # Start hanya image yang sudah ada
  ./${SCRIPT_NAME} up cloudflare-manager  # Start 1 service spesifik
  ./${SCRIPT_NAME} build                  # Build images (otomatis Bake jika ada)
  ./${SCRIPT_NAME} logs nginx             # Streaming log service nginx
  ./${SCRIPT_NAME} exec app sh            # Masuk ke terminal container
  ./${SCRIPT_NAME} down                   # Stop & bersihkan container
EOF
}

# ---- Akses Docker: langsung jika bisa, kalau tidak minta sudo dulu ----
DOCKER="docker"

ensure_docker() {
  command -v docker >/dev/null 2>&1 || die "docker tidak ditemukan di PATH."

  if docker info >/dev/null 2>&1; then
    return 0
  fi

  command -v sudo >/dev/null 2>&1 || die "Docker tidak bisa diakses dan sudo tidak tersedia."

  printf "${YELLOW}🔐 Butuh sudo untuk mengakses Docker.${NC}\n"
  sudo -v || die "Autentikasi sudo gagal."
  DOCKER="sudo docker"

  # shellcheck disable=SC2086
  $DOCKER info >/dev/null 2>&1 || die "Docker daemon tidak berjalan."
}

# Perpanjang timestamp sudo sebelum langkah panjang (mis. setelah build)
refresh_sudo() {
  if [ "$DOCKER" != "docker" ]; then
    sudo -v || die "Autentikasi sudo gagal."
  fi
}

compose() {
  # shellcheck disable=SC2086
  $DOCKER compose -f "$FILE" -p "$PROJECT" "$@"
}

run_bake() {
  if [ "${BAKE_NO_NETWORK_HOST:-}" = "1" ]; then
    printf "${CYAN}🛠️  Mengeksekusi Docker Buildx Bake...${NC}\n"
    # shellcheck disable=SC2086
    $DOCKER buildx bake --load "$@"
  else
    printf "${CYAN}🛠️  Mengeksekusi Docker Buildx Bake (--allow network.host)...${NC}\n"
    # shellcheck disable=SC2086
    $DOCKER buildx bake --allow network.host --load "$@"
  fi
}

do_run() {
  cmd="$1"
  shift

  printf "${CYAN}➜ %s${NC} ${DIM}(project: %s, file: %s)${NC}\n" "$cmd" "$PROJECT" "$FILE"

  case "$cmd" in
    up)
      # Pisahkan --build dari argumen lain tanpa memecah argumen berspasi
      force_build=false
      n=$#
      while [ "$n" -gt 0 ]; do
        arg="$1"
        shift
        n=$((n - 1))
        if [ "$arg" = "--build" ]; then
          force_build=true
        else
          set -- "$@" "$arg"
        fi
      done

      if [ "$force_build" = "true" ]; then
        if [ "$HAS_BAKE" = "true" ]; then
          printf "${CYAN}Mendeteksi docker-bake. Memasak image via Bake...${NC}\n"
          run_bake
          refresh_sudo
          compose up -d "$@"
        else
          compose up -d --build "$@"
        fi
      else
        compose up -d "$@"
      fi
      ;;
    build)
      if [ "$HAS_BAKE" = "true" ]; then
        run_bake "$@"
      else
        compose build "$@"
      fi
      ;;
    logs)
      compose logs -f "$@"
      ;;
    exec)
      [ $# -ge 1 ] || die "Usage: ./${SCRIPT_NAME} exec <service> [command]"
      compose exec "$@"
      ;;
    run)
      [ $# -ge 1 ] || die "Usage: ./${SCRIPT_NAME} run <service> [command]"
      compose run "$@"
      ;;
    *)
      # down, restart, ps, stop, start, dan perintah compose lainnya
      compose "$cmd" "$@"
      ;;
  esac

  printf "${GREEN}✔ Selesai${NC}\n"
}

CMD=""
EXTRA_ARGS=""

pilih_command() {
  printf "${CYAN}Project: ${WHITE}%s${NC} ${DIM}(%s)${NC}" "$PROJECT" "$FILE"
  if [ "$HAS_BAKE" = "true" ]; then
    printf " ${YELLOW}[Bake Enabled]${NC}"
  fi
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
  pilihan=""
  read -r pilihan || true

  case "$pilihan" in
    1) CMD="up" ;;
    2) CMD="up"; EXTRA_ARGS="--build" ;;
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
      die "Pilihan tidak valid."
      ;;
  esac
}

# ---- Argumen info/help (tidak butuh Docker maupun file compose) ----
case "${1:-}" in
  info|help|-h|--help)
    usage
    exit 0
    ;;
esac

[ -n "$FILE" ] || die "Tidak ditemukan file compose di ${CURRENT_DIR} (compose.yaml, compose.yml, docker-compose.yaml, docker-compose.yml)."

if [ $# -gt 0 ]; then
  CMD="$1"
  shift
fi

# ---- Mode interaktif kalau tanpa argumen ----
if [ -z "$CMD" ]; then
  pilih_command
  if [ -n "$EXTRA_ARGS" ]; then
    # shellcheck disable=SC2086
    set -- $EXTRA_ARGS
  fi
fi

ensure_docker
do_run "$CMD" "$@"