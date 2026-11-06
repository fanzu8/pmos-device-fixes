#!/bin/sh
# Build the patched snd-soc-wcd934x.ko for the OnePlus 6 postmarketOS kernel.
#
# Usage:
#   ./scripts/build-module.sh <kernel-source-dir> [config]
#
# Defaults:
#   config = config/kernel-6.16.7.config
#
# Examples:
#   ./scripts/build-module.sh /path/to/linux-sdm845-6.16.7-r0
#   ./scripts/build-module.sh /path/to/linux-sdm845-7.1-rc1-r0 config/kernel-7.1.config
#
# Requirements: Docker (arm64), the matching kernel source tree.
set -eu

SRC=${1:?usage: $0 <kernel-source-dir> [config]}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG=${2:-$ROOT/config/kernel-6.16.7.config}
PATCH="$ROOT/patches/0001-ASoC-codecs-wcd934x-enable-MCLK-for-the-capture-path.patch"
OUT="$ROOT/out"

[ -d "$SRC/sound/soc/codecs" ] || { echo "not a kernel source tree: $SRC" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "missing config: $CONFIG" >&2; exit 1; }
[ -f "$PATCH" ] || { echo "missing patch: $PATCH" >&2; exit 1; }

cd "$SRC"
cp "$CONFIG" .config

if ! grep -q 'ADC/DMIC blocks need the codec MCLK' sound/soc/codecs/wcd934x.c; then
	patch -p1 < "$PATCH"
fi

# BTF is not needed for a loadable module and would require pahole + vmlinux.
if grep -q '^CONFIG_DEBUG_INFO_BTF=y' .config; then
	./scripts/config --file .config -d DEBUG_INFO_BTF -d DEBUG_INFO_BTF_MODULES
fi

mkdir -p "$OUT"
docker run --rm -u 0 \
	-v "$PWD:/src" \
	-v "$OUT:/out" \
	-w /src \
	alpine:3.23 sh -c '
		set -e
		apk add --no-cache build-base clang lld llvm make bc bison flex perl \
			openssl openssl-dev elfutils-dev zstd python3 kmod >/dev/null
		make ARCH=arm64 LLVM=1 olddefconfig
		make ARCH=arm64 LLVM=1 \
			HOSTCFLAGS_sign-file.o="-I$(pwd)/include/uapi -I$(pwd)/arch/arm64/include/uapi -I$(pwd)/arch/arm64/include/generated/uapi -I$(pwd)/tools/include/uapi" \
			modules_prepare -j"$(nproc)"
		make ARCH=arm64 LLVM=1 \
			HOSTCFLAGS_sign-file.o="-I$(pwd)/include/uapi -I$(pwd)/arch/arm64/include/uapi -I$(pwd)/arch/arm64/include/generated/uapi -I$(pwd)/tools/include/uapi" \
			M=sound/soc/codecs KBUILD_MODPOST_WARN=1 modules -j"$(nproc)"
		modinfo -F vermagic sound/soc/codecs/snd-soc-wcd934x.ko > /out/VERMAGIC.txt
		zstd -19 -f -o /out/snd-soc-wcd934x.ko.zst sound/soc/codecs/snd-soc-wcd934x.ko
	'

cd "$OUT"
if command -v shasum >/dev/null 2>&1; then
	shasum -a 256 snd-soc-wcd934x.ko.zst | awk '{print $1"  snd-soc-wcd934x.ko.zst"}' \
		> snd-soc-wcd934x.ko.zst.sha256
else
	sha256sum snd-soc-wcd934x.ko.zst > snd-soc-wcd934x.ko.zst.sha256
fi

echo "Built: $OUT/snd-soc-wcd934x.ko.zst"
echo "Vermagic: $(cat VERMAGIC.txt)"
