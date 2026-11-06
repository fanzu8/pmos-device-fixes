#!/bin/sh
# Build the patched snd-soc-wcd934x.ko for the OnePlus 6 postmarketOS kernel.
#
# Usage:
#   ./scripts/build-module.sh /path/to/linux-sdm845-6.16.7-r0
#
# Requirements: Docker (arm64), the kernel source tree at tag sdm845-6.16.7-r0.
set -eu

SRC=${1:?usage: $0 <linux-sdm845-6.16.7-r0 source dir>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATCH="$ROOT/patches/0001-ASoC-codecs-wcd934x-enable-MCLK-for-the-capture-path.patch"
CONFIG="$ROOT/config/kernel.config"
OUT="$ROOT/out"

[ -d "$SRC/sound/soc/codecs" ] || { echo "not a kernel source tree: $SRC" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "missing patch: $PATCH" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "missing config: $CONFIG" >&2; exit 1; }

cd "$SRC"
cp "$CONFIG" .config

if ! grep -q 'ADC/DMIC blocks need the codec MCLK' sound/soc/codecs/wcd934x.c; then
	patch -p1 < "$PATCH"
fi

mkdir -p "$OUT"
docker run --rm -u 0 \
	-v "$PWD:/src" \
	-v "$OUT:/out" \
	-w /src \
	alpine:3.23 sh -c '
		set -e
		apk add --no-cache build-base clang lld llvm make bc bison flex perl \
			openssl-dev elfutils-dev zstd python3 >/dev/null
		make ARCH=arm64 LLVM=1 olddefconfig
		make ARCH=arm64 LLVM=1 modules_prepare -j"$(nproc)"
		make ARCH=arm64 LLVM=1 M=sound/soc/codecs KBUILD_MODPOST_WARN=1 modules -j"$(nproc)"
		zstd -19 -f -o /out/snd-soc-wcd934x.ko.zst sound/soc/codecs/snd-soc-wcd934x.ko
	'

cd "$OUT"
shasum -a 256 snd-soc-wcd934x.ko.zst 2>/dev/null \
	| awk '{print $1"  snd-soc-wcd934x.ko.zst"}' \
	> snd-soc-wcd934x.ko.zst.sha256 \
	|| sha256sum snd-soc-wcd934x.ko.zst > snd-soc-wcd934x.ko.zst.sha256

echo "Built: $OUT/snd-soc-wcd934x.ko.zst"
echo "Expected vermagic: 6.16.7-sdm845 SMP preempt mod_unload aarch64"
