#!/bin/sh
# Install a prebuilt module + UCM files on the phone over USB networking.
#
# Usage:
#   ./scripts/install-on-phone.sh
#   MODULE=path/to/snd-soc-wcd934x.ko.zst ./scripts/install-on-phone.sh
#
# The phone must be reachable at 172.16.42.1 (postmarketOS USB networking).
set -eu

PHONE=${PHONE:-user@172.16.42.1}
MODULE=${MODULE:-"$(cd "$(dirname "$0")/.." && pwd)/prebuilt/snd-soc-wcd934x.ko.zst"}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

[ -f "$MODULE" ] || { echo "missing module: $MODULE" >&2; exit 1; }

KVER=$(ssh "$PHONE" 'uname -r')
echo "phone kernel: $KVER"

if command -v zstd >/dev/null 2>&1; then
	VM=$(zstd -dc "$MODULE" 2>/dev/null | strings | grep -m1 '^vermagic=' | cut -d= -f2- || true)
	if [ -n "$VM" ] && [ "${VM#"$KVER "}" = "$VM" ]; then
		echo "warning: module vermagic does not match phone kernel:" >&2
		echo "  module: $VM" >&2
		echo "  phone:  $KVER" >&2
		[ "${FORCE:-0}" = "1" ] || { echo "set FORCE=1 to install anyway" >&2; exit 1; }
	fi
fi

scp "$MODULE" "$PHONE:/tmp/snd-soc-wcd934x.ko.zst"
scp "$ROOT/ucm/HiFi.conf" "$PHONE:/tmp/"
scp "$ROOT/ucm/VoiceCall.conf" "$PHONE:/tmp/"

ssh "$PHONE" "sudo sh -s '$KVER'" <<'EOS'
set -eu
KVER=$1
MOD=/lib/modules/$KVER/kernel/sound/soc/codecs/snd-soc-wcd934x.ko.zst
UCM=/usr/share/alsa/ucm2/OnePlus/enchilada

[ -d "/lib/modules/$KVER" ] || { echo "no module dir for $KVER"; exit 1; }
if [ ! -f /root/snd-soc-wcd934x.ko.zst.orig ]; then
	cp -a "$MOD" /root/snd-soc-wcd934x.ko.zst.orig
fi
install -m 644 /tmp/snd-soc-wcd934x.ko.zst "$MOD"
depmod -a "$KVER"

install -m 644 /tmp/HiFi.conf "$UCM/HiFi.conf"
install -m 644 /tmp/VoiceCall.conf "$UCM/VoiceCall.conf"

echo "Installed for $KVER. Reboot required to load the new module:"
echo "  sudo reboot"
EOS
