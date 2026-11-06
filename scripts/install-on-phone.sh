#!/bin/sh
# Install the prebuilt module + UCM files on the phone over USB networking.
#
# Usage:
#   PHONE=user@172.16.42.1 ./scripts/install-on-phone.sh
#
# The phone must be reachable at 172.16.42.1 (postmarketOS USB networking).
set -eu

PHONE=${PHONE:-user@172.16.42.1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

[ -f "$ROOT/prebuilt/snd-soc-wcd934x.ko.zst" ] || {
	echo "missing prebuilt/snd-soc-wcd934x.ko.zst" >&2
	exit 1
}

scp "$ROOT/prebuilt/snd-soc-wcd934x.ko.zst" "$PHONE:/tmp/"
scp "$ROOT/ucm/HiFi.conf" "$PHONE:/tmp/"
scp "$ROOT/ucm/VoiceCall.conf" "$PHONE:/tmp/"

ssh "$PHONE" 'sudo sh -s' <<'EOS'
set -eu
MOD=/lib/modules/6.16.7-sdm845/kernel/sound/soc/codecs/snd-soc-wcd934x.ko.zst
UCM=/usr/share/alsa/ucm2/OnePlus/enchilada

if [ ! -f /root/snd-soc-wcd934x.ko.zst.orig ]; then
	cp -a "$MOD" /root/snd-soc-wcd934x.ko.zst.orig
fi
install -m 644 /tmp/snd-soc-wcd934x.ko.zst "$MOD"
depmod -a 6.16.7-sdm845

install -m 644 /tmp/HiFi.conf "$UCM/HiFi.conf"
install -m 644 /tmp/VoiceCall.conf "$UCM/VoiceCall.conf"

echo "Installed. Reboot required to load the new module:"
echo "  sudo reboot"
EOS
