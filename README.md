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

Semua command `cmd-*` memerlukan Docker yang berjalan dan dapat diakses oleh user, serta Docker Compose v2. Jika akses langsung ke Docker tidak tersedia, command selain `cmd-stats` dapat memakai `sudo` atau `doas`; `cmd-stats` memerlukan akses langsung ke Docker. Jangan menjalankan command dengan `sudo cmd-...`, karena konfigurasi Compose dan file state dapat berbeda untuk root.

Di Alpine, Compose v2 tersedia melalui `docker-cli-compose`. Di Debian/Ubuntu, gunakan `docker-compose-plugin` dari repo resmi Docker atau paket Compose v2 yang disediakan distro.

`cmd-run` memakai Docker Buildx saat project berisi `docker-bake.hcl`/`docker-bake.json` dan menjalankan build. Paket Buildx opsional untuk penggunaan Compose biasa:

```sh
# Repo resmi Docker di Debian/Ubuntu
sudo apt install docker-buildx-plugin

# Alpine
apk add docker-cli-buildx
```

`cmd-stats` membutuhkan `procps` (`ps`, serta `watch` untuk mode `--watch`), `coreutils` (`nproc`), dan `util-linux` (`nsenter`). Script ini menggunakan `/bin/sh` dan `/proc`, sehingga berjalan pada distro Linux dengan paket tersebut.

Install dependency `cmd-stats`:

```sh
# Debian/Ubuntu
sudo apt install procps coreutils util-linux

# Alpine
apk add procps coreutils util-linux
```

Pastikan Docker dan Compose tersedia, lalu cek:

```sh
docker version
docker compose version
```

`general/lang` dan `general/monitor` membutuhkan `csview`.

**Perhatian:** `cmd-prune volume` dan `cmd-prune all` dapat menghapus named volume yang tidak sedang digunakan, termasuk datanya. Periksa konfirmasi yang ditampilkan; `-f`/`--force` melewati konfirmasi.

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
