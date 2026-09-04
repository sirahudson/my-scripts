#!/bin/sh

set -eu

repo="sirahudson/my-scripts"
install_prefix="${HOME}/.local"

if [ "$(id -u)" -eq 0 ]; then
    install_prefix="/usr/local"
fi

if command -v apk >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
        apk add bash curl git coreutils make
    elif command -v doas >/dev/null 2>&1; then
        doas apk add bash curl git coreutils make
    elif command -v sudo >/dev/null 2>&1; then
        sudo apk add bash curl git coreutils make
    else
        echo "Error: pasang dependency dengan doas atau sudo." >&2
        exit 1
    fi
fi

if ! command -v bash >/dev/null 2>&1; then
    echo "Error: bash belum terpasang." >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl belum terpasang." >&2
    exit 1
fi

if ! command -v bpkg >/dev/null 2>&1; then
    curl -Lo- https://get.bpkg.sh | bash
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