#!/bin/sh
# One-step installer for larkbox-fan (Chuwi LarkBox fan control on Linux).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/lmnikolaev/larkbox-fan/main/install.sh | sudo sh
#
# Downloads the latest .deb from GitHub Releases and installs it with apt.
# Works on Debian/Ubuntu and derivatives with systemd 253+.
set -eu

REPO="lmnikolaev/larkbox-fan"
API="https://api.github.com/repos/$REPO/releases/latest"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | sudo sh"
command -v apt-get >/dev/null 2>&1 || die "apt not found. This installer is for Debian/Ubuntu; see README for manual installation."
command -v systemctl >/dev/null 2>&1 || die "systemd not found."

# Downloader: curl or wget
if command -v curl >/dev/null 2>&1; then
    fetch()    { curl -fsSL "$1"; }
    fetch_to() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch()    { wget -qO- "$1"; }
    fetch_to() { wget -qO "$2" "$1"; }
else
    die "neither curl nor wget is installed (sudo apt install curl)."
fi

# Sanity checks (warn only: the service itself refuses to run elsewhere)
model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)
case "$model" in
    LarkBox*) say "Detected: Chuwi $model" ;;
    *) warn "this does not look like a Chuwi LarkBox (product name: '$model'). The service will stay inactive on this machine." ;;
esac
if ! grep -qx SEN4 /sys/class/thermal/thermal_zone*/type 2>/dev/null; then
    warn "no SEN4 thermal zone found right now (it may appear later during boot)."
fi

# Find the .deb of the latest release
say "Looking up the latest release of $REPO"
url=$(fetch "$API" | grep -o '"browser_download_url": *"[^"]*\.deb"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/')
[ -n "$url" ] || die "could not find a .deb in the latest release ($API)."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chmod 755 "$tmp"
deb="$tmp/$(basename "$url")"
say "Downloading $(basename "$url")"
fetch_to "$url" "$deb"
chmod 644 "$deb"   # let apt's sandbox user read it

# A hand-made service with the same name would override the packaged one
old=/etc/systemd/system/larkbox-fan.service
if [ -f "$old" ] && [ ! -L "$old" ]; then
    warn "found a hand-made $old - moving it to $old.bak"
    systemctl disable --now larkbox-fan.service >/dev/null 2>&1 || true
    mv "$old" "$old.bak"
    systemctl daemon-reload
fi

say "Installing"
apt-get install -y "$deb"

echo
if systemctl is-active --quiet larkbox-fan.service; then
    say "Done: larkbox-fan is running."
    journalctl -u larkbox-fan.service -n 1 --no-pager -o cat 2>/dev/null || true
else
    warn "larkbox-fan is installed but not running. Check: systemctl status larkbox-fan"
fi
