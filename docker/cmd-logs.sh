#!/usr/bin/env sh
# logs — tail logs dari container service (auto-detect dari folder aktif/pwd)
#
# Variabel opsional:
#   COMPOSE_PROJECT_OVERRIDE  nama project (default: nama folder aktif)
#   COMPOSE_FILE_OVERRIDE     file compose (default: deteksi otomatis)
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
  PROJECT="$(printf '%s' "$RAW_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g; s/^[^a-z0-9]*//')"
  [ -n "$PROJECT" ] || PROJECT="app"
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

# Pastikan plugin 'docker compose' tersedia (dipanggil setelah akses Docker beres)
ensure_compose() {
  # shellcheck disable=SC2086
  $DOCKER compose version >/dev/null 2>&1 \
    || die "Plugin 'docker compose' belum terpasang (Alpine: apk add docker-cli-compose; repo resmi Docker di Debian: apt install docker-compose-plugin)."
}

compose() {
  # shellcheck disable=SC2086
  $DOCKER compose -f "$FILE" -p "$PROJECT" "$@"
}

SERVICES=""

load_services() {
  SERVICES="$(compose config --services 2>/dev/null)" || SERVICES=""
  [ -n "$SERVICES" ] || die "Tidak ada service ditemukan. Cek ${FILE}"
}

usage() {
  # Daftar service hanya ditampilkan jika Docker bisa diakses tanpa sudo,
  # supaya 'help' tidak pernah meminta password.
  services_text="  (tidak tersedia: Docker tidak bisa diakses tanpa sudo atau file compose tidak ada)"
  if [ -n "$FILE" ] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    svc_list="$(compose config --services 2>/dev/null)" || svc_list=""
    if [ -n "$svc_list" ]; then
      services_text="$(printf '%s\n' "$svc_list" | sed 's/^/  /')"
    fi
  fi

  cat <<EOF
Usage:
  ./${SCRIPT_NAME} [info|help|-h|--help]
  ./${SCRIPT_NAME} <service> [args...]
  ./${SCRIPT_NAME}                    (mode pilih interaktif)

Nama service harus menjadi argumen pertama. Argumen lain diteruskan ke
'docker compose logs'. Khusus '-n N' diterjemahkan menjadi '--tail N'.
Tanpa '-f', log ditampilkan lalu selesai (tidak follow).

Terdeteksi otomatis:
  Project : ${PROJECT}
  File    : ${FILE:-"(tidak ditemukan)"}
  Dir     : ${CURRENT_DIR}

Akses Docker:
  Jika user tidak bisa mengakses Docker langsung, skrip meminta password sudo
  satu kali di awal lalu memakai 'sudo docker'. Jalankan sebagai user biasa,
  jangan dengan 'sudo ./${SCRIPT_NAME}'.

Override manual (opsional):
  COMPOSE_PROJECT_OVERRIDE=nama ./${SCRIPT_NAME}
  COMPOSE_FILE_OVERRIDE=file.yml ./${SCRIPT_NAME}

Services:
${services_text}

Examples:
  ./${SCRIPT_NAME} nginx
  ./${SCRIPT_NAME} app --tail 50
  ./${SCRIPT_NAME} app -n 50
  ./${SCRIPT_NAME} db -f
EOF
}

SERVICE=""
TAIL_N=""

pilih_service() {
  load_services

  printf "${CYAN}Project: ${WHITE}%s${NC} ${DIM}(%s)${NC}\n" "$PROJECT" "$FILE"
  printf "${CYAN}Pilih service (logs):${NC}\n"

  i=1
  for svc in $SERVICES; do
    printf "  ${GREEN}%2d)${NC} %s\n" "$i" "$svc"
    i=$((i + 1))
  done
  total=$i
  printf "  ${YELLOW}%2d)${NC} Keluar\n" "$total"

  printf "${DIM}#? ${NC}"
  pilihan=""
  read -r pilihan || true

  if [ -z "$pilihan" ] || [ "$pilihan" = "$total" ]; then
    printf "${YELLOW}Dibatalkan.${NC}\n"
    exit 1
  fi

  case "$pilihan" in
    ''|*[!0-9]*) die "Input tidak valid." ;;
  esac

  i=1
  for svc in $SERVICES; do
    if [ "$i" = "$pilihan" ]; then
      SERVICE="$svc"
      break
    fi
    i=$((i + 1))
  done

  [ -n "$SERVICE" ] || die "Pilihan tidak valid."

  printf "${DIM}Tail berapa baris (kosong = follow -f):${NC} "
  read -r TAIL_N || true

  case "$TAIL_N" in
    *[!0-9]*) die "Jumlah baris harus angka: ${TAIL_N}" ;;
  esac

  printf "${GREEN}✔${NC} Menampilkan log ${WHITE}%s${NC}\n" "$SERVICE"
}

# ---- Argumen info/help (tidak butuh Docker maupun sudo) ----
case "${1:-}" in
  info|help|-h|--help)
    usage
    exit 0
    ;;
esac

[ -n "$FILE" ] || die "Tidak ditemukan file compose di ${CURRENT_DIR} (compose.yaml, compose.yml, docker-compose.yaml, docker-compose.yml)."

# 'shift' hanya dipanggil kalau ada argumen (dash menghentikan skrip jika tidak)
if [ $# -gt 0 ]; then
  SERVICE="$1"
  shift
fi

case "$SERVICE" in
  -*) die "Nama service harus menjadi argumen pertama (contoh: ./${SCRIPT_NAME} app -n 50)." ;;
esac

ensure_docker
ensure_compose

# ---- Mode interaktif kalau tanpa argumen ----
if [ -z "$SERVICE" ]; then
  pilih_service
  if [ -n "$TAIL_N" ]; then
    set -- --tail "$TAIL_N"
  else
    set -- -f
  fi
fi

# ---- Terjemahkan '-n N' menjadi '--tail N' tanpa memecah argumen ----
n=$#
while [ "$n" -gt 0 ]; do
  arg="$1"
  shift
  n=$((n - 1))
  case "$arg" in
    -n)
      [ "$n" -gt 0 ] || die "Opsi -n butuh angka. Contoh: -n 50"
      val="$1"
      shift
      n=$((n - 1))
      case "$val" in
        ''|*[!0-9]*) die "Nilai -n harus angka: ${val}" ;;
      esac
      set -- "$@" --tail "$val"
      ;;
    *)
      set -- "$@" "$arg"
      ;;
  esac
done

compose logs "$@" "$SERVICE"