# my-scripts

Script utilitas pribadi untuk Docker dan pengecekan sistem.

## Setup Alpine

### Cara cepat

Install dependency dan jalankan setup dari root repo:

```sh
apk update
apk add bash curl git coreutils make
sh setup-bpkg.sh
```

Untuk user non-root, script memakai `doas` atau `sudo` saat menjalankan `apk`:

```sh
sh setup-bpkg.sh
```

Script ini mendukung `ash`, `bash`, dan `zsh`. PATH akan ditambahkan ke file shell yang sesuai: `.profile`, `.bashrc`, atau `.zshrc`.

Yang dilakukan script:

- memasang `bpkg` jika belum ada;
- memasang command repo secara global untuk user ke `$HOME/.local/bin`;
- memasang ke `/usr/local/bin` jika dijalankan sebagai root.

Verifikasi:

```sh
bpkg --version
cmd-run --help
```

### Instalasi manual

```sh
curl -Lo- https://get.bpkg.sh | bash
export PATH="$HOME/.local/bin:$PATH"
bpkg install -g sirahudson/my-scripts
```

Manifest [`bpkg.json`](bpkg.json) menjalankan `make install` dan memasang lima command berikut:

```text
cmd-run  cmd-logs  cmd-shell  cmd-stats  cmd-prune
```

## Dependency runtime

Docker Engine/Desktop dan Docker Compose v2 diperlukan untuk command `cmd-*`. `cmd-stats` juga membutuhkan `procps`, `util-linux`, dan `watch`.

Install Docker sesuai environment Alpine, lalu pastikan ini berhasil:

```sh
docker version
docker compose version
```

`general/lang` dan `general/monitor` membutuhkan `csview`.

## Pemakaian

Jalankan command dari folder project Compose yang berisi file `.yml`:

```sh
cmd-run up                 # start di background
cmd-run ps                 # lihat container
cmd-run logs nginx         # log service
cmd-run exec app sh        # shell service
cmd-run down               # stop dan hapus
cmd-logs nginx             # ikuti log nginx
cmd-shell app sh           # buka shell
cmd-stats all --watch 5    # monitor setiap 5 detik
cmd-prune image            # hapus image yang tidak terpakai
```

Tanpa argumen, `cmd-run`, `cmd-logs`, `cmd-shell`, dan `cmd-prune` membuka menu interaktif. Semua command mendukung `--help`.

Override file Compose atau nama project jika perlu:

```sh
COMPOSE_FILE_OVERRIDE=compose.prod.yml cmd-run up
COMPOSE_PROJECT_OVERRIDE=nama-project cmd-run ps
```

## Utilitas umum

```sh
sh general/greeting
bash general/lang
sh general/monitor
```

Atau beri permission executable dengan `chmod +x general/*`.

## Uninstall

Hapus command yang dipasang via `bpkg` dengan menjalankan target uninstall dari source repo:

```sh
make uninstall PREFIX="$HOME/.local"
```

Untuk instalasi root:

```sh
sudo make uninstall
```
