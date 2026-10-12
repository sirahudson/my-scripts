#!/bin/sh

set -eu

repo="sirahudson/my-scripts"
install_prefix="${HOME}/.local"

if [ "$(id -u)" -eq 0 ]; then
    install_prefix="/usr/local"
fi

have() {
    command -v "$1" >/dev/null 2>&1
}

run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif have doas; then
        doas "$@"
    elif have sudo; then
        sudo "$@"
    else
        echo "Error: pasang dependency dengan doas atau sudo." >&2
        exit 1
    fi
}

# Cek dependency yang belum terpasang
missing=""
for cmd in bash curl git make; do
    have "$cmd" || missing="${missing} ${cmd}"
done

if [ -n "${missing}" ]; then
    echo "Memasang dependency:${missing}"
    # shellcheck disable=SC2086
    set -- ${missing}
    if have apk; then
        run_root apk add "$@" coreutils
    elif have apt-get; then
        run_root apt-get update
        run_root apt-get install -y "$@"
    else
        echo "Error: package manager tidak dikenali. Pasang manual:${missing}" >&2
        exit 1
    fi
fi

# Pastikan semuanya benar-benar tersedia
for cmd in bash curl git make; do
    if ! have "$cmd"; then
        echo "Error: ${cmd} belum terpasang." >&2
        exit 1
    fi
done

mkdir -p "${install_prefix}/bin"

if ! have bpkg; then
    curl -fsSL https://get.bpkg.sh | PREFIX="${install_prefix}" bash
fi

case ":${PATH}:" in
    *":${install_prefix}/bin:"*) ;;
    *)
        export PATH="${install_prefix}/bin:${PATH}"
        ;;
esac

shell_name="$(basename "${SHELL:-sh}")"
case "${shell_name}" in
    zsh) shell_config="${HOME}/.zshrc" ;;
    bash) shell_config="${HOME}/.bashrc" ;;
    *) shell_config="${HOME}/.profile" ;;
esac

path_line="export PATH=\"${install_prefix}/bin:\$PATH\""
if [ ! -f "${shell_config}" ] || ! grep -Fqx "${path_line}" "${shell_config}"; then
    printf '\n# bpkg\n%s\n' "${path_line}" >> "${shell_config}"
fi

PREFIX="${install_prefix}" bpkg install -g "${repo}"

echo "Selesai. Jalankan shell baru atau: . ${shell_config}"