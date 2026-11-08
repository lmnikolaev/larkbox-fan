#!/bin/sh
# Build dist/larkbox-fan_<version>_all.deb from the sources in this repo.
# Requires only dpkg-deb (present on every Debian/Ubuntu system).
set -e
cd "$(dirname "$0")"
VER=$(sed -n 's/^Version: //p' packaging/DEBIAN/control)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

install -Dm755 src/larkbox-fan          "$ROOT/usr/libexec/larkbox-fan/larkbox-fan"
install -Dm644 src/larkbox-fan.service  "$ROOT/usr/lib/systemd/system/larkbox-fan.service"
install -Dm644 src/README.doc           "$ROOT/usr/share/doc/larkbox-fan/README"
install -Dm644 LICENSE                  "$ROOT/usr/share/doc/larkbox-fan/copyright"
mkdir -p "$ROOT/DEBIAN"
install -m644 packaging/DEBIAN/control  "$ROOT/DEBIAN/control"
for s in postinst prerm postrm; do
    install -m755 "packaging/DEBIAN/$s" "$ROOT/DEBIAN/$s"
done

mkdir -p dist
dpkg-deb --root-owner-group --build "$ROOT" "dist/larkbox-fan_${VER}_all.deb"
