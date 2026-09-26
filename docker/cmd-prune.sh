#!/usr/bin/env sh
# prune — membersihkan Docker images, build cache, dan volumes yang tidak terpakai
set -e

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RED='\033[1;31m'
DIM='\033[2m'
NC='\033[0m'

usage() {
  cat <<'EOF'
Usage:
  ./cmd_prune [info|help|-h|--help]
  ./cmd_prune <image|volume|cache|all> [-f|--force]
  ./cmd_prune                    (mode pilih interaktif)

Targets:
  image|images    hapus unused images
  volume|volumes  hapus unused volumes
  cache|builder   hapus Docker build cache
  all             hapus images, cache, dan volumes

Options:
  -f, --force     skip konfirmasi

Examples:
  ./cmd_prune image -f
  ./cmd_prune cache --force
  ./cmd_prune all -f
EOF
}

# confirm "pesan" -> return 0 kalau user setuju, exit kalau tidak
confirm() {
  printf "${YELLOW}⚠ %s${NC}\n" "$1"
  printf "${DIM}Lanjutkan? [y/N]${NC} "
  read -r jawaban
  case "$jawaban" in
    y|Y) return 0 ;;
    *)
      printf "${YELLOW}Dibatalkan.${NC}\n"
      exit 0
      ;;
  esac
}

do_prune() {
  target="$1"
  force="$2"

  case "$target" in
    image|images)
      msg="Akan menghapus semua unused images (termasuk dangling & unreferenced)."
      cmd="docker image prune -a"
      ;;
    volume|volumes)
      msg="Akan menghapus semua unused volumes (termasuk named volume, bukan cuma anonymous)."
      cmd="docker volume prune -a"
      ;;
    cache|builder|build-cache)
      msg="Akan membersihkan Docker build cache (legacy builder + semua buildx builder)."
      cmd="docker builder prune -a && docker buildx prune -a"
      ;;
    all)
      msg="Akan menghapus semua unused images, build cache (legacy + buildx), dan volumes (termasuk named volume yang unused)."
      cmd="docker image prune -a && docker builder prune -a && docker buildx prune -a && docker volume prune -a"
      ;;
    *)
      printf "${RED}✘ Target tidak dikenal: %s${NC}\n" "$target" >&2
      usage
      exit 1
      ;;
  esac

  if [ "$force" = "-f" ] || [ "$force" = "--force" ]; then
    printf "${CYAN}➜ %s${NC}\n" "$msg"
    # Sisipkan -f setelah tiap subcommand "prune ..." (bukan cuma di akhir string),
    # supaya semua command dalam chain "&&" (misal target 'all') ikut dapat flag force.
    forced_cmd=$(printf '%s' "$cmd" | sed -E 's/(prune -a|prune)( &&|$)/\1 -f\2/g')
    eval "$forced_cmd"
  else
    confirm "$msg"
    printf "${CYAN}➜ Menjalankan...${NC}\n"
    eval "$cmd"
  fi

  printf "${GREEN}✔ Selesai membersihkan '%s'${NC}\n" "$target"
}

pilih_target() {
  printf "${CYAN}Pilih target prune:${NC}\n"
  printf "  ${GREEN} 1)${NC} image    ${DIM}— hapus unused images${NC}\n"
  printf "  ${GREEN} 2)${NC} volume   ${DIM}— hapus unused volumes${NC}\n"
  printf "  ${GREEN} 3)${NC} cache    ${DIM}— hapus build cache${NC}\n"
  printf "  ${RED} 4)${NC} all      ${DIM}— hapus semuanya${NC}\n"
  printf "  ${YELLOW} 5)${NC} Keluar\n"

  printf "${DIM}#? ${NC}"
  read -r pilihan

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

TARGET="${1:-}"
FORCE="${2:-}"

# ---- Mode interaktif kalau tanpa argumen ----
if [ -z "$TARGET" ]; then
  pilih_target
fi

do_prune "$TARGET" "$FORCE"