#!/usr/bin/env sh
# prune — membersihkan Docker images, build cache, dan volumes yang tidak terpakai
#
# Variabel opsional:
#   NO_COLOR=1   matikan warna
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

die() {
  printf "${RED}✘ %s${NC}\n" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  ./${SCRIPT_NAME} [info|help|-h|--help]
  ./${SCRIPT_NAME} <image|volume|cache|all> [-f|--force]
  ./${SCRIPT_NAME}                    (mode pilih interaktif)

Targets:
  image|images    hapus unused images
  volume|volumes  hapus unused volumes (termasuk named volume, DATA IKUT HILANG)
  cache|builder   hapus Docker build cache
  all             hapus images, cache, dan volumes

Options:
  -f, --force     skip konfirmasi

Akses Docker:
  Jika user tidak bisa mengakses Docker langsung, skrip meminta password sudo
  satu kali di awal lalu memakai 'sudo docker'. Jalankan sebagai user biasa,
  jangan dengan 'sudo ./${SCRIPT_NAME}'.

Examples:
  ./${SCRIPT_NAME} image -f
  ./${SCRIPT_NAME} cache --force
  ./${SCRIPT_NAME} all -f
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

dk() {
  # shellcheck disable=SC2086
  $DOCKER "$@"
}

# Docker >= 23.0 butuh 'volume prune --all' agar named volume ikut dihapus.
# Docker lama tidak punya flag itu (prune sudah menghapus semua unused volume).
VOLUME_ALL=0
detect_volume_all() {
  if dk volume prune --help 2>&1 | grep -q -- '--all'; then
    VOLUME_ALL=1
  fi
}

# Semua langkah dipanggil dengan -f: konfirmasi sudah ditangani skrip ini
# (lewat --force atau pertanyaan y/N), jadi Docker tidak bertanya lagi.
prune_images() {
  dk image prune -a -f
}

prune_cache() {
  dk builder prune -a -f
  if dk buildx version >/dev/null 2>&1; then
    dk buildx prune -a -f
  else
    printf "${YELLOW}⚠ Plugin buildx tidak terpasang, langkah 'buildx prune' dilewati.${NC}\n"
  fi
}

prune_volumes() {
  if [ "$VOLUME_ALL" = "1" ]; then
    dk volume prune -a -f
  else
    dk volume prune -f
  fi
}

# confirm "pesan" -> return 0 kalau user setuju, keluar kalau tidak
confirm() {
  printf "${YELLOW}⚠ %s${NC}\n" "$1"
  printf "${DIM}Lanjutkan? [y/N]${NC} "
  jawaban=""
  read -r jawaban || true
  case "$jawaban" in
    y|Y) return 0 ;;
    *)
      printf "${YELLOW}Dibatalkan.${NC}\n"
      exit 0
      ;;
  esac
}

MSG=""
STEPS=""

# Validasi target sebelum menyentuh Docker (tidak memicu prompt sudo untuk typo)
resolve_target() {
  case "$1" in
    image|images)
      MSG="Akan menghapus semua unused images (termasuk dangling & unreferenced)."
      STEPS="images"
      ;;
    volume|volumes)
      MSG="Akan menghapus semua unused volumes (termasuk named volume, bukan cuma anonymous). Data di dalamnya tidak bisa dikembalikan."
      STEPS="volumes"
      ;;
    cache|builder|build-cache)
      MSG="Akan membersihkan Docker build cache (builder bawaan + builder buildx yang sedang aktif)."
      STEPS="cache"
      ;;
    all)
      MSG="Akan menghapus semua unused images, build cache, dan volumes (termasuk named volume yang unused). Data volume tidak bisa dikembalikan."
      STEPS="images cache volumes"
      ;;
    *)
      printf "${RED}✘ Target tidak dikenal: %s${NC}\n" "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

do_prune() {
  if [ "$FORCE" = "1" ]; then
    printf "${CYAN}➜ %s${NC}\n" "$MSG"
  else
    confirm "$MSG"
    printf "${CYAN}➜ Menjalankan...${NC}\n"
  fi

  for step in $STEPS; do
    case "$step" in
      images)  prune_images ;;
      cache)   prune_cache ;;
      volumes) prune_volumes ;;
    esac
  done

  printf "${GREEN}✔ Selesai membersihkan '%s'${NC}\n" "$TARGET"
}

TARGET=""
FORCE=0

pilih_target() {
  printf "${CYAN}Pilih target prune:${NC}\n"
  printf "  ${GREEN} 1)${NC} image    ${DIM}— hapus unused images${NC}\n"
  printf "  ${GREEN} 2)${NC} volume   ${DIM}— hapus unused volumes${NC}\n"
  printf "  ${GREEN} 3)${NC} cache    ${DIM}— hapus build cache${NC}\n"
  printf "  ${RED} 4)${NC} all      ${DIM}— hapus semuanya${NC}\n"
  printf "  ${YELLOW} 5)${NC} Keluar\n"

  printf "${DIM}#? ${NC}"
  pilihan=""
  read -r pilihan || true

  case "$pilihan" in
    1) TARGET="image" ;;
    2) TARGET="volume" ;;
    3) TARGET="cache" ;;
    4) TARGET="all" ;;
    5|"")
      printf "${YELLOW}Dibatalkan.${NC}\n"
      exit 0
      ;;
    *)
      die "Pilihan tidak valid."
      ;;
  esac
}

# ---- Argumen info/help (tidak butuh Docker maupun sudo) ----
case "${1:-}" in
  info|help|-h|--help)
    usage
    exit 0
    ;;
esac

# ---- Parsing argumen: target dan -f/--force dalam urutan apa pun ----
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
    -*) die "Opsi tidak dikenal: ${arg}" ;;
    *)
      [ -z "$TARGET" ] || die "Terlalu banyak target: '${TARGET}' dan '${arg}'. Pilih salah satu."
      TARGET="$arg"
      ;;
  esac
done

# ---- Mode interaktif kalau tanpa target ----
if [ -z "$TARGET" ]; then
  pilih_target
fi

resolve_target "$TARGET"
ensure_docker
detect_volume_all
do_prune